import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One "Audience Insights" row: icon + label on the left, value on the right.
class AudienceInsightRow {
  final IconData icon;
  final String label;
  final String value;

  const AudienceInsightRow({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// The Audience tab's insights block.
///
/// Prototype spec: a single white card, 16 dp radius,
/// `0 2px 10px rgba(26,26,46,0.05)`, 4 dp outer padding; each row 12 dp
/// vertical / 14 dp horizontal, a 20 dp `#6B7280` icon, 10 dp gap, a 13 dp
/// medium label, and a right-aligned 13 dp bold value.
///
/// One shared card rather than separate tiles — the rows sit flush together
/// with no dividers, as in the design.
class AudienceInsightsCard extends StatelessWidget {
  final List<AudienceInsightRow> rows;

  const AudienceInsightsCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingXS),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        children: [
          for (final row in rows)
            Semantics(
              label: '${row.label} ${row.value}',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: AppConstants.spacingM,
                ),
                child: Row(
                  children: [
                    Icon(row.icon, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Text(
                      row.value,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
