import 'dart:io';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:snapkeep/core/notifications/snooze_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:snapkeep/core/categories/category_store.dart';

import '../../../../core/notifications/notification_service.dart';
import '../../../../core/notifications/permission_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../categories/presentation/category_store.dart';
import '../../../data/saved_items_storage.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../models/saved_item.dart';
import 'screenshot_details_screen.dart';

enum _ViewMode { grid, list }

enum _ScreenshotAction { edit, delete, done, snooze }

/// What the viewer hands back: the action, and the item that was on screen.
class _ViewerResult {
  const _ViewerResult(this.action, this.item);

  final _ScreenshotAction action;
  final SavedItem item;
}

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

/// Frosted glass: blurs whatever is behind it, then lays a translucent tint
/// and a hairline border on top.
Widget _glass({
  required Widget child,
  BorderRadius? radius,
  double sigma = 16,
  Color? tint,
  Color? borderColor,
}) {
  final r = radius ?? BorderRadius.circular(20);

  return ClipRRect(
    borderRadius: r,
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint ?? AppColors.surface.withValues(alpha: 0.72),
          borderRadius: r,
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: child,
      ),
    ),
  );
}

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

/// Reminder pill (frosted glass) shown on the bottom-left of a grid card.
/// Red when missed, accent when today or tomorrow, dark otherwise.
/// [repeats] shows a repeat icon instead of the bell.
Widget _reminderBadge(DateTime date, {bool repeats = false}) {
  final missed = date.isBefore(DateTime.now());
  final soon = _daysUntil(date) <= 1;

  final Color tint;
  if (missed) {
    tint = _overdueColor.withValues(alpha: 0.85);
  } else if (soon) {
    tint = AppColors.accent.withValues(alpha: 0.85);
  } else {
    tint = Colors.black.withValues(alpha: 0.45);
  }

  return _glass(
    radius: BorderRadius.circular(20),
    sigma: 10,
    tint: tint,
    borderColor: Colors.white.withValues(alpha: 0.18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            missed
                ? Icons.error_outline_rounded
                : (repeats
                      ? Icons.repeat_rounded
                      : Icons.notifications_active_rounded),
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 5),
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
    ),
  );
}

/// Check pill shown on the top-left of a done card.
Widget _donePill() {
  return _glass(
    radius: BorderRadius.circular(20),
    sigma: 10,
    tint: AppColors.accent.withValues(alpha: 0.85),
    borderColor: Colors.white.withValues(alpha: 0.18),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
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
    ),
  );
}

/// Small tag shown after a reminder was moved by a snooze.
/// [onImage] makes it a glass pill that sits on top of a photo.
Widget _snoozedTag({bool onImage = false}) {
  if (onImage) {
    return _glass(
      radius: BorderRadius.circular(20),
      sigma: 10,
      tint: Colors.black.withValues(alpha: 0.45),
      borderColor: Colors.white.withValues(alpha: 0.18),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.snooze_rounded, size: 11, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'Snoozed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

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

/// Round tinted icon button used in the header.
Widget _headerButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: _muted(0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: _muted(0.8)),
          ),
        ),
      ),
    ),
  );
}

/// One row inside a bottom sheet.
Widget _sheetTile({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  Color? color,
}) {
  final c = color ?? AppColors.text;

  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: c),
    ),
    title: Text(
      title,
      style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w500),
    ),
    onTap: onTap,
  );
}

/// Big square option (Camera / Gallery) in the add sheet.
Widget _addOption({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return Material(
    color: _muted(0.06),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: AppColors.accent),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: AppColors.text,
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

// ───────────────────────── SCREEN ─────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final List<SavedItem> _items = [];
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'All';
  _ViewMode _viewMode = _ViewMode.grid;

  final SavedItemsStorage _storage = SavedItemsStorage.instance;
  bool _loading = true;

  // True when the user has notifications turned off for the app.
  bool _notificationsOff = false;

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

    WidgetsBinding.instance.addObserver(this);

    _loadItemsAndReschedule();

    // Check if notifications are allowed.
    _checkNotifications();

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
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.changes.removeListener(_onExternalChange);
    CategoryStore.categories.removeListener(_onCategoriesChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRepeating();
      // The user may have changed the permission in Settings.
      _checkNotifications();
    }
  }

  // Reads the permission (no dialog) and updates the banner.
  Future<void> _checkNotifications() async {
    try {
      final enabled = await NotificationService.instance.notificationsEnabled();
      if (!mounted) return;

      if (_notificationsOff == enabled) {
        setState(() => _notificationsOff = !enabled);
      }
    } catch (e) {
      debugPrint('SnapKeep: could not check notifications: $e');
    }
  }

  // "Turn on" button of the banner.
  Future<void> _enableNotifications() async {
    HapticFeedback.selectionClick();

    final granted = await NotificationService.instance.ensurePermissions();
    if (!mounted) return;

    if (!granted) {
      // Android will not show the system popup again after repeated "Deny",
      // so send the user to the app settings.
      await showNotificationSettingsDialog(context, force: true);
    } else {
      // Make sure every reminder has its system notification now.
      NotificationService.instance.rescheduleAll(List<SavedItem>.of(_items));
    }

    _checkNotifications();
  }

  /// Moves repeating reminders that already passed to their next time.
  Future<void> _refreshRepeating() async {
    try {
      final changed = await _storage.rollRepeating();
      if (!changed || !mounted) return;

      await _reloadList();
      if (!mounted) return;

      NotificationService.instance.rescheduleAll(List<SavedItem>.of(_items));
    } catch (e) {
      debugPrint('SnapKeep: could not refresh repeating reminders: $e');
    }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 8),
          content: Text(message),
        ),
      );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
    try {
      await _storage.rollRepeating();
      // Items deleted more than 30 days ago are removed for good.
      await _storage.purgeExpired();
    } catch (e) {
      debugPrint('SnapKeep: start-up cleanup failed: $e');
    }

    await _reloadList();
    if (!mounted) return;

    NotificationService.instance.rescheduleAll(List<SavedItem>.of(_items));
  }

  // ───────────────────────── NOTIFICATIONS ─────────────────────────

  /// Creates, replaces or removes the system notification of [item].
  /// It never asks for permission by itself. If notifications are off, the
  /// banner at the top tells the user, and its "Turn on" button asks.
  Future<void> _syncReminder(
    SavedItem item, {
    bool askPermission = true,
  }) async {
    try {
      if (item.reminderDate == null) {
        await NotificationService.instance.cancel(item);
        return;
      }

      // Scheduled even when notifications are off. It starts working once
      // the user turns them on.
      await NotificationService.instance.schedule(item);
    } catch (e) {
      _showError('Could not schedule the reminder.\n$e');
    } finally {
      // Shows or hides the banner.
      _checkNotifications();
    }
  }

  // ───────────────────────── CAMERA PERMISSION ─────────────────────────

  // Checks / requests camera permission before the camera opens.
  // true  = camera can be used.
  // false = permission not granted, do not open the camera.
  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    // First time (or after one deny on Android): system popup.
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await Permission.camera.request();
      if (status.isGranted) return true;
    }

    if (!mounted) return false;

    if (status.isPermanentlyDenied || status.isRestricted) {
      // The popup can not be shown any more, only Settings can turn it on.
      await _showCameraSettingsDialog();
    } else {
      _showError('Camera permission is needed to take a photo.');
    }
    return false;
  }

  // "Open Settings" dialog.
  Future<void> _showCameraSettingsDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Camera access is off',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'To take a photo, allow camera access for SnapKeep in Settings.',
          style: TextStyle(color: _muted(0.7), fontSize: 14),
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
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── SHEETS ─────────────────────────

  /// Blurred glass bottom sheet with a drag handle.
  Future<void> _showGlassSheet(WidgetBuilder builder) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (sheetContext) => _glass(
        radius: const BorderRadius.vertical(top: Radius.circular(28)),
        sigma: 28,
        tint: AppColors.surface.withValues(alpha: 0.82),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              builder(sheetContext),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  /// Tapping "+" shows the Camera / Gallery choice.
  void _showAddSheet() {
    HapticFeedback.selectionClick();

    _showGlassSheet(
      (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add to SnapKeep',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _addOption(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _addScreenshot(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _addOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _addScreenshot(ImageSource.gallery);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addScreenshot(ImageSource source) async {
    // The camera opens only after the permission is granted.
    if (source == ImageSource.camera) {
      final allowed = await _ensureCameraPermission();
      if (!allowed || !mounted) return;
    }

    try {
      // Only the camera photo is shrunk, because it is very large.
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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

    // Same reminder as before: keep the snoozed state.
    // Reminder changed by hand: it is no longer a snooze.
    final cleaned = updatedItem.reminderDate == item.reminderDate
        ? updatedItem.copyWith(wasSnoozed: item.wasSnoozed)
        : updatedItem.copyWith(wasSnoozed: false);

    setState(() => _items[index] = cleaned);

    await _runStorage(
      () => _storage.replaceItem(cleaned),
      'Could not save your changes.',
    );

    _syncReminder(cleaned);
  }

  /// Done. A repeating reminder is not finished by this: it moves to its next
  /// time. [finish] ends it for good (stops repeating and marks it done).
  /// Undoing a finished item only marks it not done; the reminder must be set
  /// again.
  Future<void> _toggleDone(SavedItem item, {bool finish = false}) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    // Repeating and active: just go to the next time.
    final anchor = item.repeatAnchor ?? item.reminderDate;
    final now = DateTime.now();
    final reminder = item.reminderDate;
    // If the reminder is still ahead, take the time after it. Otherwise the
    // same time comes back and Done would do nothing.
    final from = (reminder != null && reminder.isAfter(now)) ? reminder : now;

    final next =
        (!finish && !item.isDone && item.repeat.repeats && anchor != null)
        ? item.repeat.nextAfter(anchor, from)
        : null;

    if (next != null) {
      final advanced = item.copyWith(reminderDate: next, wasSnoozed: false);

      HapticFeedback.lightImpact();
      setState(() => _items[index] = advanced);

      await _runStorage(
        () => _storage.replaceItem(advanced),
        'Could not update the item.',
      );

      _syncReminder(advanced, askPermission: false);
      return;
    }

    final nowDone = !item.isDone;
    final updated = nowDone
        ? item.copyWith(
            isDone: true,
            clearReminder: true,
            repeat: RepeatRule.none,
          )
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

  /// Moves the item to "Recently deleted" (kept for 30 days) and offers Undo.
  /// There is no confirmation dialog, because nothing is lost.
  Future<void> _deleteItem(SavedItem item) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    HapticFeedback.mediumImpact();
    setState(() => _items.removeAt(index));

    await NotificationService.instance.cancel(item);

    await _runStorage(
      () => _storage.moveToTrash(item.id),
      'Could not delete the item.',
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 5),
          // A snackbar with an action does not hide by itself by default.
          persist: false,
          // Swipe left or right to dismiss.
          dismissDirection: DismissDirection.horizontal,
          content: const Text('Moved to Recently deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _runStorage(
                () => _storage.restore(item.id),
                'Could not restore the item.',
              );
              if (!mounted) return;

              // The item comes back to its old place in the list.
              await _reloadList();
              _syncReminder(item, askPermission: false);
            },
          ),
        ),
      );
  }

  /// Opens the viewer on [item]. The viewer can swipe through the same list
  /// that the home screen shows (category and search applied).
  Future<void> _openScreenshot(SavedItem item) async {
    final visible = _filteredItems;
    var start = visible.indexWhere((e) => e.id == item.id);

    // Not in the visible list (for example opened from a filtered view):
    // show just this one.
    final list = start == -1 ? <SavedItem>[item] : visible;
    if (start == -1) start = 0;

    final result = await Navigator.of(context).push<_ViewerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScreenshotViewer(items: list, initialIndex: start),
      ),
    );

    if (!mounted || result == null) return;

    // The item that was on screen when the button was pressed.
    final current = result.item;

    switch (result.action) {
      case _ScreenshotAction.delete:
        await _deleteItem(current);

      case _ScreenshotAction.edit:
        await _editItem(current);

      case _ScreenshotAction.done:
        final repeating = current.repeat.repeats && !current.isDone;
        final wasDone = current.isDone;
        await _toggleDone(current);
        _showMessage(
          wasDone
              ? 'Moved back to your list'
              : repeating
              ? 'Done for now. It will remind you again.'
              : 'Marked as done',
        );

      case _ScreenshotAction.snooze:
        final picked = await showSnoozeSheet(context);
        if (picked == null || !mounted) return;

        await NotificationService.instance.snoozeItem(current, picked);
        _showMessage('Snoozed until ${_timeShort(picked)}');
    }
  }

  void _showItemMenu(SavedItem item) {
    HapticFeedback.selectionClick();

    _showGlassSheet(
      (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetTile(
            icon: Icons.edit_outlined,
            title: 'Edit',
            onTap: () {
              Navigator.pop(sheetContext);
              _editItem(item);
            },
          ),
          _sheetTile(
            icon: item.isDone
                ? Icons.undo_rounded
                : Icons.check_circle_outline_rounded,
            title: item.isDone
                ? 'Mark as not done'
                : (item.repeat.repeats ? 'Done for this time' : 'Mark as done'),
            onTap: () {
              Navigator.pop(sheetContext);
              _toggleDone(item);
            },
          ),
          if (item.repeat.repeats && !item.isDone)
            _sheetTile(
              icon: Icons.stop_circle_outlined,
              title: 'Finish and stop repeating',
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleDone(item, finish: true);
              },
            ),
          _sheetTile(
            icon: Icons.delete_outline,
            title: 'Delete',
            color: _overdueColor,
            onTap: () {
              Navigator.pop(sheetContext);
              _deleteItem(item);
            },
          ),
        ],
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
                // Shown only when notifications are off.
                SliverToBoxAdapter(child: _buildNotificationBanner()),
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
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _showAddSheet,
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }

  // ───────────────────────── TOP ─────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent,
                  AppColors.accent.withValues(alpha: 0.65),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bookmark_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'SnapKeep',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          _headerButton(
            icon: Icons.label_outline_rounded,
            tooltip: 'Categories',
            onPressed: () => showCategorySheet(context),
          ),
          _headerButton(
            icon: _viewMode == _ViewMode.grid
                ? Icons.view_agenda_outlined
                : Icons.grid_view_rounded,
            tooltip: _viewMode == _ViewMode.grid ? 'List view' : 'Grid view',
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.grid
                  ? _ViewMode.list
                  : _ViewMode.grid;
            }),
          ),
          _headerButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  // Banner shown when notifications are off and a reminder is active.
  Widget _buildNotificationBanner() {
    final hasReminders = _items.any((i) => !i.isDone && i.reminderDate != null);

    if (!_notificationsOff || !hasReminders) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: _overdueColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _overdueColor.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              size: 20,
              color: _overdueColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications are off',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your reminders will not alert you.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _enableNotifications,
              style: TextButton.styleFrom(
                foregroundColor: _overdueColor,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Turn on'),
            ),
          ],
        ),
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
          hintText: 'Search your screenshots',
          hintStyle: TextStyle(color: _muted(0.45), fontSize: 14.5),
          prefixIcon: Icon(Icons.search_rounded, size: 21, color: _muted(0.5)),
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
          fillColor: _muted(0.06),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal, scrollable category pills. The count is hidden when 0.
  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: _categories.map((category) {
            final selected = _selectedCategory == category;
            final count = _countFor(category);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategory = category);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : _muted(0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? Colors.white : _muted(0.7),
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.25)
                                : _muted(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : _muted(0.6),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
              Icon(
                Icons.notifications_active_rounded,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Coming up',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              // Shown only when the card can not hold every item.
              if (hiddenCount > 0)
                Text(
                  '+$hiddenCount more',
                  style: TextStyle(color: _muted(0.55), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent.withValues(alpha: 0.14),
                  AppColors.accent.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < upcoming.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Divider(
                        height: 1,
                        thickness: 0.6,
                        color: _muted(0.1),
                      ),
                    ),
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
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openScreenshot(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Status dot: red missed, green today/tomorrow, grey later.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _fadeImage(
                item.image,
                width: 42,
                height: 42,
                onError: () =>
                    SizedBox(width: 42, height: 42, child: _brokenImage()),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_when(date)} · ${_timeShort(date)}'
                    '${item.repeat.repeats ? ' · ${item.repeat.label}' : ''}',
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
      child: Text(
        count == 1 ? '1 item' : '$count items',
        style: TextStyle(
          color: _muted(0.5),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
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
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.22),
                  AppColors.accent.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Icon(
              isSearching
                  ? Icons.search_off_rounded
                  : Icons.photo_library_outlined,
              size: 36,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isSearching ? 'No results' : 'Nothing saved yet',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
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
    final showBadge = reminder != null && !done;

    return GestureDetector(
      onTap: () => _openScreenshot(item),
      onLongPress: () => _showItemMenu(item),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Done items are faded so active reminders stand out.
                    Hero(
                      tag: _heroTag(item),
                      child: Opacity(
                        opacity: done ? 0.5 : 1,
                        child: _fadeImage(item.image, onError: _brokenImage),
                      ),
                    ),
                    // Soft dark fade so the glass badge is always readable.
                    if (showBadge)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 76,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (done) Positioned(top: 10, left: 10, child: _donePill()),
                    if (showBadge && item.wasSnoozed)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _snoozedTag(onImage: true),
                      ),
                    if (showBadge)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _reminderBadge(
                            reminder,
                            repeats: item.repeat.repeats,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: done ? _muted(0.5) : AppColors.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: _muted(0.5),
            ),
          ),
          const SizedBox(height: 3),
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
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _deleteItem(item),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 22),
                decoration: BoxDecoration(
                  color: _overdueColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.delete_outline, color: _overdueColor),
              ),
              child: _listRow(item),
            ),
          );
        },
      ),
    );
  }

  Widget _listRow(SavedItem item) {
    final done = item.isDone;

    return Material(
      color: _muted(0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openScreenshot(item),
        onLongPress: () => _showItemMenu(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Opacity(
                  opacity: done ? 0.55 : 1,
                  child: _fadeImage(
                    item.image,
                    width: 58,
                    height: 58,
                    onError: () =>
                        SizedBox(width: 58, height: 58, child: _brokenImage()),
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

/// Full screen viewer. Swipe left or right to move between the screenshots
/// of [items]. Pops with a [_ViewerResult] when an action button is pressed.
class _ScreenshotViewer extends StatefulWidget {
  const _ScreenshotViewer({required this.items, required this.initialIndex});

  final List<SavedItem> items;
  final int initialIndex;

  @override
  State<_ScreenshotViewer> createState() => _ScreenshotViewerState();
}

class _ScreenshotViewerState extends State<_ScreenshotViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  late int _index = widget.initialIndex;

  /// True while the current image is zoomed in. Swiping is off then, so
  /// panning the zoomed image does not turn the page.
  bool _zoomed = false;

  SavedItem get _item => widget.items[_index];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(_ScreenshotAction action) {
    Navigator.pop(context, _ViewerResult(action, _item));
  }

  Widget _chip(IconData icon, String label, {Color? color}) {
    final c = color ?? Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final fg = filled ? Colors.white : AppColors.accent;

    return Material(
      color: filled
          ? AppColors.accent
          : AppColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "3 / 12" pill in the top bar.
  Widget _counter() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12,
          sigmaY: 12,
          tileMode: TileMode.clamp,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_index + 1} / ${widget.items.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).width >= 600;
    final item = _item;
    final reminder = item.reminderDate;

    Color whenColor = Colors.white70;
    if (reminder != null) {
      final diff = _daysUntil(reminder);
      if (diff < 0) {
        whenColor = _overdueColor;
      } else if (diff <= 1) {
        whenColor = AppColors.accent;
      }
    }

    final pagePadding = EdgeInsets.only(
      top: 70,
      bottom: isTablet ? 290 : 310,
      left: 18,
      right: 18,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: Stack(
        children: [
          // Blurred copy of the current photo as the backdrop.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(item.id),
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 45,
                      sigmaY: 45,
                      tileMode: TileMode.clamp,
                    ),
                    child: Opacity(
                      opacity: 0.55,
                      child: SizedBox.expand(
                        child: Image.file(
                          item.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Stack(
              children: [
                // The swipeable photos.
                Positioned.fill(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.items.length,
                    physics: _zoomed
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _index = i;
                        _zoomed = false;
                      });
                    },
                    itemBuilder: (context, i) => _ViewerPage(
                      key: ValueKey(widget.items[i].id),
                      item: widget.items[i],
                      padding: pagePadding,
                      onZoomChanged: (zoomed) {
                        if (_zoomed != zoomed && i == _index) {
                          setState(() => _zoomed = zoomed);
                        }
                      },
                    ),
                  ),
                ),

                // Top bar: back, counter, edit, delete.
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _viewerButton(
                        Icons.arrow_back,
                        () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: widget.items.length > 1
                              ? _counter()
                              : const SizedBox.shrink(),
                        ),
                      ),
                      _viewerButton(
                        Icons.edit_outlined,
                        () => _finish(_ScreenshotAction.edit),
                      ),
                      _viewerButton(
                        Icons.delete_outline,
                        () => _finish(_ScreenshotAction.delete),
                      ),
                    ],
                  ),
                ),

                // Info card of the current photo.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _glass(
                    radius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    sigma: 30,
                    tint: const Color(0xFF16161A).withValues(alpha: 0.7),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 32 : 24,
                        12,
                        isTablet ? 32 : 24,
                        28,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 38,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  height: 1.3,
                                ),
                              ),
                              if (item.note.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.note,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip(
                                    Icons.label_outline_rounded,
                                    item.category,
                                  ),
                                  if (reminder != null)
                                    _chip(
                                      Icons.event_rounded,
                                      _formatDate(reminder),
                                    ),
                                  if (reminder != null)
                                    _chip(
                                      Icons.schedule_rounded,
                                      _when(reminder),
                                      color: whenColor,
                                    ),
                                  if (reminder != null && item.repeat.repeats)
                                    _chip(
                                      Icons.repeat_rounded,
                                      'Repeats ${item.repeat.label.toLowerCase()}',
                                      color: AppColors.accent,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  if (!item.isDone && reminder != null) ...[
                                    Expanded(
                                      child: _actionButton(
                                        icon: Icons.snooze_rounded,
                                        label: 'Snooze',
                                        onTap: () =>
                                            _finish(_ScreenshotAction.snooze),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  Expanded(
                                    child: _actionButton(
                                      icon: item.isDone
                                          ? Icons.undo_rounded
                                          : Icons.check_rounded,
                                      label: item.isDone
                                          ? 'Not done'
                                          : (item.repeat.repeats
                                                ? 'Done for now'
                                                : 'Done'),
                                      filled: true,
                                      onTap: () =>
                                          _finish(_ScreenshotAction.done),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Round frosted button for the viewer's top bar.
  Widget _viewerButton(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 12,
            sigmaY: 12,
            tileMode: TileMode.clamp,
          ),
          child: Material(
            color: Colors.black.withValues(alpha: 0.35),
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon, color: Colors.white, size: 21),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One photo of the viewer. Pinch to zoom, and it tells the viewer when it is
/// zoomed so swiping can be switched off.
class _ViewerPage extends StatefulWidget {
  const _ViewerPage({
    super.key,
    required this.item,
    required this.padding,
    required this.onZoomChanged,
  });

  final SavedItem item;
  final EdgeInsets padding;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomed) return;

    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Padding(
      padding: widget.padding,
      child: Center(
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 0.8,
          maxScale: 5,
          child: Hero(
            tag: _heroTag(item),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
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
    );
  }
}
