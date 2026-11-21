import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_colors.dart';
import '../widgets/onboarding_page_indicator.dart';
import '../../../home/presentation/screens/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 3;

  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _isFinishing = false;

  bool get _isLastPage => _currentPage == _pageCount - 1;

  @override
  void dispose() {
    _pageController.dispose();
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
      MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(),
      ),
    );
  }

  Future<void> _goToNextPage() async {
    if (_isLastPage) {
      await _finishOnboarding();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goToPreviousPage() async {
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // Skip directly to HomeScreen.
  Future<void> _skipOnboarding() async {
    await _finishOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
      ),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;

              final horizontalPadding =
              constraints.maxWidth < 360 ? 20.0 : 24.0;

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
                        _Header(
                          onSkip: _skipOnboarding,
                          showSkip: !_isLastPage,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (page) {
                              setState(() {
                                _currentPage = page;
                              });
                            },
                            children: [
                              _OnboardingPage(
                                compact: compact,
                                icon: Icons.collections_bookmark_outlined,
                                label: 'YOUR SCREENSHOTS, IN ONE PLACE',
                                title: 'Keep the things you’ll need later.',
                                description:
                                'Save useful screenshots instead of losing '
                                    'them in your camera roll.',
                              ),
                              _OnboardingPage(
                                compact: compact,
                                icon: Icons.edit_note_rounded,
                                label: 'ADD A LITTLE CONTEXT',
                                title: 'Find things without the scroll.',
                                description:
                                'Add a title or category, so saved items '
                                    'are easier to find again.',
                              ),
                              _OnboardingPage(
                                compact: compact,
                                icon: Icons.notifications_none_rounded,
                                label: 'REMEMBER WHEN IT MATTERS',
                                title: 'Set a reminder for later.',
                                description:
                                'Choose when you want to be reminded about '
                                    'a ticket, bill, event, or anything else.',
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 16),
                        _BottomBar(
                          currentPage: _currentPage,
                          pageCount: _pageCount,
                          onBack: _goToPreviousPage,
                          onNext: _goToNextPage,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── BOTTOM BAR ─────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentPage,
    required this.pageCount,
    required this.onBack,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final VoidCallback onBack;
  final VoidCallback onNext;

  static const double _size = 48;

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
              child: _CircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                color: AppColors.secondaryText,
                borderColor:
                AppColors.secondaryText.withValues(alpha: 0.45),
                onPressed: onBack,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: OnboardingPageIndicator(
                currentPage: currentPage,
                pageCount: pageCount,
              ),
            ),
          ),
          _CircleIconButton(
            icon: isLast
                ? Icons.check_rounded
                : Icons.arrow_forward_rounded,
            tooltip: isLast ? 'Get started' : 'Next',
            color: AppColors.accent,
            borderColor: AppColors.accent,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── CIRCLE BUTTON ─────────────────────────

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.borderColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final Color borderColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          fixedSize: const Size(
            _BottomBar._size,
            _BottomBar._size,
          ),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          side: BorderSide(
            color: borderColor,
            width: 1.2,
          ),
          foregroundColor: color,
          elevation: 0,
        ),
        child: Icon(
          icon,
          size: 22,
          color: color,
        ),
      ),
    );
  }
}

// ───────────────────────── HEADER ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onSkip,
    required this.showSkip,
  });

  final VoidCallback onSkip;
  final bool showSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.softViolet,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.bookmark_border_rounded,
            size: 19,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'SnapKeep',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
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
              child: const Text('Skip'),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── ONBOARDING PAGE ─────────────────────────

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.compact,
    required this.icon,
    required this.label,
    required this.title,
    required this.description,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 8 : 16,
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _IllustrationCard(
                  icon: icon,
                  label: label,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: compact ? 26 : 30,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: compact ? 12 : 20),
        ],
      ),
    );
  }
}

// ───────────────────────── ILLUSTRATION CARD ─────────────────────────

class _IllustrationCard extends StatelessWidget {
  const _IllustrationCard({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.softViolet,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 34,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 8,
            width: 128,
            decoration: BoxDecoration(
              color: const Color(0xFFEAE9E6),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 9),
          Container(
            height: 7,
            width: 92,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFEC),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}