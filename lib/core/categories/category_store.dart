import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the category list (defaults + user added) and saves it on the device.
/// Screens listen to [categories], so every chip and picker updates at once.
class CategoryStore {
  CategoryStore._();

  static const _key = 'categories_v1';

  /// Items of a removed category move here. Always kept, always last.
  static const fallback = 'Other';

  static const maxLength = 20;

  static const defaults = ['Bills', 'Travel', 'Events', 'Shopping', 'Other'];

  /// Ready-made ideas shown in the category sheet.
  static const suggestions = ['Gym', 'Market', 'Medical', 'Mall'];

  static final ValueNotifier<List<String>> categories =
  ValueNotifier<List<String>>(List<String>.of(defaults));

  static const _icons = <String, IconData>{
    'Bills': Icons.receipt_long_outlined,
    'Travel': Icons.flight_takeoff_rounded,
    'Events': Icons.event_outlined,
    'Shopping': Icons.shopping_bag_outlined,
    'Other': Icons.folder_outlined,
    'Gym': Icons.fitness_center_rounded,
    'Market': Icons.storefront_outlined,
    'Medical': Icons.local_hospital_outlined,
    'Mall': Icons.local_mall_outlined,
  };

  /// Known names get their own icon, user categories get a generic one.
  static IconData iconFor(String name) =>
      _icons[name] ?? Icons.label_outline_rounded;

  /// "  gym " -> "Gym"
  static String normalize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Stored name that matches [raw] ignoring case, or null.
  static String? find(String raw) {
    final lower = normalize(raw).toLowerCase();
    if (lower.isEmpty) return null;

    for (final c in categories.value) {
      if (c.toLowerCase() == lower) return c;
    }
    return null;
  }

  /// Error message if [raw] cannot be added, or null when it is fine.
  /// Saves nothing.
  static String? validate(String raw) {
    final name = normalize(raw);

    if (name.isEmpty) return 'Type a name first.';
    if (name.length > maxLength) {
      return 'Keep it under $maxLength characters.';
    }

    final lower = name.toLowerCase();
    if (lower == 'all' || lower == 'done') {
      return '"$name" is reserved. Try another name.';
    }
    if (find(name) != null) {
      return '"$name" already exists.';
    }
    return null;
  }

  /// Call once in main() before runApp.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);

    if (saved == null || saved.isEmpty) {
      categories.value = List<String>.of(defaults);
      return;
    }

    final list = saved.where((e) => e.trim().isNotEmpty).toList();
    if (!list.contains(fallback)) list.add(fallback);

    categories.value = list;
  }

  static Future<void> _save(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list);
  }

  /// Adds a category and saves it. Returns an error message, or null on
  /// success. Call this only when the category should really be kept.
  static Future<String?> add(String raw) async {
    final error = validate(raw);
    if (error != null) return error;

    final name = normalize(raw);
    final list = List<String>.of(categories.value);

    // Insert just above "Other", which always stays last.
    list.insert(list.length - 1, name);

    categories.value = list;
    await _save(list);
    return null;
  }

  /// Removes a category. Call SavedItemsStorage.reassignCategory first, so no
  /// item is left pointing to a category that no longer exists.
  static Future<void> remove(String name) async {
    if (name == fallback) return;

    final list = List<String>.of(categories.value)..remove(name);

    categories.value = list;
    await _save(list);
  }
}