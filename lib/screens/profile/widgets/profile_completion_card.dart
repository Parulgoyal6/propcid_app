import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/profile_completion.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../../../core/widgets/scale_tap.dart';

/// Profile-completion progress with a next-step hint (blueprint §4.1).
///
/// The percentage comes from [calculateProfileCompletion], a pure port of
/// React's `getCompletionItems()`, so the number matches the web app for the
/// same profile. Tapping opens the same edit-profile destination the Edit
/// button uses — mirroring React, where the widget is itself a button to
/// `/edit-profile`.
class ProfileCompletionCard extends StatelessWidget {
  final ProfileCompletion completion;
  final VoidCallback onTap;

  const ProfileCompletionCard({
    super.key,
    required this.completion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = completion.percentage;
    final next = completion.nextItem;

    return Semantics(
      label: 'Profile completion $percentage percent',
      button: true,
      child: ScaleTap(
        onTap: onTap,
        // Transparent, but still hit-tests its full bounds, so the whole card
        // (including padding) stays tappable.
        child: ColoredBox(
          color: Colors.transparent,
          child: FrostedGlass(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            borderRadius: 22,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.ctaGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.ctaShadow,
                  ),
                  child: const Icon(
                    Icons.person_pin_rounded,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Profile Completion',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '$percentage%',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _AnimatedProgressBar(value: percentage / 100),
                      const SizedBox(height: 7),
                      Text(
                        // Derived from the checklist rather than hardcoded,
                        // so the hint always names something that actually
                        // moves the bar.
                        next == null
                            ? 'Your profile is complete'
                            : 'Add ${next.label.toLowerCase()} to reach 100%',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient progress bar that eases from 0 to [value] the first time it's
/// shown, and animates smoothly whenever the percentage changes.
class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              ),
            ),
          ),
        );
      },
    );
  }
}
