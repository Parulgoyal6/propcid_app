import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import '../../models/network_analytics.dart';
import '../../providers/network_analytics_provider.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/stat_kpi_card.dart';
import '../messaging/widgets/chat_avatar.dart';
import '../shared/section_loader.dart';
import 'widgets/network_screen_shell.dart';

/// Network ▸ Analytics — builder-only, matching the portal's
/// `features/analytics/NetworkAnalyticsDashboard.tsx`.
///
/// The portal gates the tab itself on `profile?.user_type === 'builder'`
/// (both the nav trigger and the `<TabsContent>` block); this app reaches
/// the equivalent screen only via the Network hub's own builder-only nav
/// card (see `network_hub_screen.dart`), so nothing here re-checks the role
/// — same convention the other four Network leaf screens already follow.
///
/// Four sub-tabs, matching the portal exactly: Overview (a real, live
/// Network Health card plus a genuinely-static "Performance Summary"
/// placeholder — the portal's own card has no query behind it either),
/// Performance (a real leaderboard from `network_performance`), Trends and
/// Insights (both unconditional "Coming Soon" placeholders on the portal —
/// copied verbatim rather than invented).
class NetworkAnalyticsScreen extends StatelessWidget {
  const NetworkAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkAnalyticsProvider(),
      child: const _NetworkAnalyticsView(),
    );
  }
}

class _NetworkAnalyticsView extends StatefulWidget {
  const _NetworkAnalyticsView();

  @override
  State<_NetworkAnalyticsView> createState() => _NetworkAnalyticsViewState();
}

class _NetworkAnalyticsViewState extends State<_NetworkAnalyticsView>
    with DeferredSectionLoader<_NetworkAnalyticsView> {
  @override
  void loadSection(String userId) =>
      context.read<NetworkAnalyticsProvider>().load(userId);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NetworkAnalyticsProvider>();

    return NetworkAnalyticsBody(
      stats: provider.stats,
      performance: provider.performance,
      loading: provider.loading,
      failed: provider.failed,
    );
  }
}

class NetworkAnalyticsBody extends StatefulWidget {
  final NetworkAnalyticsStats stats;
  final List<NetworkPerformanceEntry> performance;
  final bool loading;
  final bool failed;

  const NetworkAnalyticsBody({
    super.key,
    required this.stats,
    required this.performance,
    required this.loading,
    required this.failed,
  });

  @override
  State<NetworkAnalyticsBody> createState() => _NetworkAnalyticsBodyState();
}

class _NetworkAnalyticsBodyState extends State<NetworkAnalyticsBody> {
  int _tab = 0;

  static const List<String> _tabs = [
    'Overview',
    'Performance',
    'Trends',
    'Insights',
  ];

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;

    return NetworkScreenShell(
      title: 'Network Analytics',
      subtitle: "Insights into your network's performance and growth",
      children: [
        const SizedBox(height: 18),
        NetworkIntroBanner(
          title: 'Network Analytics',
          description:
              "Comprehensive insights into your network's performance "
              'and growth',
          trailing: _ActiveMembersBadge(
            count: widget.loading || widget.failed ? null : stats.activeMembers,
          ),
        ),
        const SizedBox(height: AppConstants.spacingL),
        if (widget.loading)
          const MetricCardGridShimmer(count: 4)
        else if (widget.failed)
          const EmptyStateView(
            icon: Icons.error_outline,
            title: "Couldn't load analytics",
            message: 'Try again in a moment.',
            iconCircleSize: 52,
          )
        else
          _buildKpiGrid(stats),
        const SizedBox(height: AppConstants.spacingL),
        SegmentedTabPill(
          labels: _tabs,
          selectedIndex: _tab,
          onChanged: (index) => setState(() => _tab = index),
          labelFontSize: 11.5,
          itemVerticalPadding: 9,
        ),
        const SizedBox(height: AppConstants.spacingL),
        _buildTab(),
      ],
    );
  }

  Widget _buildKpiGrid(NetworkAnalyticsStats stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _AnalyticsMetricCard(
                icon: Icons.groups_2_outlined,
                label: 'Total Members',
                value: '${stats.totalMembers}',
                sublabel: '${stats.activeMembers} active',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AnalyticsMetricCard(
                icon: Icons.track_changes,
                label: 'Leads Distributed',
                value: '${stats.totalLeadsDistributed}',
                sublabel: '${stats.convertedLeads} converted',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _AnalyticsMetricCard(
                icon: Icons.trending_up_rounded,
                label: 'Conversion Rate',
                value: stats.conversionRateDisplay,
                sublabel: 'Network average',
                iconColor: AppColors.success,
                iconBackground: const Color(0xFFDCFCE7),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AnalyticsMetricCard(
                icon: Icons.currency_rupee,
                label: 'Commissions Paid',
                value: stats.commissionsPaidDisplay,
                sublabel: '${stats.totalReferrals} referrals',
                iconColor: const Color(0xFFF59E0B),
                iconBackground: const Color(0xFFFEF3C7),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 1:
        return _PerformanceTab(entries: widget.performance);
      case 2:
        return const _StaticPlaceholderCard(
          icon: Icons.show_chart_rounded,
          title: 'Performance Trends',
          placeholderTitle: 'Trend Analysis Coming Soon',
          message:
              'Historical performance trends and predictive analytics '
              'will be available here.',
        );
      case 3:
        return const _StaticPlaceholderCard(
          icon: Icons.pie_chart_outline_rounded,
          title: 'Network Insights',
          placeholderTitle: 'AI-Powered Insights',
          message:
              'Smart recommendations and insights to optimize your '
              'network performance will appear here.',
        );
      default:
        return _OverviewTab(stats: widget.stats);
    }
  }
}

/// The header banner's top-right pill — "N ACTIVE MEMBERS". Null while
/// loading/failed, matching the design's own em-dash convention elsewhere.
class _ActiveMembersBadge extends StatelessWidget {
  final int? count;

  const _ActiveMembersBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_alt_outlined,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count == null ? '—' : '$count',
                style: AppTextStyles.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'ACTIVE MEMBERS',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One KPI tile: label + tinted icon on top, a large value, and a muted
/// sub-label — the design's Analytics grid, distinct in layout from the
/// shared [MetricCard] (icon-on-top, no sub-label) used elsewhere in this
/// app, so this stays a screen-local widget rather than changing that
/// shared one.
class _AnalyticsMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sublabel;
  final Color iconColor;
  final Color iconBackground;

  const _AnalyticsMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sublabel,
    this.iconColor = AppColors.primary,
    this.iconBackground = AppColors.primaryLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.heading2.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final NetworkAnalyticsStats stats;

  const _OverviewTab({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetworkTitledCard(
          icon: Icons.favorite_border_rounded,
          title: 'Network Health',
          child: Padding(
            padding: const EdgeInsets.only(top: AppConstants.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressStat(
                  label: 'Active Members',
                  percent: stats.activeMemberRate,
                  color: AppColors.error,
                ),
                const SizedBox(height: AppConstants.spacingL),
                _ProgressStat(
                  label: 'Lead Conversion',
                  percent: stats.averageConversionRate,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppConstants.spacingL),
                const Divider(height: 1, color: AppColors.hairline),
                const SizedBox(height: AppConstants.spacingM),
                Row(
                  children: [
                    Expanded(
                      child: _CountColumn(
                        value: '${stats.totalReferrals}',
                        label: 'Total Referrals',
                        color: AppColors.error,
                      ),
                    ),
                    Expanded(
                      child: _CountColumn(
                        value: '${stats.totalLeadsDistributed}',
                        label: 'Leads Distributed',
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingL),
        // Genuinely static on the portal too — see this file's own header.
        DashboardCard(
          child: EmptyStateView(
            icon: Icons.bar_chart_rounded,
            title: 'Performance Dashboard',
            message:
                'Detailed performance metrics and trends will be '
                'displayed here as your network grows.',
            iconCircleSize: 56,
          ),
        ),
      ],
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String label;
  final double percent;
  final Color color;

  const _ProgressStat({
    required this.label,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${clamped.round()}%',
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 7,
            backgroundColor: AppColors.background,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _CountColumn extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _CountColumn({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.heading2.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}

class _PerformanceTab extends StatelessWidget {
  final List<NetworkPerformanceEntry> entries;

  const _PerformanceTab({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const DashboardCard(
        child: EmptyStateView(
          icon: Icons.emoji_events_outlined,
          title: 'No Performance Data',
          message:
              'Performance metrics will appear here as your network '
              'members engage with leads and referrals.',
          iconCircleSize: 56,
        ),
      );
    }

    return NetworkTitledCard(
      icon: Icons.emoji_events_outlined,
      title: 'Performance Leaderboard',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            SizedBox(height: i == 0 ? AppConstants.spacingL : 10),
            _PerformanceRow(rank: i + 1, entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  final int rank;
  final NetworkPerformanceEntry entry;

  const _PerformanceRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ChatAvatar(
                avatarUrl: entry.avatarUrl,
                initials: entry.initial,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.resolvedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      entry.roleLabel,
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              NetworkStatusPill(
                entry.performanceScore.toStringAsFixed(0),
                positive: entry.performanceScore >= 50,
              ),
            ],
          ),
          const SizedBox(height: 8),
          NetworkDetailRow(
            label: 'Leads received / converted',
            value: '${entry.leadsReceived} / ${entry.leadsConverted}',
          ),
          NetworkDetailRow(
            label: 'Conversion rate',
            value: entry.conversionRateDisplay,
          ),
          NetworkDetailRow(
            label: 'Commission earned',
            value: entry.commissionEarnedDisplay,
          ),
        ],
      ),
    );
  }
}

class _StaticPlaceholderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String placeholderTitle;
  final String message;

  const _StaticPlaceholderCard({
    required this.icon,
    required this.title,
    required this.placeholderTitle,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return NetworkTitledCard(
      icon: icon,
      title: title,
      child: EmptyStateView(
        icon: icon,
        title: placeholderTitle,
        message: message,
        iconCircleSize: 56,
      ),
    );
  }
}
