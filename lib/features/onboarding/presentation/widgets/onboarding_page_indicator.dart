import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Current page of a [PageController] as a double (for example 1.37 while
/// swiping), safe to read before the first layout.
extension PageControllerValue on PageController {
  double get pageValue {
    if (!hasClients) return initialPage.toDouble();
    return page ?? initialPage.toDouble();
  }
}

/// Dots that stretch and change colour smoothly while the user swipes.
class OnboardingPageIndicator extends StatelessWidget {
  const OnboardingPageIndicator({
    required this.controller,
    required this.pageCount,
    super.key,
  });

  final PageController controller;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.pageValue;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(pageCount, (index) {
            final t = (1 - (page - index).abs()).clamp(0.0, 1.0).toDouble();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6 + 18 * t,
              height: 6,
              decoration: BoxDecoration(
                color: Color.lerp(AppColors.border, AppColors.accent, t),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        );
      },
    );
  }
}