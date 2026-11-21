import 'package:flutter/material.dart';
import 'package:snapkeep/core/categories/category_store.dart';
import 'package:snapkeep/core/theme/app_colors.dart';
import 'package:snapkeep/features/data/saved_items_storage.dart';
import 'package:snapkeep/features/home/models/saved_item.dart';

const _red = Color(0xFFD6574E);

/// manage: home screen se. Add, remove, counts. Changes save at once.
/// pick:   details screen se. Only returns the chosen name. Nothing is saved
///         until the screenshot itself is saved.
enum CategorySheetMode { manage, pick }

/// Opens the category sheet. Returns:
/// - pick mode: the chosen or new category name, or null if dismissed.
/// - manage mode: the name of a category added during this visit, or null.
Future<String?> showCategorySheet(
  BuildContext context, {
  CategorySheetMode mode = CategorySheetMode.manage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _CategorySheet(mode: mode),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.mode});

  final CategorySheetMode mode;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final TextEditingController _controller = TextEditingController();
  final Map<String, int> _counts = {};

  String? _error;
  String? _lastAdded;

  bool get _pickMode => widget.mode == CategorySheetMode.pick;

  @override
  void initState() {
    super.initState();
    if (!_pickMode) _loadCounts();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final items = await SavedItemsStorage.instance.load();
    if (!mounted) return;

    setState(() {
      _counts.clear();
      for (final SavedItem item in items) {
        _counts[item.category] = (_counts[item.category] ?? 0) + 1;
      }
    });
  }

  Future<void> _add(String raw) async {
    if (_pickMode) {
      // Nothing is saved here. The name goes back to the details screen,
      // which saves it only when the screenshot is saved.
      final name = CategoryStore.normalize(raw);

      if (name.isEmpty) {
        setState(() => _error = 'Type a name first.');
        return;
      }

      // Already exists: just select the existing one.
      final existing = CategoryStore.find(name);
      if (existing != null) {
        Navigator.pop(context, existing);
        return;
      }

      final error = CategoryStore.validate(name);
      if (error != null) {
        setState(() => _error = error);
        return;
      }

      Navigator.pop(context, name);
      return;
    }

    // manage mode: saved right away.
    final error = await CategoryStore.add(raw);
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    _controller.clear();
    setState(() {
      _error = null;
      _lastAdded = CategoryStore.normalize(raw);
    });
  }

  Future<void> _remove(String name) async {
    final count = _counts[name] ?? 0;

    if (count > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Remove "$name"?'),
          content: Text(
            '$count item${count == 1 ? '' : 's'} will move to '
            '${CategoryStore.fallback}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: _red)),
            ),
          ],
        ),
      );

      if (ok != true) return;
    }

    await SavedItemsStorage.instance.reassignCategory(
      name,
      CategoryStore.fallback,
    );
    await CategoryStore.remove(name);

    if (mounted) _loadCounts();
  }

  Color get _fill => AppColors.text.withValues(alpha: 0.045);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pickMode ? 'Add category' : 'Categories',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () =>
                        Navigator.pop(context, _pickMode ? null : _lastAdded),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
              Text(
                _pickMode
                    ? 'It is saved only when you save the screenshot.'
                    : 'Add your own. Removing one moves its items to '
                          '${CategoryStore.fallback}.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              _addRow(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: _red, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 14),
              _suggestionsRow(),
              if (!_pickMode) ...[
                const SizedBox(height: 20),
                Text(
                  'YOUR CATEGORIES',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<List<String>>(
                  valueListenable: CategoryStore.categories,
                  builder: (context, names, _) => Column(
                    children: [for (final name in names) _categoryRow(name)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            cursorColor: AppColors.accent,
            onSubmitted: _add,
            style: TextStyle(color: AppColors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'New category, e.g. Gym',
              hintStyle: TextStyle(
                color: AppColors.text.withValues(alpha: 0.4),
                fontSize: 14.5,
              ),
              filled: true,
              fillColor: _fill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => _add(_controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Add',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _suggestionsRow() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: CategoryStore.categories,
      builder: (context, names, _) {
        final left = CategoryStore.suggestions
            .where((s) => !names.any((n) => n.toLowerCase() == s.toLowerCase()))
            .toList();

        if (left.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUGGESTED',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in left)
                  ActionChip(
                    avatar: Icon(
                      CategoryStore.iconFor(s),
                      size: 16,
                      color: AppColors.accent,
                    ),
                    label: Text('+ $s'),
                    labelStyle: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.softAccent,
                    side: BorderSide.none,
                    onPressed: () => _add(s),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _categoryRow(String name) {
    final isFallback = name == CategoryStore.fallback;
    final count = _counts[name] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.softAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CategoryStore.iconFor(name),
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    count == 0
                        ? 'No items'
                        : '$count item${count == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isFallback)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  'Default',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Remove $name',
                onPressed: () => _remove(name),
                icon: const Icon(Icons.delete_outline_rounded, color: _red),
              ),
          ],
        ),
      ),
    );
  }
}
