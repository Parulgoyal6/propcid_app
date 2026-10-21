import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// White surface card used for the chart and insight blocks.
///
/// Prototype spec: `#FFFFFF`, 16 dp radius,
/// `0 2px 10px rgba(26,26,46,0.05)`, 16 dp padding.
class DashboardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppConstants.spacingL),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: child,
    );
  }
}

/// Title inside a [DashboardCard] — 13.5 dp semi-bold.
class DashboardCardTitle extends StatelessWidget {
  final String text;

  const DashboardCardTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Uppercase muted section label — 11.5 dp semi-bold `#9CA3AF`, 0.6 tracking.
///
/// Replaces the old gradient-chip `_sectionTitle`, which the design does not
/// use anywhere.
class DashboardSectionLabel extends StatelessWidget {
  final String text;

  const DashboardSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textHint,
        letterSpacing: 0.6,
      ),
    );
  }
}
