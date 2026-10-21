import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../widgets/search_bar_widget.dart';

/// Welcome heading + the premium search bar. Same two navigations as before
/// (tap the bar → Search; tap the mic → Search with `autoStartVoice: true`) —
/// only the visual treatment changes.
class PremiumSearchSection extends StatelessWidget {
  const PremiumSearchSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          // Scales down rather than overflowing on narrow phones.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Find your perfect ',
                  style: AppTextStyles.heading1.copyWith(
                    fontSize: 23,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const GradientText(
                  text: 'property',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const Text(' 🏡', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SearchBarWidget(
            hint: 'Search properties, locations...',
            glass: true,
            height: 54,
            borderRadius: 22,
            onTap: () =>
                Navigator.pushNamed(context, AppConstants.searchScreen),
            trailing: GestureDetector(
              onTap: () => Navigator.pushNamed(
                context,
                AppConstants.searchScreen,
                arguments: {'autoStartVoice': true},
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppColors.ctaShadow,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
