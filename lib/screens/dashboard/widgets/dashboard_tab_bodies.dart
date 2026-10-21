import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/dashboard_analytics.dart';
import 'audience_insights_card.dart';
import 'cross_content_insights_section.dart';
import '../../../widgets/shared/app_chart_wrapper.dart';
import 'dashboard_primitives.dart';
import '../../../widgets/shared/stat_kpi_card.dart';
import 'top_content_list.dart';

/// `1240` → `1,240`, matching React's `toLocaleString()` and the design's
/// thousands separators. Deliberately not the Profile screen's `2.3K` style —
/// the dashboard design shows full numbers.
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }

  return '${value < 0 ? '-' : ''}$buffer';
}

/// Analytics tab body — six metric tiles, the performance chart and the
/// top-content list, in the design's order and spacing.
/// Indian-notation short currency, e.g. `₹1.2 Cr`, `₹45.0 L`, `₹9,500`.
///
/// Portfolio value and commission are whole-rupee figures large enough that a
/// full number would not fit a metric tile. Lakh/crore rather than K/M because
/// every price the app displays elsewhere uses that notation.
String formatCompactCurrency(double value) {
  if (value >= 10000000) return '₹${_trimZero(value / 10000000)} Cr';
  if (value >= 100000) return '₹${_trimZero(value / 100000)} L';
  return '₹${formatThousands(value.round())}';
}

/// `m:ss` above a minute, `Ns` below — how a watch time reads.
String formatDuration(double seconds) {
  final total = seconds.round();
  if (total < 60) return '${total}s';
  final minutes = total ~/ 60;
  final remainder = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}

/// One decimal place, with a trailing `.0` dropped.
String _trimZero(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

class DashboardAnalyticsBody extends StatelessWidget {
  final DashboardAnalytics analytics;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  /// Whether to show the "Saved Properties" tile.
  ///
  /// Only `IndividualAnalytics.tsx` queries `saved_properties`; the broker,
  /// builder and influencer variants never compute it, so the tile read a
  /// permanent 0 on three of the four dashboards. False renders five cards
  /// instead of six rather than showing a number that will never move.
  ///
  /// Defaults to true so the Individual dashboard — the one role that does
  /// compute it — needs no change, and so this stays additive.
  final bool showSavedProperties;

  const DashboardAnalyticsBody({
    super.key,
    required this.analytics,
    required this.loading,
    required this.failed,
    required this.onRetry,
    this.showSavedProperties = true,
  });

  @override
  Widget build(BuildContext context) {
    // Matches the card count below, so the shimmer does not reflow into a
    // different grid height once the real tiles arrive.
    if (loading) {
      return MetricCardGridShimmer(count: showSavedProperties ? 6 : 5);
    }

    if (failed) {
      return DashboardEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load analytics",
        message: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: onRetry,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricCardGrid(
          cards: [
            MetricCard(
              icon: Icons.visibility_outlined,
              value: formatThousands(analytics.totalViews),
              label: 'Total Views',
            ),
            MetricCard(
              icon: Icons.favorite_border,
              value: formatThousands(analytics.totalLikes),
              label: 'Total Likes',
            ),
            if (showSavedProperties)
              MetricCard(
                icon: Icons.bookmark_border_rounded,
                value: formatThousands(analytics.totalSaved),
                label: 'Saved Properties',
              ),
            MetricCard(
              icon: Icons.trending_up_rounded,
              // React's card renders two decimals; the design shows one.
              value: '${analytics.avgEngagement.toStringAsFixed(1)}%',
              label: 'Avg Engagement',
            ),
            MetricCard(
              icon: Icons.people_outline,
              value: formatThousands(analytics.totalInteractions),
              label: 'Total Interactions',
            ),
            MetricCard(
              icon: Icons.description_outlined,
              value: formatThousands(analytics.contentPosted),
              label: 'Content Posted',
            ),

            // Role-specific tiles, appended rather than interleaved so the six
            // shared ones keep their positions on every dashboard. Each is
            // null-gated: the metric is null for roles that do not compute it,
            // and a 0 would be indistinguishable from a real zero.

            // Broker — BrokerAnalytics.tsx:9-22.
            if (analytics.activeCount != null)
              MetricCard(
                icon: Icons.sell_outlined,
                value: formatThousands(analytics.activeCount!),
                label: 'Active Listings',
              ),
            if (analytics.soldCount != null)
              MetricCard(
                icon: Icons.task_alt_rounded,
                value: formatThousands(analytics.soldCount!),
                label: 'Sold',
              ),
            if (analytics.totalInquiries != null)
              MetricCard(
                icon: Icons.mark_email_unread_outlined,
                value: formatThousands(analytics.totalInquiries!),
                label: 'Inquiries',
              ),
            if (analytics.totalValue != null)
              MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                value: formatCompactCurrency(analytics.totalValue!),
                label: 'Portfolio Value',
              ),
            if (analytics.totalCommission != null)
              MetricCard(
                icon: Icons.percent_rounded,
                value: formatCompactCurrency(analytics.totalCommission!),
                // The rate is part of the label because it is an assumption, not
                // a measurement — the portal hard-codes 2%.
                label:
                    'Commission '
                    '(${_trimZero(analytics.commissionRate ?? 0)}%)',
              ),

            // Influencer — InfluencerAnalytics.tsx:15-16.
            if (analytics.avgWatchTime != null)
              MetricCard(
                icon: Icons.timer_outlined,
                value: formatDuration(analytics.avgWatchTime!),
                label: 'Avg Watch Time',
              ),
            if (analytics.avgCompletionRate != null)
              MetricCard(
                icon: Icons.donut_large_rounded,
                value: '${analytics.avgCompletionRate!.toStringAsFixed(1)}%',
                label: 'Avg Completion',
              ),
          ],
        ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardCardTitle('Performance Over Time'),
              const SizedBox(height: AppConstants.spacingM),
              DashboardLineChart(
                points: analytics.performance,
                height: 120,
                showDayLabels: true,
                emptyMessage: 'No performance data yet',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const DashboardSectionLabel('Top Performing Content'),
        const SizedBox(height: 10),
        if (analytics.topContent.isEmpty)
          DashboardCard(
            child: DashboardEmptyState(
              icon: Icons.insights_outlined,
              title: 'No content yet',
              message: 'Start posting to see which content performs best.',
            ),
          )
        else
          TopContentList(items: analytics.topContent),
      ],
    );
  }
}

/// Audience tab body — four metric tiles, the follower-growth chart and the
/// insights list.
class DashboardAudienceBody extends StatelessWidget {
  final DashboardAudience audience;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  /// The cross-content section's own independent loading/failure state
  /// (`DashboardAnalyticsProvider.crossContentLoading`/`.crossContentFailed`)
  /// — false unless the caller opted into
  /// `DashboardAnalyticsProvider.includeCrossContentInsights`, so every
  /// existing caller (broker/builder/individual dashboards) renders exactly
  /// as before with no change to this widget's default behaviour.
  final bool crossContentLoading;
  final bool crossContentFailed;
  final VoidCallback? onCrossContentRetry;

  /// Routes a "Most Liked Content" tap to that item's own detail screen.
  /// Null hides the tap affordance entirely rather than doing nothing on tap.
  final ValueChanged<CrossContentItem>? onContentTap;

  const DashboardAudienceBody({
    super.key,
    required this.audience,
    required this.loading,
    required this.failed,
    required this.onRetry,
    this.crossContentLoading = false,
    this.crossContentFailed = false,
    this.onCrossContentRetry,
    this.onContentTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const MetricCardGridShimmer(count: 4);

    if (failed) {
      return DashboardEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load audience data",
        message: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: onRetry,
      );
    }

    final growth = audience.followersGrowth;
    final growthLabel =
        '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricCardGrid(
          cards: [
            MetricCard(
              icon: Icons.people_outline,
              value: formatThousands(audience.totalFollowers),
              label: 'Total Followers',
            ),
            MetricCard(
              icon: Icons.visibility_outlined,
              value: formatThousands(audience.totalViews),
              label: 'Total Views',
            ),
            MetricCard(
              icon: Icons.grid_view_rounded,
              value: formatThousands(audience.avgViewsPerPost.round()),
              label: 'Avg Views/Post',
            ),
            MetricCard(
              icon: Icons.percent_rounded,
              value: '${audience.engagementRate.toStringAsFixed(1)}%',
              label: 'Engagement Rate',
            ),
          ],
        ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardCardTitle('Follower Growth'),
              const SizedBox(height: AppConstants.spacingM),
              DashboardLineChart(
                points: audience.followerGrowth,
                height: 100,
                // The prototype fills this one with the lighter accent.
                areaColor: Color(0xFFFDBA74),
                emptyMessage: 'No follower data yet',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const DashboardSectionLabel('Audience Insights'),
        const SizedBox(height: 10),
        AudienceInsightsCard(
          rows: [
            AudienceInsightRow(
              icon: Icons.trending_up_rounded,
              label: 'Avg Engagement',
              value: '${audience.engagementRate.toStringAsFixed(1)}%',
            ),
            AudienceInsightRow(
              icon: Icons.people_outline,
              label: 'Follower Growth',
              value: growthLabel,
            ),
            AudienceInsightRow(
              icon: Icons.visibility_outlined,
              label: 'Total Reach',
              value: formatThousands(audience.totalViews),
            ),
            AudienceInsightRow(
              icon: Icons.person_outline,
              label: 'Audience Size',
              value: formatThousands(audience.totalFollowers),
            ),

            // Broker only — BrokerAudienceInsights.tsx:9-18. Null for every other
            // role, so the card simply has four rows there instead of seven.
            if (audience.totalLeads != null)
              AudienceInsightRow(
                icon: Icons.inbox_outlined,
                label: 'Total Leads',
                value: formatThousands(audience.totalLeads!),
              ),
            if (audience.leadConversionRate != null)
              AudienceInsightRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Lead Conversion',
                value: '${audience.leadConversionRate!.toStringAsFixed(1)}%',
              ),
            if (audience.responseRate != null)
              AudienceInsightRow(
                icon: Icons.reply_rounded,
                label: 'Response Rate',
                value: '${audience.responseRate!.toStringAsFixed(1)}%',
              ),
          ],
        ),
        // Influencer only — see `crossContentLoading`'s own doc comment for
        // why every other role's dashboard reaches none of these branches.
        if (crossContentLoading ||
            crossContentFailed ||
            audience.crossContent != null) ...[
          const SizedBox(height: 22),
          const DashboardSectionLabel('Reach Across All Content'),
          const SizedBox(height: 10),
          _CrossContentSection(
            loading: crossContentLoading,
            failed: crossContentFailed,
            onRetry: onCrossContentRetry,
            insights: audience.crossContent,
            onContentTap: onContentTap,
          ),
        ],
      ],
    );
  }
}

/// The cross-content block's own loading/error/empty/data states — kept
/// separate from the rest of [DashboardAudienceBody] so a failure here never
/// blanks the follower/views/engagement metrics above it.
class _CrossContentSection extends StatelessWidget {
  const _CrossContentSection({
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.insights,
    required this.onContentTap,
  });

  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;
  final CrossContentInsights? insights;
  final ValueChanged<CrossContentItem>? onContentTap;

  @override
  Widget build(BuildContext context) {
    if (loading) return const MetricCardGridShimmer(count: 3);

    if (failed) {
      return DashboardCard(
        child: DashboardEmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load this section",
          message: 'Check your connection and try again.',
          actionLabel: onRetry == null ? null : 'Retry',
          onAction: onRetry,
        ),
      );
    }

    final data = insights;
    if (data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricCardGrid(
          cards: [
            // Labelled "(All Content)" rather than bare "Total Reach" —
            // the Audience Insights card above already has a "Total Reach"
            // row for the single-source `audience.totalViews`; these three
            // are the cross-content sums instead and must read as distinct
            // numbers, not a duplicate of that row.
            MetricCard(
              icon: Icons.visibility_outlined,
              value: formatThousands(data.totalViews),
              label: 'Reach (All Content)',
            ),
            MetricCard(
              icon: Icons.favorite_border,
              value: formatThousands(data.totalLikes),
              label: 'Likes (All Content)',
            ),
            MetricCard(
              icon: Icons.mode_comment_outlined,
              value: formatThousands(data.totalComments),
              label: 'Comments (All Content)',
            ),
          ],
        ),
        if (data.breakdown.isNotEmpty) ...[
          const SizedBox(height: 18),
          const DashboardCardTitle('Content Breakdown'),
          const SizedBox(height: 10),
          ContentBreakdownList(items: data.breakdown),
        ],
        const SizedBox(height: 22),
        const DashboardSectionLabel('Most Liked Content'),
        const SizedBox(height: 10),
        if (data.topContent.isEmpty)
          DashboardCard(
            child: DashboardEmptyState(
              icon: Icons.insights_outlined,
              title: 'No content yet',
              message: 'Start posting to see which content performs best.',
            ),
          )
        else
          MostLikedContentList(items: data.topContent, onTap: onContentTap),
      ],
    );
  }
}

/// Content Manager tab body — the design's "Content Library" header over each
/// role's own content sections.
///
/// [sections] receives the role's existing, working widgets (Quick Actions,
/// Recent Properties/Projects/Campaigns, My Listings) unchanged, so no
/// functionality is lost; only the surrounding presentation is the design's.
/// When a role has nothing to show, [isEmpty] swaps in the design's empty state.
class DashboardContentBody extends StatelessWidget {
  final VoidCallback? onCreate;
  final String createLabel;
  final bool isEmpty;
  final String emptyTitle;
  final String emptyMessage;
  final String emptyActionLabel;
  final List<Widget> sections;

  const DashboardContentBody({
    super.key,
    required this.onCreate,
    required this.sections,
    this.createLabel = 'Create Post',
    this.isEmpty = false,
    this.emptyTitle = 'No posts yet',
    this.emptyMessage = 'Start creating content to build your presence',
    this.emptyActionLabel = 'Create Your First Post',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentLibraryHeader(actionLabel: createLabel, onAction: onCreate),
        if (isEmpty) ...[
          // Prototype puts 44 dp between the header row and the empty state.
          const SizedBox(height: 44),
          // Full width so the centred empty state is not left-aligned by the
          // surrounding start-aligned Column.
          SizedBox(
            width: double.infinity,
            child: DashboardEmptyState(
              icon: Icons.description_outlined,
              title: emptyTitle,
              message: emptyMessage,
              actionLabel: emptyActionLabel,
              onAction: onCreate,
            ),
          ),
        ] else ...[
          const SizedBox(height: 18),
          ...sections,
        ],
      ],
    );
  }
}
