import 'dart:io';

import 'package:path/path.dart' as p;

class SavedItem {
  SavedItem({
    required this.image,
    required this.title,
    required this.category,
    this.note = '',
    this.reminderDate,
    this.isDone = false,
    this.wasSnoozed = false, // default false, purane saved data ke liye safe
    String? id,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final File image;
  final String title;
  final String category;
  final String note;
  final DateTime? reminderDate;

  /// True agar user ne reminder kam se kam ek baar snooze kiya ho.
  final bool wasSnoozed;

  /// True once the user marked the item as done. A done item has no active
  /// reminder (its reminderDate is cleared).
  final bool isDone;

  SavedItem copyWith({
    File? image,
    String? title,
    String? category,
    String? note,
    DateTime? reminderDate,
    bool clearReminder = false,
    bool? isDone,
    bool? wasSnoozed,
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
  };

  factory SavedItem.fromJson(Map<String, dynamic> json, Directory imagesDir) {
    final reminder = json['reminderDate'] as String?;

    return SavedItem(
      id: json['id'] as String?,
      image: File(p.join(imagesDir.path, json['image'] as String)),
      title: (json['title'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Other',
      note: (json['note'] as String?) ?? '',
      reminderDate: reminder == null ? null : DateTime.tryParse(reminder),
      isDone: (json['isDone'] as bool?) ?? false,
      wasSnoozed: (json['wasSnoozed'] as bool?) ?? false,
    );
  }
}