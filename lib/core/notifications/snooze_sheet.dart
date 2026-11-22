import 'package:flutter/cupertino.dart'
    show
    CupertinoDatePicker,
    CupertinoDatePickerMode,
    CupertinoTextThemeData,
    CupertinoTheme,
    CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

const _red = Color(0xFFD6574E);

/// Opens the snooze sheet. Returns the chosen DateTime, or null if dismissed.
///
/// Same look as the "Change reminder" sheet. No Material date/time dialogs
/// are opened from here, everything is picked inside this one sheet.
Future<DateTime?> showSnoozeSheet(BuildContext context) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    barrierColor: Colors.black54,
    constraints: const BoxConstraints(maxWidth: 600),
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

/// Current time + 1 minute (hour stays as it is).
DateTime _nextMinute() {
  final next = DateTime.now().add(const Duration(minutes: 1));
  return DateTime(next.year, next.month, next.day, next.hour, next.minute);
}

class _SnoozeSheet extends StatefulWidget {
  const _SnoozeSheet();

  @override
  State<_SnoozeSheet> createState() => _SnoozeSheetState();
}

class _SnoozeSheetState extends State<_SnoozeSheet> {
  /// 0 = today, 1 = tomorrow.
  int _dayOffset = 0;

  /// Only hour and minute are used. Starts at current time + 1 minute.
  late DateTime _time = _nextMinute();

  /// True once the user scrolled the wheel by hand. Then the chosen time is
  /// kept when switching days.
  bool _timeEdited = false;

  /// Bumped when the time is changed by code, so the wheel jumps to it.
  int _wheelVersion = 0;

  String? _error;

  Color get _fill => AppColors.text.withValues(alpha: 0.045);

  DateTime get _day =>
      DateUtils.dateOnly(DateTime.now()).add(Duration(days: _dayOffset));

  DateTime get _candidate =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  void _selectDay(int offset) {
    HapticFeedback.selectionClick();

    setState(() {
      _dayOffset = offset;
      _error = null;

      if (offset == 0) {
        // Today: always current time + 1 minute.
        _time = _nextMinute();
        _timeEdited = false;
      } else if (!_timeEdited) {
        // Another day: 12:00 PM unless the user picked a time by hand.
        _time = DateTime(_day.year, _day.month, _day.day, 12, 0);
      }

      _wheelVersion++;
    });
  }

  void _confirm() {
    if (!_candidate.isAfter(DateTime.now())) {
      setState(() => _error = 'Pick a time in the future.');
      return;
    }

    HapticFeedback.lightImpact();
    Navigator.pop(context, _candidate);
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withValues(alpha: 0.10) : _fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.accent : Colors.transparent,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: active ? AppColors.accent : AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
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

  @override
  Widget build(BuildContext context) {
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);

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
                      'Snooze reminder',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Quick options: tap = snoozed immediately.
              _label('SNOOZE FOR'),
              Row(
                children: [
                  for (var i = 0; i < _quickOptions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _chip(
                      label: _quickOptions[i].label,
                      active: false,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(
                          context,
                          DateTime.now().add(_quickOptions[i].duration),
                        );
                      },
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 22),

              _label('OR PICK A TIME'),
              Row(
                children: [
                  _chip(
                    label: 'Today',
                    active: _dayOffset == 0,
                    onTap: () => _selectDay(0),
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    label: 'Tomorrow',
                    active: _dayOffset == 1,
                    onTap: () => _selectDay(1),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // TIME: scroll wheels, so only valid times are possible.
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
                            TimeOfDay.fromDateTime(_candidate).format(context),
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
                          key: ValueKey(_wheelVersion),
                          mode: CupertinoDatePickerMode.time,
                          use24hFormat: use24h,
                          initialDateTime: _time,
                          // Only hour and minute are read.
                          onDateTimeChanged: (value) {
                            setState(() {
                              _time = value;
                              _timeEdited = true;
                              _error = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: _red, fontSize: 12.5),
                  ),
                ),

              const SizedBox(height: 18),

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
      ),
    );
  }
}