import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerWidth = (constraints.maxWidth * 0.44)
            .clamp(118.0, 158.0)
            .toDouble();
        final sideWidth = centerWidth * 0.90;
        final cardHeight = centerWidth * 1.25;
        final sideOffset = centerWidth * 0.59;

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(-sideOffset, 4),
              child: Transform.rotate(
                angle: -0.10,
                child: _ScreenshotCard(
                  width: sideWidth,
                  height: cardHeight,
                  type: _CardType.ticket,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(sideOffset, 4),
              child: Transform.rotate(
                angle: 0.10,
                child: _ScreenshotCard(
                  width: sideWidth,
                  height: cardHeight,
                  type: _CardType.bill,
                ),
              ),
            ),
            _ScreenshotCard(
              width: centerWidth,
              height: cardHeight,
              type: _CardType.event,
            ),
          ],
        );
      },
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 7),
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
                color: const Color(0xFFEAE7F7),
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
  const _SkeletonLine({
    required this.width,
    this.light = false,
  });

  final double width;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: width,
      decoration: BoxDecoration(
        color: light ? const Color(0xFFF0EFEC) : const Color(0xFFEAE9E6),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
