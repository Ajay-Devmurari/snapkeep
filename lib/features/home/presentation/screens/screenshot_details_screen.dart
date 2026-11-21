import 'dart:io';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/cupertino.dart'
    show
    CupertinoDatePicker,
    CupertinoDatePickerMode,
    CupertinoTextThemeData,
    CupertinoTheme,
    CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snapkeep/core/categories/category_store.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../categories/presentation/category_store.dart';
import '../../../home/models/saved_item.dart';

const _red = Color(0xFFD6574E);

class ScreenshotDetailsScreen extends StatefulWidget {
  const ScreenshotDetailsScreen({
    required this.image,
    this.initialItem,
    super.key,
  });

  final File image;
  final SavedItem? initialItem;

  @override
  State<ScreenshotDetailsScreen> createState() =>
      _ScreenshotDetailsScreenState();
}

class _ScreenshotDetailsScreenState extends State<ScreenshotDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _titleFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  /// The image currently shown. Starts as the given image and changes when
  /// the user picks another one.
  late File _image;

  String _category = 'Other';
  DateTime? _reminderDate;

  /// Shown under the reminder row after the user tries to save without one.
  bool _reminderMissing = false;

  /// Category created from this screen. It is saved to the list only when the
  /// screenshot is saved, so Cancel or X leaves no trace.
  String? _pendingCategory;

  /// Stored categories, with the pending one placed before "Other".
  List<String> _visibleCategories(List<String> stored) {
    final pending = _pendingCategory;
    if (pending == null || stored.contains(pending) || stored.isEmpty) {
      return stored;
    }
    return [...stored.sublist(0, stored.length - 1), pending, stored.last];
  }

  bool _categoryTouched = false;

  String _initialTitle = '';
  String _initialNote = '';
  String _initialCategory = 'Other';
  DateTime? _initialReminder;

  static const _months = [
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

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static final _patterns = <String, RegExp>{
    'Bills': RegExp(
      r'\b(bill|electric|water|gas|rent|invoice|recharge|emi|insurance|tax|payment|due|loan|subscription)',
      caseSensitive: false,
    ),
    'Travel': RegExp(
      r'\b(flight|ticket|train|bus|hotel|trip|booking|boarding|visa|pnr|cab|airport|passport)',
      caseSensitive: false,
    ),
    'Events': RegExp(
      r'\b(event|concert|party|wedding|meeting|birthday|show|movie|invite|festival|exam|interview)',
      caseSensitive: false,
    ),
    'Shopping': RegExp(
      r'\b(order|amazon|flipkart|delivery|cart|offer|coupon|sale|refund|shopping|purchase|discount)',
      caseSensitive: false,
    ),
  };

  bool get _isEditing => widget.initialItem != null;

  /// Only the title is checked here. The reminder is checked on save, so the
  /// user gets a clear message instead of a disabled button.
  bool get _canSave => _titleController.text.trim().isNotEmpty;

  bool get _dirty =>
      _titleController.text.trim() != _initialTitle.trim() ||
          _noteController.text.trim() != _initialNote.trim() ||
          _category != _initialCategory ||
          _image.path != widget.image.path ||
          !_sameReminder(_reminderDate, _initialReminder);

  bool _sameReminder(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;

    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  /// Suggests only categories that still exist, so a removed category never
  /// comes back through auto-detection.
  String? get _suggestedCategory {
    final text = '${_titleController.text} ${_noteController.text}';
    if (text.trim().isEmpty) return null;

    final available = CategoryStore.categories.value;
    final matches = _patterns.entries
        .where((e) => available.contains(e.key) && e.value.hasMatch(text))
        .map((e) => e.key)
        .toList();

    if (matches.isEmpty || matches.contains(_category)) return null;
    return matches.first;
  }

  @override
  void initState() {
    super.initState();

    _image = widget.image;

    final item = widget.initialItem;

    if (item != null) {
      _titleController.text = item.title;
      _noteController.text = item.note;
      _category = item.category;
      _reminderDate = item.reminderDate;
      _categoryTouched = true;
    }

    _initialTitle = _titleController.text;
    _initialNote = _noteController.text;
    _initialCategory = _category;
    _initialReminder = _reminderDate;

    _titleController.addListener(_onTextChanged);
    _noteController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;

    setState(() {
      if (!_categoryTouched) {
        final suggestion = _suggestedCategory;
        if (suggestion != null) _category = suggestion;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      _titleFocus.requestFocus();
      return;
    }

    // A screenshot is saved only with a reminder. Open the sheet so the user
    // can set one right away.
    if (_reminderDate == null) {
      HapticFeedback.mediumImpact();
      setState(() => _reminderMissing = true);
      _openReminderSheet();
      return;
    }

    // Only now does a new category become real.
    final pending = _pendingCategory;
    if (pending != null && CategoryStore.find(pending) == null) {
      await CategoryStore.add(pending);
    }
    if (!mounted) return;

    HapticFeedback.lightImpact();

    Navigator.of(context).pop(
      SavedItem(
        id: widget.initialItem?.id,
        // The currently shown image, so a replaced image is really saved.
        image: _image,
        title: _titleController.text.trim(),
        category: _category,
        note: _noteController.text.trim(),
        reminderDate: _reminderDate,
      ),
    );
  }

  /// Picks another image from the gallery and shows it in the preview.
  Future<void> _changeImage() async {
    FocusScope.of(context).unfocus();

    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;

      HapticFeedback.selectionClick();
      setState(() => _image = File(picked.path));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not select image: $e'),
        ),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard changes?'),
        content: const Text('What you entered here won’t be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Keep editing',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );

    return discard ?? false;
  }

  // ───────────────────────── CATEGORY ─────────────────────────

  /// Opens the picker in pick mode. Nothing is saved here.
  Future<void> _addCategoryFromDetails() async {
    final picked = await showCategorySheet(
      context,
      mode: CategorySheetMode.pick,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _pendingCategory = picked;
      _category = picked;
      _categoryTouched = true;
    });
  }

  // ───────────────────────── DATE / TIME HELPERS ─────────────────────────

  DateTime _nextMinute() {
    final now = DateTime.now();
    final next = now.add(const Duration(minutes: 1));

    return DateTime(next.year, next.month, next.day, next.hour, next.minute);
  }

  String _dateLabel(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = DateUtils.dateOnly(date);

    if (DateUtils.isSameDay(selected, today)) return 'Today';

    if (DateUtils.isSameDay(selected, today.add(const Duration(days: 1)))) {
      return 'Tomorrow';
    }

    return '${_weekdays[date.weekday - 1]}, '
        '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  String _timeLabel(DateTime date) {
    return TimeOfDay.fromDateTime(date).format(context);
  }

  /// Accent-coloured theme for the system date picker.
  Widget _pickerTheme(BuildContext context, Widget? child) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: AppColors.accent,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.text,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  // ───────────────────────── REMINDER SHEET ─────────────────────────

  Future<void> _openReminderSheet() async {
    FocusScope.of(context).unfocus();

    final now = DateTime.now();

    // State lives OUTSIDE the builder so a rebuild can never reset it.
    // Default for a new reminder: tomorrow, 9:00.
    DateTime selected =
        _reminderDate ?? DateTime(now.year, now.month, now.day + 1, 9, 0);

    // Bumped only when the time is changed by code (quick chips / date),
    // so the wheel jumps to the new time but is left alone while scrolling.
    int wheelVersion = 0;

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
            final isFuture = selected.isAfter(DateTime.now());

            /// Same time of day on another day. If that moment already
            /// passed today, fall back to the next minute.
            DateTime withDay(DateTime day) {
              final candidate = DateTime(
                day.year,
                day.month,
                day.day,
                selected.hour,
                selected.minute,
              );

              if (candidate.isAfter(DateTime.now())) return candidate;

              return DateUtils.isSameDay(day, DateTime.now())
                  ? _nextMinute()
                  : candidate;
            }

            Future<void> pickDate() async {
              final today = DateUtils.dateOnly(DateTime.now());
              final current = DateUtils.dateOnly(selected);

              final picked = await showDatePicker(
                context: context,
                // initialDate must never be before firstDate.
                initialDate: current.isBefore(today) ? today : current,
                firstDate: today,
                lastDate: DateTime(today.year + 5),
                // No keyboard mode -> no keyboard related crashes.
                initialEntryMode: DatePickerEntryMode.calendarOnly,
                builder: _pickerTheme,
              );

              if (picked == null || !context.mounted) return;

              setSheetState(() {
                selected = withDay(picked);
                wheelVersion++;
              });
            }

            Widget chip(String label, int days) {
              final target = DateUtils.dateOnly(
                DateTime.now(),
              ).add(Duration(days: days));

              final active = DateUtils.isSameDay(selected, target);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();

                    setSheetState(() {
                      selected = withDay(target);
                      wheelVersion++;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.10)
                          : _fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active ? AppColors.accent : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active ? AppColors.accent : AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _reminderDate == null
                                  ? 'Set reminder'
                                  : 'Change reminder',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          chip('Today', 0),
                          const SizedBox(width: 8),
                          chip('Tomorrow', 1),
                          const SizedBox(width: 8),
                          chip('In a week', 7),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // DATE – tap to open the calendar (any date from today).
                      _sheetTile(
                        icon: Icons.calendar_month_rounded,
                        label: 'Date',
                        value: _dateLabel(selected),
                        onTap: pickDate,
                      ),

                      const SizedBox(height: 10),

                      // TIME – scroll wheels. Only valid times are possible,
                      // so values like 18:80 can't be entered at all.
                      Container(
                        decoration: BoxDecoration(
                          color: _fill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    color: AppColors.accent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Time',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _timeLabel(selected),
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 150,
                              child: CupertinoTheme(
                                data: CupertinoThemeData(
                                  textTheme: CupertinoTextThemeData(
                                    dateTimePickerTextStyle: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                child: CupertinoDatePicker(
                                  key: ValueKey(wheelVersion),
                                  mode: CupertinoDatePickerMode.time,
                                  use24hFormat: use24h,
                                  initialDateTime: selected,
                                  onDateTimeChanged: (value) {
                                    setSheetState(() {
                                      selected = DateTime(
                                        selected.year,
                                        selected.month,
                                        selected.day,
                                        value.hour,
                                        value.minute,
                                      );
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (!isFuture)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Pick a time in the future.',
                            style: TextStyle(color: _red, fontSize: 12.5),
                          ),
                        ),

                      const SizedBox(height: 18),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isFuture
                              ? () {
                            // Re-check: time may have passed while open.
                            if (!selected.isAfter(DateTime.now())) {
                              setSheetState(() {});
                              return;
                            }

                            HapticFeedback.lightImpact();
                            Navigator.pop(sheetContext, selected);
                          }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.text.withValues(
                              alpha: 0.08,
                            ),
                            disabledForegroundColor: AppColors.text.withValues(
                              alpha: 0.4,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Set reminder',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _reminderDate = result;
      _reminderMissing = false;
    });
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── PREVIEW ─────────────────────────

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.file(_image, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── HELPERS ─────────────────────────

  String _reminderShort(DateTime d) {
    final diff = DateUtils.dateOnly(
      d,
    ).difference(DateUtils.dateOnly(DateTime.now())).inDays;

    final String dateLabel;

    if (diff == 0) {
      dateLabel = 'Today';
    } else if (diff == 1) {
      dateLabel = 'Tomorrow';
    } else {
      dateLabel =
      '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
    }

    return '$dateLabel · ${_timeLabel(d)}';
  }

  Color get _fill => AppColors.text.withValues(alpha: 0.045);

  InputDecoration _decoration(String hint) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.text.withValues(alpha: 0.38),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: _fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.accent, 1.3),
      errorBorder: border(_red),
      focusedErrorBorder: border(_red, 1.3),
      errorStyle: const TextStyle(color: _red, fontSize: 12.5),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        color: AppColors.secondaryText,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
  );

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final leave = await _confirmDiscard();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: AppColors.text),
          ),
          title: Text(
            _isEditing ? 'Edit details' : 'New screenshot',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            // Icon only. The tooltip still says what it does.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: _isEditing ? 'Save changes' : 'Save',
                onPressed: _canSave ? _save : null,
                color: AppColors.accent,
                disabledColor: AppColors.text.withValues(alpha: 0.38),
                icon: const Icon(Icons.check_rounded, size: 26),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 26),
                      _label('CATEGORY'),
                      _buildCategoryRow(),
                      const SizedBox(height: 26),
                      _label('REMINDER'),
                      _buildReminderRow(),
                      const SizedBox(height: 12),
                      _buildNoteField(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── SECTIONS ─────────────────────────

  /// Header card: blurred backdrop, thumbnail on the left, title on the right.
  Widget _buildHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // Blurred copy of the image behind the card.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 30,
                sigmaY: 30,
                tileMode: TileMode.mirror,
              ),
              child: Image.file(
                _image,
                key: ValueKey('bg_${_image.path}'),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildThumbnail(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitleField(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Tooltip(
                            message: 'Change image',
                            child: GestureDetector(
                              onTap: _changeImage,
                              child: _previewIcon(
                                Icons.add_photo_alternate_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Tooltip(
                            message: 'View full image',
                            child: GestureDetector(
                              onTap: _openPreview,
                              child: _previewIcon(Icons.open_in_full_rounded),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full image at its own aspect ratio, never cropped.
  Widget _buildThumbnail() {
    return GestureDetector(
      onTap: _openPreview,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Image.file(
              _image,
              key: ValueKey(_image.path),
              height: 150,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => SizedBox(
                width: 80,
                height: 150,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Round glass button that stays readable on any image.
  Widget _previewIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: 19, color: Colors.white),
    );
  }

  /// Title field styled for the dark card (white text, translucent fill).
  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      focusNode: _titleFocus,
      autofocus: !_isEditing,
      minLines: 1,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      cursorColor: AppColors.accent,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: _decoration('Title').copyWith(
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
        fillColor: Colors.black.withValues(alpha: 0.30),
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? 'Add a title to find it later'
          : null,
    );
  }

  /// Pill chips that wrap onto the next line, so every category is visible
  /// without sideways scrolling. The "New" pill is always last.
  Widget _buildCategoryRow() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: CategoryStore.categories,
      builder: (context, stored, _) {
        final names = _visibleCategories(stored);

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in names) _categoryTile(name),
            _addCategoryTile(),
          ],
        );
      },
    );
  }

  Widget _categoryTile(String name) {
    final selected = _category == name;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _category = name;
          _categoryTouched = true;
          // Picking another category drops the unsaved new one.
          if (name != _pendingCategory) _pendingCategory = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : _fill,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CategoryStore.iconFor(name),
              size: 17,
              color: selected ? Colors.white : AppColors.secondaryText,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : AppColors.text.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addCategoryTile() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _addCategoryFromDetails,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'New',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reminder is required. Tapping the row opens the sheet to set or change
  /// it. There is no remove option.
  Widget _buildReminderRow() {
    final date = _reminderDate;
    final hasDate = date != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: _fill,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openReminderSheet,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                child: Row(
                  children: [
                    Icon(
                      hasDate
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_rounded,
                      size: 21,
                      color: hasDate
                          ? AppColors.accent
                          : (_reminderMissing ? _red : AppColors.secondaryText),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasDate ? _reminderShort(date) : 'Set a reminder',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: hasDate
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: hasDate
                              ? AppColors.text
                              : (_reminderMissing
                              ? _red
                              : AppColors.text.withValues(alpha: 0.38)),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_reminderMissing && !hasDate)
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'A reminder is required to save this screenshot.',
              style: TextStyle(color: _red, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: AppColors.accent,
      minLines: 3,
      maxLines: 6,
      style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.45),
      decoration: _decoration('Add a note (optional)'),
    );
  }
}