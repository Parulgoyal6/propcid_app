import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/premium_launch_banner.dart';

/// Thin wrapper around the existing `PremiumLaunchBanner` (PropCID Pro
/// upsell) so it composes uniformly alongside the other Home sections at its
/// new position in the scroll order — the banner itself (content, gradient,
/// shimmer, `/payment-method` navigation) is untouched.
///
/// Adds a short gradient-bleed lead-in/out in the banner's own brand tones so
/// the saturated card fades into the page instead of sitting as a hard-edged
/// rectangle dropped on top of it.
class PremiumBannerSection extends StatelessWidget {
  const PremiumBannerSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 18,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background,
                AppColors.primaryLight.withOpacity(0.6),
              ],
            ),
          ),
        ),
        const PremiumLaunchBanner(),
        Container(
          height: 18,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primaryLight.withOpacity(0.6),
                AppColors.background,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
