import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/premium_button.dart';

/// CTA buttons: "View Details" (secondary, light) + "Contact Builder"
/// (primary). Purely presentational: both callbacks are supplied by
/// [ReelsScreen] and wired to real navigation / contact logic — no
/// property or builder data is hardcoded here.
class ReelCtaButtons extends StatelessWidget {
  const ReelCtaButtons({
    super.key,
    required this.onViewDetails,
    required this.onContactBuilder,
    this.axis = Axis.horizontal,
  });

  final VoidCallback onViewDetails;
  final VoidCallback onContactBuilder;

  /// `Axis.horizontal` (original) places the two buttons side by side,
  /// full width, reusing the app's [PremiumButton] as-is. `Axis.vertical`
  /// stacks them in a narrow right-hand column next to the title/price/
  /// actions (the compact video~80%/card~20% layout) — that column is
  /// narrow enough that [PremiumButton]'s own `Text` (no ellipsis/Flexible
  /// wrapping built in) would overflow, so the vertical variant builds a
  /// smaller button locally instead, reusing the same
  /// [AppColors.primaryGradient] so it still looks identical in style.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton(
              onPressed: onViewDetails,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'View Details',
                      style: AppTextStyles.chip.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                  onTap: onContactBuilder,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.call_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Contact Builder',
                          style: AppTextStyles.chip.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: onViewDetails,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                ),
              ),
              child: Text(
                'View Details',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PremiumButton(
            label: 'Contact Builder',
            icon: Icons.call_rounded,
            height: 50,
            onPressed: onContactBuilder,
          ),
        ),
      ],
    );
  }
}
