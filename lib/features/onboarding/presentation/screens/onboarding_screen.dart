import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../widgets/onboarding_illustration.dart';
import '../widgets/onboarding_page_indicator.dart';

class _PageData {
  const _PageData({
    required this.label,
    required this.title,
    required this.description,
  });

  final String label;
  final String title;
  final String description;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _pages = <_PageData>[
    _PageData(
      label: 'YOUR SCREENSHOTS, IN ONE PLACE',
      title: 'Keep the things you’ll need later.',
      description:
          'Save useful screenshots instead of losing them in your camera roll.',
    ),
    _PageData(
      label: 'ADD A LITTLE CONTEXT',
      title: 'Find things without the scroll.',
      description:
          'Add a title or category, so saved items are easier to find again.',
    ),
    _PageData(
      label: 'REMEMBER WHEN IT MATTERS',
      title: 'Set a reminder for later.',
      description:
          'Choose when you want to be reminded about a ticket, bill, event, '
          'or anything else.',
    ),
  ];

  final PageController _pageController = PageController();

  /// Slow loop that makes the background glow drift.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat(reverse: true);

  int _currentPage = 0;
  bool _isFinishing = false;

  int get _pageCount => _pages.length;

  bool get _isLastPage => _currentPage == _pageCount - 1;

  @override
  void dispose() {
    _pageController.dispose();
    _ambient.dispose();
    super.dispose();
  }

  // Save onboarding completion and open HomeScreen.
  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;

    _isFinishing = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstTime', false);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _goToNextPage() async {
    HapticFeedback.selectionClick();

    if (_isLastPage) {
      await _finishOnboarding();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToPreviousPage() async {
    HapticFeedback.selectionClick();

    await _pageController.previousPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  // Skip jumps to the last page, so the user still sees "Get started".
  Future<void> _skipToLastPage() async {
    HapticFeedback.selectionClick();

    await _pageController.animateToPage(
      _pageCount - 1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: _AmbientBackground(
                pageController: _pageController,
                ambient: _ambient,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 680;
                  final horizontalPadding = constraints.maxWidth < 360
                      ? 20.0
                      : 24.0;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          compact ? 12 : 18,
                          horizontalPadding,
                          compact ? 12 : 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FadeSlideIn(
                              offset: const Offset(0, -14),
                              child: _Header(
                                onSkip: _skipToLastPage,
                                showSkip: !_isLastPage,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: PageView.builder(
                                controller: _pageController,
                                physics: const BouncingScrollPhysics(),
                                itemCount: _pageCount,
                                onPageChanged: (page) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _currentPage = page);
                                },
                                itemBuilder: (context, index) {
                                  return _OnboardingPage(
                                    controller: _pageController,
                                    index: index,
                                    active: _currentPage == index,
                                    compact: compact,
                                    data: _pages[index],
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 16),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 250),
                              offset: const Offset(0, 22),
                              child: _BottomBar(
                                controller: _pageController,
                                currentPage: _currentPage,
                                pageCount: _pageCount,
                                onBack: _goToPreviousPage,
                                onNext: _goToNextPage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── BACKGROUND ─────────────────────────

/// Two soft glows that drift while the user swipes and breathe on their own.
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({
    required this.pageController,
    required this.ambient,
  });

  final PageController pageController;
  final AnimationController ambient;

  Widget _glow(Alignment alignment, double size, double alpha) {
    final color = AppColors.accent.withValues(alpha: alpha);

    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([pageController, ambient]),
        builder: (context, _) {
          final page = pageController.pageValue;
          final breathe = Curves.easeInOut.transform(ambient.value);

          return Stack(
            children: [
              _glow(
                Alignment(1.1 - page * 0.55, -0.85 + breathe * 0.12),
                380,
                0.22,
              ),
              _glow(
                Alignment(-1.1 + page * 0.45, 0.95 - breathe * 0.14),
                340,
                0.13,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── PAGE ─────────────────────────

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.controller,
    required this.index,
    required this.active,
    required this.compact,
    required this.data,
  });

  final PageController controller;
  final int index;
  final bool active;
  final bool compact;
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
      child: AnimatedBuilder(
        animation: controller,
        // The scene itself is not rebuilt on every scroll tick.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: OnboardingIllustration(index: index, active: active),
        ),
        builder: (context, scene) {
          // -1 .. 1: how far this page is from the centre.
          final delta = controller.pageValue - index;
          final distance = delta.abs().clamp(0.0, 1.0).toDouble();
          final textOpacity = (1 - distance * 1.4).clamp(0.0, 1.0).toDouble();

          return Column(
            children: [
              Expanded(
                child: Center(
                  // The scene moves a bit faster than the page (parallax).
                  child: Transform.translate(
                    offset: Offset(-delta * 90, 0),
                    child: Transform.scale(
                      scale: 1 - distance * 0.18,
                      child: scene,
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 12 : 22),
              Opacity(
                opacity: textOpacity,
                child: Transform.translate(
                  offset: Offset(-delta * 40, 0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          data.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        data.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: compact ? 25 : 29,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        data.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 16),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── HEADER ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onSkip, required this.showSkip});

  final VoidCallback onSkip;
  final bool showSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.elasticOut,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
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
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.bookmark_border_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'SnapKeep',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: showSkip ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !showSkip,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryText,
              ),
              child: const Text('Skip'),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── BOTTOM BAR ─────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.currentPage,
    required this.pageCount,
    required this.onBack,
    required this.onNext,
  });

  final PageController controller;
  final int currentPage;
  final int pageCount;
  final VoidCallback onBack;
  final VoidCallback onNext;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final isFirst = currentPage == 0;
    final isLast = currentPage == pageCount - 1;

    return SizedBox(
      height: _size,
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: isFirst ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: isFirst,
              child: Tooltip(
                message: 'Back',
                child: PressScale(
                  onTap: onBack,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondaryText.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: OnboardingPageIndicator(
                controller: controller,
                pageCount: pageCount,
              ),
            ),
          ),
          Tooltip(
            message: isLast ? 'Get started' : 'Next',
            child: PressScale(
              onTap: onNext,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                height: _size,
                width: isLast ? 156 : _size,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(_size / 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: isLast
                      ? const FittedBox(
                          key: ValueKey('start'),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Get started',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          key: ValueKey('next'),
                          size: 24,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
