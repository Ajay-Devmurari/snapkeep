import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

const double _kWidth = 340;
const double _kHeight = 270;

/// The animated scene of one onboarding page.
///
/// [active] turns true when the page is the current one. The entrance
/// animation plays then. A slow loop (floating, ringing) always runs.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    required this.index,
    required this.active,
    super.key,
  });

  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Widget scene;

    switch (index) {
      case 0:
        scene = _FanScene(active: active);
      case 1:
        scene = _ContextScene(active: active);
      default:
        scene = _ReminderScene(active: active);
    }

    return SizedBox(width: _kWidth, height: _kHeight, child: scene);
  }
}

// ───────────────────────── HELPERS ─────────────────────────

/// 0..1 progress of [t] between [begin] and [end], shaped by [curve].
double _seg(
  double t,
  double begin,
  double end, [
  Curve curve = Curves.easeOutCubic,
]) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return curve.transform((t - begin) / (end - begin));
}

double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

/// A surface slightly lighter than the background, in dark and light mode.
Color _raised([double a = 0.06]) =>
    Color.alphaBlend(AppColors.text.withValues(alpha: a), AppColors.surface);

BoxDecoration _panelDecoration({double radius = 22}) {
  return BoxDecoration(
    color: _raised(),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

Widget _tiny(String text) {
  return Text(
    text,
    style: TextStyle(
      color: AppColors.secondaryText,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
    ),
  );
}

// ───────────────────────── SCENE BASE ─────────────────────────

abstract class _Scene extends StatefulWidget {
  const _Scene({required this.active});

  final bool active;
}

abstract class _SceneState<T extends _Scene> extends State<T>
    with TickerProviderStateMixin<T> {
  /// Plays once when the page becomes active.
  late final AnimationController enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// Runs forever: floating, ringing, blinking.
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );

  @override
  void initState() {
    super.initState();
    loop.repeat();
    if (widget.active) enter.forward();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && enter.value < 1) {
      enter.forward();
    }
  }

  @override
  void dispose() {
    enter.dispose();
    loop.dispose();
    super.dispose();
  }

  /// [t] is the entrance progress (0..1), [f] the loop angle (0..2π).
  Widget buildScene(BuildContext context, double t, double f);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([enter, loop]),
      builder: (context, _) =>
          buildScene(context, enter.value, loop.value * 2 * math.pi),
    );
  }
}

// ───────────────────────── SCENE 1: CARD FAN ─────────────────────────

class _FanScene extends _Scene {
  const _FanScene({required super.active});

  @override
  State<_FanScene> createState() => _FanSceneState();
}

class _FanSceneState extends _SceneState<_FanScene> {
  @override
  Widget buildScene(BuildContext context, double t, double f) {
    final spread = _seg(t, 0.18, 0.78, Curves.easeOutBack);
    final drop = _seg(t, 0.0, 0.42, Curves.easeOutBack);
    final fade = _seg(t, 0.0, 0.25, Curves.easeOut);
    final badge = _seg(t, 0.62, 1.0, Curves.elasticOut);

    double bob(double phase) => math.sin(f + phase) * 5;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft glow on the "ground" that breathes with the cards.
        Positioned(
          bottom: 12,
          child: Opacity(
            opacity: fade,
            child: Container(
              width: 170 + math.sin(f + 1.5) * 10,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.28),
                    blurRadius: 26,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Left card.
        Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(-96 * spread, 8 + bob(0)),
            child: Transform.rotate(
              angle: -0.13 * spread,
              child: const _ScreenshotCard(
                width: 136,
                height: 188,
                type: _CardType.ticket,
              ),
            ),
          ),
        ),

        // Right card.
        Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(96 * spread, 8 + bob(3.0)),
            child: Transform.rotate(
              angle: 0.13 * spread,
              child: const _ScreenshotCard(
                width: 136,
                height: 188,
                type: _CardType.bill,
              ),
            ),
          ),
        ),

        // Centre card drops in on top.
        Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, -46 * (1 - drop) + bob(1.5)),
            child: const _ScreenshotCard(
              width: 150,
              height: 196,
              type: _CardType.event,
            ),
          ),
        ),

        // "Saved" badge pops on the corner of the centre card.
        Transform.translate(
          offset: Offset(68, -98 + bob(1.5)),
          child: Transform.scale(
            scale: badge,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.bookmark_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _CardType { event, bill, ticket }

class _ScreenshotCard extends StatelessWidget {
  const _ScreenshotCard({
    required this.width,
    required this.height,
    required this.type,
  });

  final double width;
  final double height;
  final _CardType type;

  @override
  Widget build(BuildContext context) {
    final isEvent = type == _CardType.event;
    final isBill = type == _CardType.bill;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.09),
      decoration: BoxDecoration(
        color: _raised(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEvent)
            Container(
              height: height * 0.38,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.35),
                    AppColors.softViolet,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Icons.music_note_rounded,
                  size: 30,
                  color: AppColors.accent,
                ),
              ),
            )
          else
            Row(
              children: [
                Icon(
                  isBill
                      ? Icons.receipt_long_outlined
                      : Icons.confirmation_number_outlined,
                  size: 20,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 7),
                Text(
                  isBill ? 'BILL' : 'TICKET',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          SizedBox(height: height * 0.06),
          Text(
            isEvent
                ? 'Live music night'
                : isBill
                ? 'Electricity bill'
                : 'Train ticket',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          _SkeletonLine(width: width * 0.70),
          const SizedBox(height: 5),
          _SkeletonLine(width: width * 0.48, light: true),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 15,
                color: AppColors.accent,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  isEvent
                      ? '18 Jun'
                      : isBill
                      ? '₹1,240'
                      : '22 Jun',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, this.light = false});

  final double width;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: light ? 0.06 : 0.11),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ───────────────────────── SCENE 2: ADD CONTEXT ─────────────────────────

class _ContextScene extends _Scene {
  const _ContextScene({required super.active});

  @override
  State<_ContextScene> createState() => _ContextSceneState();
}

class _ContextSceneState extends _SceneState<_ContextScene> {
  static const _title = 'Electricity bill';

  static const _chips = <(IconData, String)>[
    (Icons.receipt_long_outlined, 'Bills'),
    (Icons.flight_outlined, 'Travel'),
    (Icons.event_outlined, 'Events'),
  ];

  @override
  Widget buildScene(BuildContext context, double t, double f) {
    final panelIn = _seg(t, 0.0, 0.35, Curves.easeOutBack);
    final typedFraction = _seg(t, 0.12, 0.58, Curves.linear);
    final typed = math.min(
      _title.length,
      (_title.length * typedFraction).floor(),
    );
    final select = _seg(t, 0.64, 0.82);
    final suggest = _seg(t, 0.78, 1.0, Curves.easeOutBack);
    final cursorOn = typed < _title.length || math.sin(f * 6) > 0;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Opacity(
          opacity: _clamp01(panelIn),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - panelIn) + math.sin(f) * 3),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: _panelDecoration(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.accent.withValues(alpha: 0.35),
                              AppColors.softViolet,
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 24,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _tiny('TITLE'),
                            const SizedBox(height: 6),
                            Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: AppColors.text.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _title.substring(0, typed),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Opacity(
                                    opacity: cursorOn ? 1 : 0,
                                    child: Container(
                                      width: 2,
                                      height: 18,
                                      color: AppColors.accent,
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
                  const SizedBox(height: 16),
                  _tiny('CATEGORY'),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        for (var i = 0; i < _chips.length; i++)
                          _chip(i, t, select),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: _clamp01(suggest),
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - suggest)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 14,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Category suggested automatically',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(int i, double t, double select) {
    final appear = _seg(
      t,
      0.30 + i * 0.06,
      0.52 + i * 0.06,
      Curves.easeOutBack,
    );
    final isSelected = i == 0;
    final s = isSelected ? select : 0.0;

    final background = Color.lerp(
      AppColors.text.withValues(alpha: 0.06),
      AppColors.accent,
      s,
    )!;
    final foreground = Color.lerp(
      AppColors.text.withValues(alpha: 0.75),
      Colors.white,
      s,
    )!;
    final pop = isSelected ? 1 + 0.12 * math.sin(math.pi * s) : 1.0;

    final (icon, label) = _chips[i];

    return Padding(
      padding: EdgeInsets.only(right: i == _chips.length - 1 ? 0 : 8),
      child: Opacity(
        opacity: _clamp01(appear),
        child: Transform.scale(
          scale: (0.6 + 0.4 * appear) * pop,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── SCENE 3: REMINDER ─────────────────────────

class _ReminderScene extends _Scene {
  const _ReminderScene({required super.active});

  @override
  State<_ReminderScene> createState() => _ReminderSceneState();
}

class _ReminderSceneState extends _SceneState<_ReminderScene> {
  static const _actions = <String>['+5 min', 'Custom', 'Done'];

  @override
  Widget buildScene(BuildContext context, double t, double f) {
    final bellIn = _seg(t, 0.0, 0.32, Curves.easeOutBack);
    final cardIn = _seg(t, 0.22, 0.66, Curves.easeOutBack);
    final loopValue = f / (2 * math.pi);

    // The bell rings in short bursts, then rests.
    final burst = math.pow(math.max(0.0, math.sin(f - 0.6)), 2).toDouble();
    final swing = math.sin(f * 10) * 0.30 * burst * _clamp01(bellIn);

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    for (final k in [0.0, 0.5])
                      _ring(k, loopValue, _clamp01(bellIn)),
                    Transform.scale(
                      scale: bellIn,
                      child: Transform.rotate(
                        angle: swing,
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.45),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: _clamp01(cardIn),
                child: Transform.translate(
                  offset: Offset(0, 36 * (1 - cardIn)),
                  child: _notificationCard(t),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double offset, double loopValue, double visible) {
    final p = (loopValue + offset) % 1.0;
    final size = 64 + 48 * p;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: (1 - p) * 0.38 * visible),
          width: 2,
        ),
      ),
    );
  }

  Widget _notificationCard(double t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(radius: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.bookmark_border_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SnapKeep',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'now',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Electricity bill',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Due today · Tap to open',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _action(i, t)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(int i, double t) {
    final appear = _seg(
      t,
      0.62 + i * 0.07,
      0.84 + i * 0.07,
      Curves.easeOutBack,
    );
    final primary = i == _actions.length - 1;

    return Opacity(
      opacity: _clamp01(appear),
      child: Transform.scale(
        scale: 0.7 + 0.3 * appear,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? AppColors.accent
                : AppColors.text.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            _actions[i],
            style: TextStyle(
              color: primary ? Colors.white : AppColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
