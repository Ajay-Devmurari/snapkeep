import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Opens the snooze sheet. Returns the chosen DateTime, or null if dismissed.
///
/// No Material date/time dialogs are opened from here. They caused a red
/// "non-normalized constraints" screen when the keyboard mode was shown
/// inside a bottom sheet. Everything is picked inside this one sheet.
Future<DateTime?> showSnoozeSheet(BuildContext context) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _SnoozeSheet(),
  );
}

const _quickOptions = <({String label, Duration duration})>[
  (label: '5 min', duration: Duration(minutes: 5)),
  (label: '10 min', duration: Duration(minutes: 10)),
  (label: '20 min', duration: Duration(minutes: 20)),
  (label: '1 hour', duration: Duration(hours: 1)),
];

class _SnoozeSheet extends StatefulWidget {
  const _SnoozeSheet();

  @override
  State<_SnoozeSheet> createState() => _SnoozeSheetState();
}

class _SnoozeSheetState extends State<_SnoozeSheet> {
  /// 0 = today, 1 = tomorrow.
  int _dayOffset = 0;

  /// Only hour and minute are used. Starts 10 minutes from now.
  DateTime _time = DateTime.now().add(const Duration(minutes: 10));

  String? _error;

  DateTime get _day =>
      DateUtils.dateOnly(DateTime.now()).add(Duration(days: _dayOffset));

  DateTime get _candidate =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  void _confirm() {
    if (!_candidate.isAfter(DateTime.now())) {
      setState(() => _error = 'Pick a time in the future.');
      return;
    }

    Navigator.pop(context, _candidate);
  }

  @override
  Widget build(BuildContext context) {
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Snooze reminder',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),

            // Quick options: tap = snoozed immediately.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _quickOptions)
                  ActionChip(
                    label: Text(option.label),
                    onPressed: () => Navigator.pop(
                      context,
                      DateTime.now().add(option.duration),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 22),

            Text(
              'Or choose your own time',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Today')),
                    selected: _dayOffset == 0,
                    onSelected: (_) => setState(() {
                      _dayOffset = 0;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Tomorrow')),
                    selected: _dayOffset == 1,
                    onSelected: (_) => setState(() {
                      _dayOffset = 1;
                      _error = null;
                    }),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Wheel picker: no keyboard mode, so no layout crash.
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.text.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(14),
              ),
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
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: use24h,
                  initialDateTime: _time,
                  // Only the hour and minute are read in _confirm().
                  onDateTimeChanged: (value) {
                    _time = value;
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD6574E),
                    fontSize: 12.5,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Snooze',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
