import 'dart:io';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// PERMISSION: camera permission ke liye
import 'package:permission_handler/permission_handler.dart';
import 'package:snapkeep/core/categories/category_store.dart';

import '../../../../core/notifications/notification_service.dart';
import '../../../../core/notifications/permission_sheet.dart';
import '../../../../core/notifications/snooze_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../categories/presentation/category_store.dart';
import '../../../data/saved_items_storage.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../models/saved_item.dart';
import 'screenshot_details_screen.dart';

/// What the viewer asks the home screen to do when it closes.
enum _ScreenshotAction { edit, delete, done, snooze }

enum _ViewMode { grid, list }

// ───────────────────────── HELPERS ─────────────────────────

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _overdueColor = Color(0xFFD6574E);

String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

Color _muted([double a = 0.6]) => AppColors.text.withValues(alpha: a);

int _daysUntil(DateTime d) =>
    DateUtils.dateOnly(d).difference(DateUtils.dateOnly(DateTime.now())).inDays;

/// Reminder time has passed and the item is not done.
bool _isMissed(SavedItem item) {
  final r = item.reminderDate;
  return r != null && !item.isDone && r.isBefore(DateTime.now());
}

/// "Missed", "Today", "Tomorrow", "In 3 days", or a plain date.
String _when(DateTime d) {
  final diff = _daysUntil(d);
  if (diff < 0) return 'Missed';
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff <= 7) return 'In $diff days';
  return _formatDate(d);
}

Color _whenColor(DateTime d) {
  final diff = _daysUntil(d);
  if (diff < 0) return _overdueColor;
  if (diff <= 1) return AppColors.accent;
  return _muted(0.6);
}

/// "8:35 PM" style time, independent of BuildContext.
String _timeShort(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $period';
}

/// Short label for the image badge: "Today 8:35 PM", "Tomorrow 9:00 AM",
/// "12 Jun 9:00 AM".
String _badgeText(DateTime d) {
  final diff = _daysUntil(d);
  if (diff == 0) return 'Today ${_timeShort(d)}';
  if (diff == 1) return 'Tomorrow ${_timeShort(d)}';
  return '${d.day} ${_months[d.month - 1]} ${_timeShort(d)}';
}

String _heroTag(SavedItem item) => 'img_${item.id}';

/// Image that fades in instead of popping.
Widget _fadeImage(
  File file, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  required Widget Function() onError,
}) {
  return Image.file(
    file,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, _, _) => onError(),
    frameBuilder: (context, child, frame, sync) {
      if (sync) return child;
      return AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: child,
      );
    },
  );
}

/// Reminder pill shown on the bottom-left of a grid card.
/// Red when missed, accent when today or tomorrow, dark otherwise.
Widget _reminderBadge(DateTime date) {
  final missed = date.isBefore(DateTime.now());
  final soon = _daysUntil(date) <= 1;

  final Color background;
  if (missed) {
    background = _overdueColor;
  } else if (soon) {
    background = AppColors.accent;
  } else {
    background = Colors.black.withValues(alpha: 0.55);
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          missed
              ? Icons.error_outline_rounded
              : Icons.notifications_active_rounded,
          size: 11,
          color: Colors.white,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            missed ? 'Missed' : _badgeText(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Check pill shown on the top-left of a done card.
Widget _donePill() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, size: 12, color: Colors.white),
        SizedBox(width: 3),
        Text(
          'Done',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Small tag shown after a reminder was moved by a snooze.
Widget _snoozedTag() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.softAccent,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      'Snoozed',
      style: TextStyle(
        color: AppColors.accent,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ───────────────────────── SCREEN ─────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<SavedItem> _items = [];
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'All';
  _ViewMode _viewMode = _ViewMode.grid;

  final SavedItemsStorage _storage = SavedItemsStorage.instance;
  bool _loading = true;

  /// All, then every category (built-in + user), then Done.
  List<String> get _categories => [
    'All',
    ...CategoryStore.categories.value,
    'Done',
  ];

  /// Number of items shown under a category chip. Matches _filteredItems
  /// (without the search text), so the count always equals the list.
  int _countFor(String category) {
    return _items.where((item) {
      return switch (category) {
        'All' => !item.isDone,
        'Done' => item.isDone,
        _ => !item.isDone && item.category == category,
      };
    }).length;
  }

  // Done items are hidden from every category except "Done".
  List<SavedItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();

    return _items.where((item) {
      final matchesCategory = switch (_selectedCategory) {
        'All' => !item.isDone,
        'Done' => item.isDone,
        _ => !item.isDone && item.category == _selectedCategory,
      };

      final matchesSearch =
          query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.note.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);

      return matchesCategory && matchesSearch;
    }).toList();
  }

  /// Every active reminder that is missed or within the next 7 days.
  List<SavedItem> get _upcomingAll {
    final list =
        _items
            .where(
              (i) =>
                  !i.isDone &&
                  i.reminderDate != null &&
                  _daysUntil(i.reminderDate!) <= 7,
            )
            .toList()
          ..sort((a, b) => a.reminderDate!.compareTo(b.reminderDate!));

    return list;
  }

  /// Only the first three are shown on the card.
  List<SavedItem> get _upcoming => _upcomingAll.take(3).toList();

  @override
  void initState() {
    super.initState();

    _loadItemsAndReschedule();

    // A snooze changed the stored data. Reload the list only.
    NotificationService.changes.addListener(_onExternalChange);

    // A category was added or removed.
    CategoryStore.categories.addListener(_onCategoriesChanged);

    // App opened from a notification button: show the custom sheet now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.flushPending();
    });
  }

  @override
  void dispose() {
    NotificationService.changes.removeListener(_onExternalChange);
    CategoryStore.categories.removeListener(_onCategoriesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onExternalChange() {
    _reloadList();
  }

  /// A category was added or removed. If the selected chip is gone, go back
  /// to All. Then reload, because removed items now belong to Other.
  void _onCategoriesChanged() {
    setState(() {
      if (!_categories.contains(_selectedCategory)) {
        _selectedCategory = 'All';
      }
    });
    _reloadList();
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Text(message),
        ),
      );
  }

  /// Short confirmation message (not an error).
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(message),
        ),
      );
  }

  /// Runs a storage write. On failure, shows [message] with the error.
  Future<void> _runStorage(
    Future<void> Function() operation,
    String message,
  ) async {
    try {
      await operation();
    } catch (e) {
      _showError('$message\n$e');
    }
  }

  // ───────────────────────── LOAD ─────────────────────────

  /// Reads the list from storage. Does not touch notifications.
  Future<void> _reloadList() async {
    try {
      final loaded = await _storage.load();
      if (!mounted) return;

      setState(() {
        _items
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _showError(
        'Could not load saved items.\n'
        'If you just added packages, STOP the app and run it again '
        '(hot restart is not enough).\n$e',
      );
    }
  }

  /// Only at app start: reload, then make sure every future reminder has its
  /// system notification.
  Future<void> _loadItemsAndReschedule() async {
    await _reloadList();
    if (!mounted) return;

    NotificationService.instance.rescheduleAll(List<SavedItem>.of(_items));
  }

  // ───────────────────────── NOTIFICATIONS ─────────────────────────

  /// Creates, replaces or removes the system notification of [item].
  Future<void> _syncReminder(
    SavedItem item, {
    bool askPermission = true,
  }) async {
    try {
      if (item.reminderDate == null) {
        await NotificationService.instance.cancel(item);
        return;
      }

      if (askPermission) {
        final result = await ensureReminderPermission(context);

        switch (result) {
          case ReminderPermission.granted:
            break;
          case ReminderPermission.skipped:
            _showError(
              'Reminder saved. Notifications are off, so it will not alert you '
              'until you turn them on in Settings.',
            );
          case ReminderPermission.denied:
            if (mounted) {
              await _showSettingsDialog(
                title: 'Notifications are off',
                message:
                    'Allow notifications for SnapKeep in Settings, so your '
                    'reminders can alert you on time.',
              );
            }
        }
      }

      // Scheduled even when skipped. It starts working once the user
      // turns notifications on later.
      await NotificationService.instance.schedule(item);
    } catch (e) {
      _showError('Could not schedule the reminder.\n$e');
    }
  }

  // ───────────────────────── PERMISSION DIALOGS ─────────────────────────

  /// "Open Settings" dialog, used for camera and notifications.
  Future<void> _showSettingsDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: _muted(0.7), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Not now', style: TextStyle(color: _muted(0.6))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: Text(
              'Open Settings',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // PERMISSION: Camera kholne se pehle permission check / request karta hai.
  // true  = camera use kar sakte hain.
  // false = permission nahi mili, camera nahi kholna.
  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    // Pehli baar (ya Android par ek baar deny ke baad): system popup.
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await Permission.camera.request();
      if (status.isGranted) return true;
    }

    if (!mounted) return false;

    if (status.isPermanentlyDenied || status.isRestricted) {
      // User popup nahi dekh sakta ab, Settings se hi ON ho sakta hai.
      await _showSettingsDialog(
        title: 'Camera access is off',
        message:
            'To take a photo, allow camera access for SnapKeep in Settings.',
      );
    } else {
      _showError('Camera permission is needed to take a photo.');
    }
    return false;
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  /// "+" dabane par Camera / Gallery ka choice dikhata hai.
  void _showAddSheet() {
    HapticFeedback.selectionClick();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addScreenshot(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addScreenshot(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addScreenshot(ImageSource source) async {
    // PERMISSION: camera sirf tab khulega jab permission mil jaye.
    if (source == ImageSource.camera) {
      final allowed = await _ensureCameraPermission();
      if (!allowed || !mounted) return;
    }

    try {
      // Gallery pehle jaisi hi hai. Sirf camera photo ko chhota karte hain,
      // kyunki camera ki photo bahut badi hoti hai.
      final image = source == ImageSource.camera
          ? await _picker.pickImage(
              source: source,
              imageQuality: 85,
              maxWidth: 1920,
            )
          : await _picker.pickImage(source: source);

      if (image == null || !mounted) return;

      final savedItem = await Navigator.of(context).push<SavedItem>(
        MaterialPageRoute(
          builder: (_) => ScreenshotDetailsScreen(image: File(image.path)),
        ),
      );

      if (savedItem == null || !mounted) return;

      HapticFeedback.lightImpact();

      // Copy the screenshot into the app folder so it survives restarts.
      final SavedItem stored;
      try {
        stored = await _storage.persistImage(savedItem);
      } catch (e) {
        _showError('Could not store the screenshot.\n$e');
        return;
      }
      if (!mounted) return;

      setState(() => _items.insert(0, stored));

      await _runStorage(
        () => _storage.insertItem(stored),
        'Could not save your data.',
      );

      _syncReminder(stored);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editItem(SavedItem item) async {
    final updatedItem = await Navigator.of(context).push<SavedItem>(
      MaterialPageRoute(
        builder: (_) =>
            ScreenshotDetailsScreen(image: item.image, initialItem: item),
      ),
    );

    if (updatedItem == null || !mounted) return;

    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    // If the image was replaced, copy the new one into the app folder.
    var edited = updatedItem;
    final imageChanged = updatedItem.image.path != item.image.path;

    if (imageChanged) {
      try {
        edited = await _storage.persistImage(updatedItem);
      } catch (e) {
        _showError('Could not store the new image.\n$e');
        return;
      }
      if (!mounted) return;
    }

    // Same reminder as before: keep the snoozed state.
    // Reminder changed by hand: it is no longer a snooze.
    final cleaned = updatedItem.reminderDate == item.reminderDate
        ? edited.copyWith(wasSnoozed: item.wasSnoozed)
        : edited.copyWith(wasSnoozed: false);

    setState(() => _items[index] = cleaned);

    await _runStorage(
      () => _storage.replaceItem(cleaned),
      'Could not save your changes.',
    );

    // The old image is not needed anymore. Never delete it if the stored
    // copy happens to use the same path.
    if (imageChanged && edited.image.path != item.image.path) {
      _storage.deleteImage(item.image);
    }

    _syncReminder(cleaned);
  }

  /// Marks the item done. Cancels its notification and clears the reminder.
  /// Undoing it only marks it not done; the reminder must be set again.
  Future<void> _toggleDone(SavedItem item) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    final nowDone = !item.isDone;
    final updated = nowDone
        ? item.copyWith(isDone: true, clearReminder: true)
        : item.copyWith(isDone: false);

    HapticFeedback.lightImpact();
    setState(() => _items[index] = updated);

    if (nowDone) {
      await NotificationService.instance.cancel(item);
    }

    await _runStorage(
      () => _storage.setDone(item.id, nowDone),
      'Could not update the item.',
    );
  }

  /// Snooze from the viewer: pick a time, then move the reminder.
  Future<void> _snoozeFromViewer(SavedItem item) async {
    final picked = await showSnoozeSheet(context);
    if (picked == null || !mounted) return;

    HapticFeedback.lightImpact();
    await NotificationService.instance.snoozeItem(item, picked);

    _showMessage('Snoozed to ${_when(picked)} · ${_timeShort(picked)}');
  }

  /// Deletes immediately and offers Undo (no confirmation dialog).
  /// The image file is removed only after the Undo bar has gone away.
  Future<void> _deleteItem(SavedItem item) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    HapticFeedback.mediumImpact();
    setState(() => _items.removeAt(index));

    var undone = false;

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();

    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            // Action wale snackbar ko Flutter default mein hatata nahi hai,
            // isliye persist: false zaroori hai.
            persist: false,
            // Left ya right swipe karke hata sakte hain.
            dismissDirection: DismissDirection.horizontal,
            content: const Text('Screenshot deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                undone = true;
                if (!mounted) return;

                setState(() {
                  _items.insert(index.clamp(0, _items.length), item);
                });

                _runStorage(
                  () => _storage.insertItem(item, index: index),
                  'Could not restore the item.',
                );
                _syncReminder(item, askPermission: false);
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (!undone) _storage.deleteImage(item.image);
        });

    await NotificationService.instance.cancel(item);

    await _runStorage(
      () => _storage.removeItem(item.id),
      'Could not delete the item.',
    );
  }

  Future<void> _openScreenshot(SavedItem item) async {
    final action = await Navigator.of(context).push<_ScreenshotAction>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScreenshotViewer(item: item),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _ScreenshotAction.delete:
        await _deleteItem(item);
      case _ScreenshotAction.edit:
        await _editItem(item);
      case _ScreenshotAction.done:
        await _toggleDone(item);
        _showMessage(
          item.isDone ? 'Moved back to your list' : 'Marked as done',
        );
      case _ScreenshotAction.snooze:
        await _snoozeFromViewer(item);
    }
  }

  void _showItemMenu(SavedItem item) {
    HapticFeedback.selectionClick();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editItem(item);
              },
            ),
            ListTile(
              leading: Icon(
                item.isDone
                    ? Icons.undo_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              title: Text(item.isDone ? 'Mark as not done' : 'Mark as done'),
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleDone(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _overdueColor),
              title: const Text(
                'Delete',
                style: TextStyle(color: _overdueColor),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildTopBar()),
                SliverToBoxAdapter(child: _buildSearch()),
                SliverToBoxAdapter(child: _buildCategories()),
                SliverToBoxAdapter(child: _buildUpcoming()),
                SliverToBoxAdapter(child: _buildCount(items.length)),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else if (_viewMode == _ViewMode.grid)
                  _buildGrid(items)
                else
                  _buildList(items),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_rounded, size: 26),
      ),
    );
  }

  // ───────────────────────── TOP ─────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
      child: Row(
        children: [
          Text(
            'SnapKeep',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Categories',
            onPressed: () => showCategorySheet(context),
            icon: Icon(
              Icons.label_outline_rounded,
              size: 21,
              color: _muted(0.7),
            ),
          ),
          IconButton(
            tooltip: _viewMode == _ViewMode.grid ? 'List view' : 'Grid view',
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.grid
                  ? _ViewMode.list
                  : _ViewMode.grid;
            }),
            icon: Icon(
              _viewMode == _ViewMode.grid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded,
              size: 21,
              color: _muted(0.7),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: Icon(Icons.settings_outlined, size: 21, color: _muted(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        cursorColor: AppColors.accent,
        style: TextStyle(color: AppColors.text, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: _muted(0.45), fontSize: 14.5),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: _muted(0.5)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: Icon(Icons.close_rounded, size: 18, color: _muted(0.6)),
                )
              : null,
          filled: true,
          fillColor: _muted(0.05),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// Horizontal, scrollable category chips. The count is hidden when 0.
  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: _categories.map((category) {
            final selected = _selectedCategory == category;
            final count = _countFor(category);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedCategory = category),
              child: Padding(
                padding: const EdgeInsets.only(right: 18, bottom: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: category,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected ? AppColors.text : _muted(0.5),
                            ),
                          ),
                          if (count > 0)
                            TextSpan(
                              text: ' $count',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? AppColors.accent
                                    : _muted(0.4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 1.5,
                      width: selected ? 16 : 0,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ───────────────────────── COMING UP ─────────────────────────

  Widget _buildUpcoming() {
    final isFiltering =
        _selectedCategory != 'All' || _searchController.text.isNotEmpty;
    final upcoming = _upcoming;
    final hiddenCount = _upcomingAll.length - upcoming.length;

    if (isFiltering || upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Coming up',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Count sirf tab, jab card mein sab items na aa paye hon.
              if (hiddenCount > 0)
                Text(
                  '+$hiddenCount more',
                  style: TextStyle(color: _muted(0.55), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Column(
              children: [
                for (int i = 0; i < upcoming.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 0.6, color: _muted(0.1)),
                  _upcomingRow(upcoming[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingRow(SavedItem item) {
    final date = item.reminderDate!;
    final color = _whenColor(date);
    final missed = _isMissed(item);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openScreenshot(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Status dot: red missed, green today/tomorrow, grey later.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _fadeImage(
                item.image,
                width: 36,
                height: 36,
                onError: () =>
                    SizedBox(width: 36, height: 36, child: _brokenImage()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_when(date)} · ${_timeShort(date)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.wasSnoozed) ...[
                    const SizedBox(height: 4),
                    _snoozedTag(),
                  ],
                  if (missed) ...[
                    const SizedBox(height: 8),
                    _missedActions(item),
                  ],
                ],
              ),
            ),
            if (!missed)
              Icon(Icons.chevron_right_rounded, size: 20, color: _muted(0.35)),
          ],
        ),
      ),
    );
  }

  /// Quick actions shown under a missed reminder.
  Widget _missedActions(SavedItem item) {
    return Row(
      children: [
        _smallAction(
          label: 'Snooze 10 min',
          icon: Icons.snooze_rounded,
          onTap: () => _quickSnooze(item, const Duration(minutes: 10)),
        ),
        const SizedBox(width: 8),
        _smallAction(
          label: 'Done',
          icon: Icons.check_rounded,
          filled: true,
          onTap: () => _toggleDone(item),
        ),
      ],
    );
  }

  Widget _smallAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final foreground = filled ? Colors.white : AppColors.accent;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : AppColors.softAccent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickSnooze(SavedItem item, Duration duration) async {
    HapticFeedback.lightImpact();
    await NotificationService.instance.snoozeItem(
      item,
      DateTime.now().add(duration),
    );
  }

  Widget _buildCount(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Text(
        count == 1 ? '1 item' : '$count items',
        style: TextStyle(color: _muted(0.55), fontSize: 12.5),
      ),
    );
  }

  // ───────────────────────── EMPTY ─────────────────────────

  Widget _buildEmptyState() {
    final isSearching =
        _searchController.text.isNotEmpty || _selectedCategory != 'All';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isSearching ? 'No results' : 'Nothing saved yet',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching
                ? 'Try a different search or category.'
                : 'Tap + to add your first screenshot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted(0.6), fontSize: 13.5),
          ),
          if (isSearching) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => setState(() {
                _searchController.clear();
                _selectedCategory = 'All';
              }),
              child: Text(
                'Clear filters',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── GRID ─────────────────────────

  Widget _buildGrid(List<SavedItem> items) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700 ? 3 : 2;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 24,
          crossAxisSpacing: 16,
          childAspectRatio: 0.62, // taller cells: screenshots are portrait
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _gridItem(items[index]),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _gridItem(SavedItem item) {
    final done = item.isDone;
    final reminder = item.reminderDate;

    return GestureDetector(
      onTap: () => _openScreenshot(item),
      onLongPress: () => _showItemMenu(item),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Hero(
                    tag: _heroTag(item),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // Done items are faded so active reminders stand out.
                      child: Opacity(
                        opacity: done ? 0.55 : 1,
                        child: _fadeImage(item.image, onError: _brokenImage),
                      ),
                    ),
                  ),
                ),
                if (done) Positioned(top: 8, left: 8, child: _donePill()),
                if (reminder != null && !done && item.wasSnoozed)
                  Positioned(top: 8, right: 8, child: _snoozedTag()),
                if (reminder != null && !done)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _reminderBadge(reminder),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: done ? _muted(0.5) : AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: _muted(0.5),
            ),
          ),
          const SizedBox(height: 2),
          _metaText(item),
        ],
      ),
    );
  }

  /// "Category" or "Category · Tomorrow" (reminder part is coloured).
  Widget _metaText(SavedItem item) {
    return Text.rich(
      TextSpan(
        style: TextStyle(color: _muted(0.6), fontSize: 12),
        children: [
          TextSpan(text: item.category),
          if (item.reminderDate != null) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: _when(item.reminderDate!),
              style: TextStyle(
                color: _whenColor(item.reminderDate!),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ───────────────────────── LIST ─────────────────────────

  Widget _buildList(List<SavedItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, thickness: 0.6, color: _muted(0.1)),
        itemBuilder: (context, index) {
          final item = items[index];

          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _deleteItem(item),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: _overdueColor.withValues(alpha: 0.10),
              child: const Icon(Icons.delete_outline, color: _overdueColor),
            ),
            child: _listRow(item),
          );
        },
      ),
    );
  }

  Widget _listRow(SavedItem item) {
    final done = item.isDone;

    return InkWell(
      onTap: () => _openScreenshot(item),
      onLongPress: () => _showItemMenu(item),
      child: Container(
        color: AppColors.surface, // keeps swipe background hidden at rest
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: done ? 0.55 : 1,
                child: _fadeImage(
                  item.image,
                  width: 54,
                  height: 54,
                  onError: () =>
                      SizedBox(width: 54, height: 54, child: _brokenImage()),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: done ? _muted(0.5) : AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: _muted(0.5),
                    ),
                  ),
                  if (item.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted(0.6), fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 3),
                  _metaText(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brokenImage() {
    return Container(
      color: _muted(0.06),
      child: Icon(Icons.broken_image_outlined, color: _muted(0.4)),
    );
  }
}

// ───────────────────────── VIEWER ─────────────────────────

class _ScreenshotViewer extends StatelessWidget {
  const _ScreenshotViewer({required this.item});

  final SavedItem item;

  static const _bg = Color(0xFF0E0E0E);
  static const _cardColor = Color(0xFF181818);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hPad = size.width >= 600 ? 32.0 : 24.0;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Soft blurred copy of the screenshot behind everything.
          Positioned.fill(child: _backdrop()),

          SafeArea(
            // The card runs down to the bottom edge and adds its own inset.
            bottom: false,
            child: Column(
              children: [
                _topBar(context),

                // The image takes all the space the card does not need.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Center(
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 5,
                        child: Hero(
                          tag: _heroTag(item),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.file(
                              item.image,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 60,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                _infoCard(context, size, hPad),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── BACKDROP ─────────────────────────

  Widget _backdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 40,
            sigmaY: 40,
            tileMode: TileMode.mirror,
          ),
          child: Image.file(
            item.image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        // Dark layer keeps the text readable whatever the image colours are.
        Container(color: _bg.withValues(alpha: 0.74)),
      ],
    );
  }

  // ───────────────────────── TOP BAR ─────────────────────────

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _roundButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
          _roundButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onTap: () => Navigator.pop(context, _ScreenshotAction.edit),
          ),
          const SizedBox(width: 10),
          _roundButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            tint: const Color(0xFFFF8A80),
            onTap: () => Navigator.pop(context, _ScreenshotAction.delete),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color tint = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tint.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Icon(icon, color: tint, size: 21)),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── INFO CARD ─────────────────────────

  Widget _infoCard(BuildContext context, Size size, double hPad) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final reminder = item.reminderDate;
    final missed = _isMissed(item);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardColor.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      // A very long note scrolls inside the card instead of pushing the
      // image off the screen.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.5),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24 + bottomInset),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small handle, purely decorative.
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.2,
                      ),
                    ),

                    if (item.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        item.note,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14.5,
                          height: 1.55,
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          icon: CategoryStore.iconFor(item.category),
                          label: item.category,
                        ),
                        if (item.isDone)
                          _chip(
                            icon: Icons.check_circle_outline_rounded,
                            label: 'Done',
                            color: AppColors.accent,
                          ),
                        if (reminder != null) ...[
                          _chip(
                            icon: Icons.calendar_today_rounded,
                            label:
                                '${_formatDate(reminder)} · ${_timeShort(reminder)}',
                          ),
                          _chip(
                            icon: missed
                                ? Icons.error_outline_rounded
                                : Icons.notifications_active_outlined,
                            label: missed ? 'Missed' : _when(reminder),
                            color: _statusColor(reminder, missed),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 22),
                    _actionRow(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Snooze (only while a reminder is active) and Done / Mark not done.
  Widget _actionRow(BuildContext context) {
    final canSnooze = !item.isDone && item.reminderDate != null;

    return Row(
      children: [
        if (canSnooze) ...[
          Expanded(
            child: _actionButton(
              icon: Icons.snooze_rounded,
              label: 'Snooze',
              onTap: () => Navigator.pop(context, _ScreenshotAction.snooze),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: _actionButton(
            icon: item.isDone ? Icons.undo_rounded : Icons.check_rounded,
            label: item.isDone ? 'Mark not done' : 'Done',
            filled: !item.isDone,
            onTap: () => Navigator.pop(context, _ScreenshotAction.done),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final foreground = filled ? Colors.white : AppColors.accent;

    return Material(
      color: filled
          ? AppColors.accent
          : AppColors.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(DateTime reminder, bool missed) {
    if (missed) return _overdueColor;
    if (_daysUntil(reminder) <= 1) return AppColors.accent;
    return Colors.white70;
  }

  Widget _chip({
    required IconData icon,
    required String label,
    Color color = Colors.white70,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
