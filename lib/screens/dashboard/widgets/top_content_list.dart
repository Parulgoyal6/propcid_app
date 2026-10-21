import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_analytics.dart';

/// "Top Performing Content" rows.
///
/// Prototype spec per row: white card, 16 dp radius,
/// `0 2px 10px rgba(26,26,46,0.05)`, 12 dp padding, 12 dp gap; a 52 dp
/// 12 dp-radius placeholder thumbnail; title 13.5 dp semi-bold, ellipsised;
/// then a 5 dp-below stats row with 12 dp gaps — 14 dp eye and heart icons in
/// `#6B7280` beside 11.5 dp counts. Rows are 10 dp apart.
class TopContentList extends StatelessWidget {
  final List<TopContentItem> items;

  const TopContentList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _TopContentRow(item: items[i]),
        ],
      ],
    );
  }
}

class _TopContentRow extends StatelessWidget {
  final TopContentItem item;

  const _TopContentRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${item.title}, ${item.views} views, ${item.likes} likes',
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingM),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.surfaceCardShadow,
        ),
        child: Row(
          children: [
            // The design shows a neutral placeholder block, not a photo — the
            // React analytics queries select no image column.
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE7E6EE),
                borderRadius: BorderRadius.circular(
                  AppConstants.imageThumbnailRadius,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _Stat(icon: Icons.visibility_outlined, value: item.views),
                      const SizedBox(width: AppConstants.spacingM),
                      _Stat(icon: Icons.favorite_border, value: item.likes),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;

  const _Stat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text('$value', style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}
