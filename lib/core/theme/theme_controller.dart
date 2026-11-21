import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_service.dart';
import 'app_colors.dart';

/// Switches between light and dark with a circular wave that starts at the
/// top-right corner and sweeps toward the bottom-left.
class ThemeController {
  ThemeController._();

  static const _prefKey = 'is_dark_mode';

  /// Wraps the whole app. Used to take the "before" screenshot and to
  /// rebuild every screen after the theme changes.
  static final GlobalKey appBoundaryKey = GlobalKey();

  static bool _busy = false;

  /// Call once in main(), before runApp.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    AppColors.darkMode.value = prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setDark(bool dark) async {
    if (_busy || dark == AppColors.darkMode.value) return;
    _busy = true;

    try {
      // 1. Screenshot of the current (old) theme.
      final snapshot = await _captureApp();

      // 2. Switch the theme and rebuild every visible screen.
      AppColors.darkMode.value = dark;
      _rebuildAll();

      // 3. Old screenshot covers the screen and shrinks away as a wave.
      _showWave(snapshot);

      SharedPreferences.getInstance().then((p) => p.setBool(_prefKey, dark));
    } finally {
      _busy = false;
    }
  }

  static Future<ui.Image?> _captureApp() async {
    final ctx = appBoundaryKey.currentContext;
    if (ctx == null) return null;

    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final dpr = MediaQuery.devicePixelRatioOf(ctx);
    return boundary.toImage(pixelRatio: dpr);
  }

  /// Marks every element below the app as dirty, so screens that read
  /// AppColors directly (without a Theme lookup) also repaint.
  static void _rebuildAll() {
    final root = appBoundaryKey.currentContext;
    if (root is! Element) return;

    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    visit(root);
  }

  static void _showWave(ui.Image? snapshot) {
    if (snapshot == null) return;

    final overlay = NotificationService.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      snapshot.dispose();
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ThemeWave(
        snapshot: snapshot,
        onDone: () {
          entry.remove();
          snapshot.dispose();
        },
      ),
    );

    overlay.insert(entry);
  }
}

// ───────────────────────── WAVE OVERLAY ─────────────────────────

class _ThemeWave extends StatefulWidget {
  const _ThemeWave({required this.snapshot, required this.onDone});

  final ui.Image snapshot;
  final VoidCallback onDone;

  @override
  State<_ThemeWave> createState() => _ThemeWaveState();
}

class _ThemeWaveState extends State<_ThemeWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed) widget.onDone();
  });

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final t = Curves.easeInOutCubic.transform(_controller.value);

            return ClipPath(
              clipper: _WaveClipper(t),
              child: RawImage(
                image: widget.snapshot,
                fit: BoxFit.fill,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Keeps the old screen everywhere OUTSIDE a growing circle. The circle is
/// centred on the top-right corner, so the new theme appears from there and
/// spreads toward the bottom-left.
class _WaveClipper extends CustomClipper<Path> {
  _WaveClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final center = Offset(size.width, 0);
    final maxRadius = math.sqrt(
      size.width * size.width + size.height * size.height,
    );

    final full = Path()..addRect(Offset.zero & size);
    final circle = Path()
      ..addOval(
        Rect.fromCircle(center: center, radius: maxRadius * progress),
      );

    return Path.combine(PathOperation.difference, full, circle);
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) =>
      oldClipper.progress != progress;
}