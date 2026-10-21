// screens/dashboard/widgets/cross_content_insights_section.dart
//
// The Audience tab's cross-content additions: Content Breakdown and Most
// Liked Content. For influencer, spans reels + properties + articles via the
// `influencer-audience-insights` edge function; for builder, spans projects
// (its only content type) via `builder-audience-insights`
// (`DashboardAnalyticsService.fetchCrossContentInsights`).
//
// Deliberately separate widgets from `TopContentList`/`AudienceInsightsCard`:
// those are single-source (no `type`, no `comments`, no tap target), and a
// reel id or article id here must never be treated as a property id when
// routing a tap — see `InfluencerDashboardScreen._openCrossContentItem` /
// `BuilderDashboardScreen._openCrossContentItem`.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_analytics.dart';
import '../../../widgets/shared/app_surface_card.dart';
import 'dashboard_tab_bodies.dart' show formatThousands;

String _typeLabel(CrossContentType type) => switch (type) {
  CrossContentType.reel => 'Reel',
  CrossContentType.property => 'Property',
  CrossContentType.article => 'Article',
  CrossContentType.project => 'Project',
};

IconData _typeIcon(CrossContentType type) => switch (type) {
  CrossContentType.reel => Icons.play_circle_outline_rounded,
  CrossContentType.property => Icons.home_outlined,
  CrossContentType.article => Icons.article_outlined,
  CrossContentType.project => Icons.apartment_outlined,
};

/// "Content Breakdown" — one row per content type present, each with its own
/// count/views/likes/comments. A type this influencer has never posted is
/// simply absent from [items] (the edge function only emits an entry for a
/// type it actually saw a row for), not shown as a zeroed row.
class ContentBreakdownList extends StatelessWidget {
  const ContentBreakdownList({super.key, required this.items});

  final List<ContentBreakdownItem> items;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(AppConstants.spacingXS),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.hairline),
            _BreakdownRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.item});

  final ContentBreakdownItem item;

  @override
  Widget build(BuildContext context) {
    final label = _typeLabel(item.type);
    return Semantics(
      label:
          '$label: ${item.count} posts, ${item.views} views, '
          '${item.likes} likes, ${item.comments} comments',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppConstants.spacingM,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _typeIcon(item.type),
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${item.count} ${item.count == 1 ? 'post' : 'posts'}',
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: AppConstants.spacingM,
              runSpacing: 4,
              children: [
                _MiniStat(icon: Icons.visibility_outlined, value: item.views),
                _MiniStat(icon: Icons.favorite_border, value: item.likes),
                _MiniStat(
                  icon: Icons.mode_comment_outlined,
                  value: item.comments,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          formatThousands(value),
          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// "Most Liked Content" — ranked 1-5 across all content types, tappable.
class MostLikedContentList extends StatelessWidget {
  const MostLikedContentList({super.key, required this.items, this.onTap});

  final List<CrossContentItem> items;
  final ValueChanged<CrossContentItem>? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _MostLikedRow(rank: i + 1, item: items[i], onTap: onTap),
        ],
      ],
    );
  }
}

class _MostLikedRow extends StatelessWidget {
  const _MostLikedRow({required this.rank, required this.item, this.onTap});

  final int rank;
  final CrossContentItem item;
  final ValueChanged<CrossContentItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final label = _typeLabel(item.type);

    return Semantics(
      label:
          '#$rank, $label, ${item.title}, ${item.views} views, '
          '${item.likes} likes, ${item.comments} comments',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          onTap: onTap == null ? null : () => onTap!(item),
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              boxShadow: AppColors.surfaceCardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$rank',
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _typeIcon(item.type),
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
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
                          _MiniStat(
                            icon: Icons.visibility_outlined,
                            value: item.views,
                          ),
                          const SizedBox(width: AppConstants.spacingM),
                          _MiniStat(
                            icon: Icons.favorite_border,
                            value: item.likes,
                          ),
                          const SizedBox(width: AppConstants.spacingM),
                          _MiniStat(
                            icon: Icons.mode_comment_outlined,
                            value: item.comments,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
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
