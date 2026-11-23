import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapkeep/features/home/models/saved_item.dart';

/// Keeps everything on the device:
///  • the list of items  -> JSON text in SharedPreferences
///  • the screenshots    -> copied into the app's own documents folder
///
/// Every read and write goes through one queue, so a read always sees the
/// latest write and two writes never overwrite each other.
class SavedItemsStorage {
  static const _key = 'saved_items_v1';
  static const _folder = 'snapkeep_images';

  static final SavedItemsStorage instance = SavedItemsStorage();

  Directory? _imagesDir;

  Future<void> _queue = Future.value();

  /// Runs [task] after every previously queued operation has finished.
  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _queue.then((_) => task());
    // A failed task must not block the tasks queued after it.
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Directory> _images() async {
    final cached = _imagesDir;
    if (cached != null) return cached;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _folder));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return _imagesDir = dir;
  }

  // ───────────────────────── RAW READ / WRITE (call only inside _serial) ─────────────────────────

  Future<List<SavedItem>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return [];

    final dir = await _images();
    final decoded = jsonDecode(raw);

    if (decoded is! List) return [];

    final items = <SavedItem>[];

    for (final entry in decoded) {
      if (entry is! Map) continue;

      try {
        items.add(SavedItem.fromJson(Map<String, dynamic>.from(entry), dir));
      } catch (e) {
        debugPrint('SnapKeep: skipped an unreadable item: $e');
      }
    }

    return items;
  }

  Future<void> _writeAll(List<SavedItem> items) async {
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(_key, json);

    if (!ok) throw Exception('The device refused to store the data.');

    debugPrint('SnapKeep: saved ${items.length} item(s)');
  }

  /// Read -> change -> write, all inside the queue.
  Future<void> _modify(void Function(List<SavedItem> items) change) {
    return _serial(() async {
      final items = await _readAll();
      change(items);
      await _writeAll(items);
    });
  }

  // ───────────────────────── PUBLIC API ─────────────────────────

  /// Returns every saved item. Waits for pending writes first, so the result
  /// is always up to date.
  /// Returns every saved item that is not in "Recently deleted". Waits for
  /// pending writes first, so the result is always up to date.
  Future<List<SavedItem>> load() {
    return _serial(() async {
      final all = await _readAll();
      return all.where((e) => !e.isTrashed).toList();
    });
  }

  /// Adds [item] at [index] (default: top of the list).
  Future<void> insertItem(SavedItem item, {int index = 0}) {
    return _modify((items) {
      items.insert(index.clamp(0, items.length), item);
    });
  }

  /// Replaces the stored item that has the same id as [item].
  Future<void> replaceItem(SavedItem item) {
    return _modify((items) {
      final i = items.indexWhere((e) => e.id == item.id);
      if (i != -1) items[i] = item;
    });
  }

  Future<void> removeItem(String id) {
    return _modify((items) {
      items.removeWhere((e) => e.id == id);
    });
  }

  /// Used by the snooze flow. Changes the reminder date and marks the item
  /// as snoozed, so the UI can show a "Snoozed" label.
  ///
  /// The repeat series (repeat + repeatAnchor) is left alone, so a snooze
  /// never moves a repeating reminder.
  Future<void> updateReminderDate(String itemId, DateTime date) {
    return _modify((items) {
      final i = items.indexWhere((e) => e.id == itemId);
      if (i != -1) {
        items[i] = items[i].copyWith(reminderDate: date, wasSnoozed: true);
      }
    });
  }

  /// Moves every item from [from] to [to]. Used when a category is removed.
  Future<void> reassignCategory(String from, String to) {
    return _modify((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].category == from) {
          items[i] = items[i].copyWith(category: to);
        }
      }
    });
  }

  // ───────────────────────── REPEATING REMINDERS ─────────────────────────

  /// Moves every repeating reminder whose time has passed to its next time.
  /// Returns true if anything changed. Repeating reminders therefore never
  /// stay "Missed": they simply show the next time.
  Future<bool> rollRepeating() {
    return _serial(() async {
      final items = await _readAll();
      final now = DateTime.now();
      var changed = false;

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final reminder = item.reminderDate;

        if (!item.repeat.repeats ||
            item.isTrashed ||
            item.isDone ||
            reminder == null ||
            !reminder.isBefore(now)) {
          continue;
        }

        final next = item.repeat.nextAfter(item.repeatAnchor ?? reminder, now);
        if (next == null) continue;

        items[i] = item.copyWith(reminderDate: next, wasSnoozed: false);
        changed = true;
      }

      if (changed) await _writeAll(items);
      return changed;
    });
  }

  /// "Done" for a reminder.
  /// - Repeating: moves it to its next time and returns the updated item.
  /// - Not repeating: marks it done and returns null.
  Future<SavedItem?> markDoneOrAdvance(String itemId) {
    return _serial(() async {
      final items = await _readAll();
      final i = items.indexWhere((e) => e.id == itemId);
      if (i == -1) return null;
      if (items[i].isTrashed) return null;

      final item = items[i];
      final anchor = item.repeatAnchor ?? item.reminderDate;
      final now = DateTime.now();
      final reminder = item.reminderDate;
      final from = (reminder != null && reminder.isAfter(now)) ? reminder : now;

      final next = (item.repeat.repeats && anchor != null)
          ? item.repeat.nextAfter(anchor, from)
          : null;

      if (next != null) {
        items[i] = item.copyWith(reminderDate: next, wasSnoozed: false);
        await _writeAll(items);
        return items[i];
      }

      items[i] = item.copyWith(
        isDone: true,
        clearReminder: true,
        repeat: RepeatRule.none,
      );
      await _writeAll(items);
      return null;
    });
  }

  // ───────────────────────── IMAGES ─────────────────────────

  // ───────────────────────── RECENTLY DELETED ─────────────────────────

  /// How many days a deleted item stays in "Recently deleted".
  static const trashKeepDays = 30;

  /// Moves an item to "Recently deleted". Its image stays on the phone until
  /// the item is removed for good.
  Future<void> moveToTrash(String id) {
    return _modify((items) {
      final i = items.indexWhere((e) => e.id == id);
      if (i == -1) return;

      items[i] = items[i].copyWith(deletedAt: DateTime.now());
    });
  }

  /// Takes an item out of "Recently deleted". It returns to its old place.
  Future<void> restore(String id) {
    return _modify((items) {
      final i = items.indexWhere((e) => e.id == id);
      if (i == -1) return;

      items[i] = items[i].copyWith(clearDeleted: true);
    });
  }

  /// Items in "Recently deleted", newest first.
  Future<List<SavedItem>> loadDeleted() {
    return _serial(() async {
      final all = await _readAll();

      return all.where((e) => e.isTrashed).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    });
  }

  /// Removes one item and its image for good.
  Future<void> deletePermanently(String id) async {
    SavedItem? removed;

    await _modify((items) {
      final i = items.indexWhere((e) => e.id == id);
      if (i == -1) return;

      removed = items.removeAt(i);
    });

    final gone = removed;
    if (gone != null) await deleteImage(gone.image);
  }

  /// Removes everything in "Recently deleted" for good.
  Future<void> emptyTrash() async {
    final gone = <SavedItem>[];

    await _modify((items) {
      gone.addAll(items.where((e) => e.isTrashed));
      items.removeWhere((e) => e.isTrashed);
    });

    for (final item in gone) {
      await deleteImage(item.image);
    }
  }

  /// Removes items that were deleted more than [trashKeepDays] days ago.
  /// Returns how many were removed.
  Future<int> purgeExpired() async {
    final limit = DateTime.now().subtract(const Duration(days: trashKeepDays));
    final gone = <SavedItem>[];

    bool expired(SavedItem e) =>
        e.deletedAt != null && e.deletedAt!.isBefore(limit);

    await _modify((items) {
      gone.addAll(items.where(expired));
      items.removeWhere(expired);
    });

    for (final item in gone) {
      await deleteImage(item.image);
    }

    return gone.length;
  }

  /// Copies the picked screenshot into the app folder and returns the item
  /// pointing to the permanent copy. Throws if the copy fails.
  Future<SavedItem> persistImage(SavedItem item) async {
    final dir = await _images();

    // Already ours (e.g. an edited item): nothing to copy.
    if (p.equals(p.dirname(item.image.path), dir.path)) return item;

    final ext = p.extension(item.image.path);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';

    final copy = await item.image.copy(p.join(dir.path, name));

    debugPrint('SnapKeep: image copied to ${copy.path}');
    return item.copyWith(image: copy);
  }

  /// Deletes an image, but only if it lives in OUR folder, never a file from
  /// the user's gallery.
  Future<void> deleteImage(File file) async {
    try {
      final dir = await _images();

      if (p.equals(p.dirname(file.path), dir.path) && await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('SnapKeep: could not delete image: $e');
    }
  }

  /// Marks an item done (or not done). When done, its reminder is cleared and
  /// it stops repeating, so it no longer shows as upcoming or overdue.
  Future<void> setDone(String itemId, bool done) {
    return _modify((items) {
      final i = items.indexWhere((e) => e.id == itemId);
      if (i == -1) return;

      items[i] = done
          ? items[i].copyWith(
              isDone: true,
              clearReminder: true,
              repeat: RepeatRule.none,
            )
          : items[i].copyWith(isDone: false);
    });
  }
}
