import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/widgets/motion.dart';
import 'package:snapkeep/features/data/saved_items_storage.dart';
import 'package:snapkeep/features/trash/presentation/screens/recently_deleted_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          'Settings',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: AppColors.darkMode,
        builder: (context, dark, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const FadeSlideIn(child: _HeroCard()),
                  const SizedBox(height: 30),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 120),
                    child: _SectionLabel('APPEARANCE'),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 180),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ThemeCard(dark: false, selected: !dark),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: _ThemeCard(dark: true, selected: dark)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 240),
                    child: _SectionLabel('DATA'),
                  ),
                  const SizedBox(height: 12),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 290),
                    child: _RecentlyDeletedTile(),
                  ),
                  const SizedBox(height: 30),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 260),
                    child: _SectionLabel('ABOUT'),
                  ),
                  const SizedBox(height: 12),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 320),
                    child: _AboutCard(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── SECTION LABEL ─────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ───────────────────────── RECENTLY DELETED TILE ─────────────────────────

class _RecentlyDeletedTile extends StatefulWidget {
  const _RecentlyDeletedTile();

  @override
  State<_RecentlyDeletedTile> createState() => _RecentlyDeletedTileState();
}

class _RecentlyDeletedTileState extends State<_RecentlyDeletedTile> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final deleted = await SavedItemsStorage.instance.loadDeleted();
      if (!mounted) return;

      setState(() => _count = deleted.length);
    } catch (e) {
      debugPrint('SnapKeep: could not count deleted items: $e');
    }
  }

  Future<void> _open() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecentlyDeletedScreen()),
    );

    // Items may have been restored or removed meanwhile.
    if (mounted) _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.98,
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.text.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.softAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recently deleted',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kept for ${SavedItemsStorage.trashKeepDays} days, then '
                        'removed for good.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (_count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_count',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── HERO CARD ─────────────────────────

class _HeroCard extends StatefulWidget {
  const _HeroCard();

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accent.withValues(alpha: 0.26),
              AppColors.accent.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Stack(
          children: [
            // A soft glow that slowly circles in the corner.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) {
                  final a = _loop.value * 2 * math.pi;
                  final color = AppColors.accent.withValues(alpha: 0.30);

                  return Align(
                    alignment: Alignment(
                      0.95 + math.sin(a) * 0.12,
                      -0.9 + math.cos(a) * 0.25,
                    ),
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [color, color.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent,
                            AppColors.accent.withValues(alpha: 0.7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.bookmark_border_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SnapKeep',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Screenshots you’ll need later, back right when '
                              'you need them.',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── THEME CARD ─────────────────────────

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.dark, required this.selected});

  final bool dark;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.96,
      onTap: () {
        HapticFeedback.selectionClick();
        ThemeController.setDark(dark);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.text.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.6,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ]
              : const [],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _preview(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size: 16,
                  color: selected ? AppColors.accent : AppColors.secondaryText,
                ),
                const SizedBox(width: 6),
                Text(
                  dark ? 'Dark' : 'Light',
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.secondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  /// A tiny fixed-colour mock of the home screen in this theme.
  Widget _preview() {
    final background = dark ? const Color(0xFF1B1C1F) : const Color(0xFFF6F5F2);
    final bar = dark ? const Color(0xFF2D2E33) : const Color(0xFFE5E3DE);
    final line = dark ? const Color(0xFF8A8B91) : const Color(0xFF9A9892);

    Widget tile() {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accent.withValues(alpha: dark ? 0.55 : 0.75),
              bar,
            ],
          ),
        ),
      );
    }

    return Container(
      color: background,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                width: 34,
                height: 5,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: bar,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile()),
                const SizedBox(width: 6),
                Expanded(child: tile()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── ABOUT CARD ─────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const _AboutRow(
            icon: Icons.phone_android_rounded,
            title: 'Stored on your phone',
            subtitle:
            'Your screenshots and reminders stay only on this device.',
          ),
          Divider(height: 1, thickness: 0.6, color: AppColors.border),
          const _AboutRow(
            icon: Icons.wifi_off_rounded,
            title: 'Works offline',
            subtitle: 'No internet needed to save or find your items.',
          ),
          Divider(height: 1, thickness: 0.6, color: AppColors.border),
          const _AboutRow(
            icon: Icons.alarm_on_rounded,
            title: 'On-time reminders',
            subtitle: 'Reminders ring at the exact minute you choose.',
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.softAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}