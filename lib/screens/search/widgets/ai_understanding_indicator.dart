import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shown while `AiSearchService.parseQuery` is in flight.
///
/// Replaces the bare `LinearProgressIndicator` that stood here before. The point
/// is that this reads as a considered step rather than a generic fetch: parsing
/// a sentence into filters is the one moment in the flow where the app is doing
/// something the user cannot see, so it says what it is doing.
///
/// The redesign does not draw this state (the prototype only has the idle bar),
/// so it is composed from the app's established AI language: the same
/// `Icons.auto_awesome` sparkle the search screen already uses for AI, on a
/// `primaryLight` surface, with a slow pulse rather than a spinner.
class AiUnderstandingIndicator extends StatelessWidget {
  const AiUnderstandingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary)
              // Breathing, not spinning — deliberately unlike a progress
              // spinner, and slow enough not to nag.
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scaleXY(
                begin: 0.85,
                end: 1.15,
                duration: 700.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Understanding your search…',
              style: AppTextStyles.caption.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
