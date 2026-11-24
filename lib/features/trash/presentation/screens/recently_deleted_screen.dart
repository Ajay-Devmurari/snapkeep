import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snapkeep/core/notifications/notification_service.dart';
import 'package:snapkeep/core/theme/app_colors.dart';
import 'package:snapkeep/core/widgets/motion.dart';
import 'package:snapkeep/features/data/saved_items_storage.dart';
import 'package:snapkeep/features/home/models/saved_item.dart';

const _red = Color(0xFFD6574E);

/// Deleted screenshots stay here for 30 days. From here they can be restored
/// or removed for good.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  final SavedItemsStorage _storage = SavedItemsStorage.instance;
  final List<SavedItem> _items = [];

  // Ids that are being restored or deleted right now. Stops double taps.
  final Set<String> _busyIds = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final deleted = await _storage.loadDeleted();
      if (!mounted) return;

      setState(() {
        _items
          ..clear()
          ..addAll(deleted);
        _loading = false;
      });
    } catch (e) {
      debugPrint('SnapKeep: could not load deleted items: $e');
      if (!mounted) return;

      setState(() => _loading = false);
    }
  }

  // ───────────────────────── HELPERS ─────────────────────────

  int _daysAgo(SavedItem item) => DateUtils.dateOnly(
    DateTime.now(),
  ).difference(DateUtils.dateOnly(item.deletedAt!)).inDays;

  int _daysLeft(SavedItem item) {
    final left = SavedItemsStorage.trashKeepDays - _daysAgo(item);
    return left < 0 ? 0 : left;
  }

  String _deletedLabel(SavedItem item) {
    final days = _daysAgo(item);
    if (days <= 0) return 'Deleted today';
    if (days == 1) return 'Deleted yesterday';
    return 'Deleted $days days ago';
  }

  String _leftLabel(int left) {
    if (left <= 0) return 'Removed soon';
    if (left == 1) return '1 day left';
    return '$left days left';
  }

  void _snack(String message) {
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

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              action,
              style: const TextStyle(
                color: _red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  Future<void> _restore(SavedItem item) async {
    if (_busyIds.contains(item.id)) return;
    _busyIds.add(item.id);
    HapticFeedback.lightImpact();

    try {
      await _storage.restore(item.id);
    } catch (e) {
      _busyIds.remove(item.id);
      _snack('Could not restore the item.');
      return;
    }

    if (mounted) {
      setState(() => _items.removeWhere((e) => e.id == item.id));
    }

    // Bring its reminder back, then tell the home screen to reload.
    try {
      await NotificationService.instance.schedule(item);
    } catch (e) {
      debugPrint('SnapKeep: could not schedule restored item: $e');
    }
    NotificationService.changes.value++;
    _busyIds.remove(item.id);

    _snack('Restored to your list');
  }

  Future<void> _deleteForever(SavedItem item) async {
    if (_busyIds.contains(item.id)) return;

    final ok = await _confirm(
      title: 'Delete permanently?',
      message: 'This screenshot will be gone for good. This cannot be undone.',
      action: 'Delete',
    );
    if (ok != true || !mounted) return;

    _busyIds.add(item.id);
    HapticFeedback.mediumImpact();
    setState(() => _items.removeWhere((e) => e.id == item.id));

    try {
      await _storage.deletePermanently(item.id);
    } catch (e) {
      debugPrint('SnapKeep: could not delete permanently: $e');
    } finally {
      _busyIds.remove(item.id);
    }
  }

  Future<void> _emptyAll() async {
    final ok = await _confirm(
      title: 'Empty Recently deleted?',
      message:
      'All ${_items.length} screenshots here will be gone for good. '
          'This cannot be undone.',
      action: 'Delete all',
    );
    if (ok != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(_items.clear);

    try {
      await _storage.emptyTrash();
    } catch (e) {
      debugPrint('SnapKeep: could not empty trash: $e');
    }
  }

  void _preview(SavedItem item) {
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
    );
  }

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Recently deleted',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Delete all',
              onPressed: _emptyAll,
              icon: const Icon(Icons.delete_sweep_outlined, color: _red),
            ),
        ],
      ),
      body: _loading
          ? const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      )
          : _items.isEmpty
          ? _buildEmpty()
          : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              FadeSlideIn(child: _buildInfo()),
              const SizedBox(height: 16),
              for (var i = 0; i < _items.length; i++)
                FadeSlideIn(
                  key: ValueKey(_items[i].id),
                  delay: Duration(milliseconds: 60 + (i < 8 ? i : 8) * 40),
                  child: _buildCard(_items[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Deleted screenshots stay here for '
                  '${SavedItemsStorage.trashKeepDays} days, then they are removed '
                  'for good.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(SavedItem item) {
    final left = _daysLeft(item);
    final urgent = left <= 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.text.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _preview(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.file(
                      item.image,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 58,
                        height: 58,
                        color: AppColors.text.withValues(alpha: 0.06),
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.text.withValues(alpha: 0.4),
                        ),
                      ),
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
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.category} · ${_deletedLabel(item)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _leftLabel(left),
                        style: TextStyle(
                          color: urgent ? _red : AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _restore(item),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.restore_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Restore',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Delete permanently',
                  child: Material(
                    color: _red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _deleteForever(item),
                      child: const SizedBox(
                        width: 48,
                        height: 44,
                        child: Icon(
                          Icons.delete_forever_outlined,
                          size: 20,
                          color: _red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                Icons.delete_outline_rounded,
                size: 36,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Nothing here',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Deleted screenshots stay here for '
                  '${SavedItemsStorage.trashKeepDays} days.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.secondaryText, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}