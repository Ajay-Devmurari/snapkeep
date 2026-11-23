import 'dart:io';

import 'package:path/path.dart' as p;

/// How often a reminder comes back.
enum RepeatRule {
  none('Never'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const RepeatRule(this.label);

  final String label;

  bool get repeats => this != RepeatRule.none;

  static RepeatRule fromName(String? name) {
    return RepeatRule.values.firstWhere(
          (r) => r.name == name,
      orElse: () => RepeatRule.none,
    );
  }

  /// The first time of this series that is later than [after].
  ///
  /// The series is always counted from [anchor] (the time the user chose),
  /// never from the previous result, so a snooze or a short month can never
  /// move the series. Monthly: day 31 becomes the last day of shorter months.
  DateTime? nextAfter(DateTime anchor, DateTime after) {
    if (!repeats) return null;
    if (anchor.isAfter(after)) return anchor;

    DateTime at(int n) {
      switch (this) {
        case RepeatRule.daily:
          return DateTime(
            anchor.year,
            anchor.month,
            anchor.day + n,
            anchor.hour,
            anchor.minute,
          );
        case RepeatRule.weekly:
          return DateTime(
            anchor.year,
            anchor.month,
            anchor.day + 7 * n,
            anchor.hour,
            anchor.minute,
          );
        case RepeatRule.monthly:
          return _monthlyOccurrence(anchor, n);
        case RepeatRule.none:
          return anchor;
      }
    }

    // Start close to the answer, then step forward.
    final days = DateTime.utc(after.year, after.month, after.day)
        .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
        .inDays;

    var n = switch (this) {
      RepeatRule.daily => days,
      RepeatRule.weekly => days ~/ 7,
      RepeatRule.monthly =>
      (after.year - anchor.year) * 12 + after.month - anchor.month,
      RepeatRule.none => 0,
    };

    if (n < 0) n = 0;

    while (!at(n).isAfter(after)) {
      n++;
    }

    return at(n);
  }

  /// The next [count] times after [after].
  List<DateTime> upcoming(DateTime anchor, DateTime after, int count) {
    final result = <DateTime>[];
    var cursor = after;

    for (var i = 0; i < count; i++) {
      final next = nextAfter(anchor, cursor);
      if (next == null) break;

      result.add(next);
      cursor = next;
    }

    return result;
  }
}

/// An extra "heads up" alert before the reminder itself.
enum AdvanceAlert {
  none('At the time'),
  hour('1 hour before'),
  day('1 day before');

  const AdvanceAlert(this.label);

  final String label;

  bool get enabled => this != AdvanceAlert.none;

  static AdvanceAlert fromName(String? name) {
    return AdvanceAlert.values.firstWhere(
          (a) => a.name == name,
      orElse: () => AdvanceAlert.none,
    );
  }

  /// The moment of the early alert for a reminder at [when].
  DateTime before(DateTime when) {
    switch (this) {
      case AdvanceAlert.hour:
        return when.subtract(const Duration(hours: 1));
      case AdvanceAlert.day:
        return DateTime(
          when.year,
          when.month,
          when.day - 1,
          when.hour,
          when.minute,
        );
      case AdvanceAlert.none:
        return when;
    }
  }
}

DateTime _monthlyOccurrence(DateTime a, int months) {
  final total = a.month - 1 + months;
  final year = a.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;

  return DateTime(
    year,
    month,
    a.day > lastDay ? lastDay : a.day,
    a.hour,
    a.minute,
  );
}

class SavedItem {
  SavedItem({
    required this.image,
    required this.title,
    required this.category,
    this.note = '',
    this.reminderDate,
    this.isDone = false,
    this.wasSnoozed = false, // default false, purane saved data ke liye safe
    this.repeat = RepeatRule.none, // purane saved data ke liye safe
    this.repeatAnchor,
    this.advance = AdvanceAlert.none, // purane saved data ke liye safe
    this.deletedAt, // null = not deleted, purane saved data ke liye safe
    String? id,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final File image;
  final String title;
  final String category;
  final String note;

  /// The next time the reminder rings (or the snoozed time).
  final DateTime? reminderDate;

  /// True agar user ne reminder kam se kam ek baar snooze kiya ho.
  final bool wasSnoozed;

  /// True once the user marked the item as done. A done item has no active
  /// reminder (its reminderDate is cleared).
  final bool isDone;

  /// How often the reminder comes back.
  final RepeatRule repeat;

  /// The time the user chose for the series. Every repeat is counted from
  /// here. Null when the reminder does not repeat.
  final DateTime? repeatAnchor;

  /// Extra alert before each reminder time (none, 1 hour, 1 day).
  final AdvanceAlert advance;

  /// When the item was moved to "Recently deleted". Null for a normal item.
  final DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  SavedItem copyWith({
    File? image,
    String? title,
    String? category,
    String? note,
    DateTime? reminderDate,
    bool clearReminder = false,
    bool? isDone,
    bool? wasSnoozed,
    RepeatRule? repeat,
    DateTime? repeatAnchor,
    AdvanceAlert? advance,
    DateTime? deletedAt,
    bool clearDeleted = false,
  }) {
    return SavedItem(
      id: id,
      image: image ?? this.image,
      title: title ?? this.title,
      category: category ?? this.category,
      note: note ?? this.note,
      reminderDate: clearReminder ? null : (reminderDate ?? this.reminderDate),
      isDone: isDone ?? this.isDone,
      wasSnoozed: wasSnoozed ?? this.wasSnoozed,
      repeat: repeat ?? this.repeat,
      repeatAnchor: clearReminder ? null : (repeatAnchor ?? this.repeatAnchor),
      advance: advance ?? this.advance,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
    );
  }

  /// Only the image *file name* is stored. The folder is rebuilt on every
  /// launch, because the app's documents path can change (for example on iOS
  /// after an update).
  Map<String, dynamic> toJson() => {
    'id': id,
    'image': p.basename(image.path),
    'title': title,
    'category': category,
    'note': note,
    'reminderDate': reminderDate?.toIso8601String(),
    'isDone': isDone,
    'wasSnoozed': wasSnoozed,
    'repeat': repeat.name,
    'repeatAnchor': repeatAnchor?.toIso8601String(),
    'advance': advance.name,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory SavedItem.fromJson(Map<String, dynamic> json, Directory imagesDir) {
    final reminder = json['reminderDate'] as String?;
    final anchor = json['repeatAnchor'] as String?;
    final deleted = json['deletedAt'] as String?;

    return SavedItem(
      id: json['id'] as String?,
      image: File(p.join(imagesDir.path, json['image'] as String)),
      title: (json['title'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Other',
      note: (json['note'] as String?) ?? '',
      reminderDate: reminder == null ? null : DateTime.tryParse(reminder),
      isDone: (json['isDone'] as bool?) ?? false,
      wasSnoozed: (json['wasSnoozed'] as bool?) ?? false,
      repeat: RepeatRule.fromName(json['repeat'] as String?),
      repeatAnchor: anchor == null ? null : DateTime.tryParse(anchor),
      advance: AdvanceAlert.fromName(json['advance'] as String?),
      deletedAt: deleted == null ? null : DateTime.tryParse(deleted),
    );
  }
}