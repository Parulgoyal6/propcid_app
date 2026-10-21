import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/constants/app_constants.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.verifiedBadge,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 12, color: AppColors.verifiedBadgeText),
          const SizedBox(width: 4),
          Text(
            'Verified',
            style: AppTextStyles.chip.copyWith(
              color: AppColors.verifiedBadgeText,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
