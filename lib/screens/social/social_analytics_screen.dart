import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/social_models.dart';
import '../../providers/social_provider.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/stat_kpi_card.dart';
import '../shared/section_loader.dart';
import 'widgets/social_screen_shell.dart';

/// Social ▸ Analytics — the design's `isSocialAnalytics` screen.
///
/// Six KPIs over "Posts by platform" and "Most shared", derived from the
/// caller's own publish records exactly as `analyticsService.getAnalytics`
/// does. Live Meta Insights (reach, CTR, engagement) are a later phase on both
/// platforms — React's own file says so — so nothing here claims them.
class SocialAnalyticsScreen extends StatelessWidget {
  const SocialAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialAnalyticsSection(),
      child: const _AnalyticsView(),
    );
  }
}

class _AnalyticsView extends StatefulWidget {
  const _AnalyticsView();

  @override
  State<_AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<_AnalyticsView>
    with DeferredSectionLoader<_AnalyticsView> {
  @override
  void loadSection(String userId) =>
      context.read<SocialAnalyticsSection>().loadFor(userId);

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialAnalyticsSection>();

    return SocialAnalyticsBody(
      analytics: section.value,
      loading: section.loading,
      failed: section.failed,
    );
  }
}

class SocialAnalyticsBody extends StatelessWidget {
  final SocialAnalytics analytics;
  final bool loading;
  final bool failed;

  const SocialAnalyticsBody({
    super.key,
    required this.analytics,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    // An em dash rather than a zero when the query failed, so "no data" is
    // never mistaken for "you have published nothing".
    String count(int value) => failed ? '—' : '$value';

    return SocialScreenShell(
      title: 'Analytics',
      subtitle: 'Publishing performance',
      children: [
        const SizedBox(height: 18),
        if (loading)
          const MetricCardGridShimmer(count: 6)
        else
          MetricCardGrid(
            cards: [
              MetricCard(
                icon: Icons.refresh,
                value: count(analytics.totalShares),
                label: 'Total published',
              ),
              MetricCard(
                icon: Icons.trending_up_rounded,
                value: count(analytics.today),
                label: 'Today',
              ),
              MetricCard(
                icon: Icons.schedule,
                value: count(analytics.week),
                label: 'This week',
              ),
              MetricCard(
                icon: Icons.grid_view_rounded,
                value: count(analytics.month),
                label: 'This month',
              ),
              MetricCard(
                icon: Icons.hourglass_empty,
                value: count(analytics.pending),
                label: 'Pending',
                accent: AppColors.warning,
              ),
              MetricCard(
                icon: Icons.error_outline,
                value: count(analytics.failed),
                label: 'Failed',
                accent: AppColors.error,
              ),
            ],
          ),
        const SizedBox(height: 14),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SocialCardTitle('Posts by platform'),
              const SizedBox(height: 14),
              if (failed)
                const _CentredNote("Couldn't load platform data.")
              else if (!analytics.hasPublished)
                const _CentredNote('No published posts yet.')
              else ...[
                _PlatformRow(
                  icon: Icons.facebook,
                  label: 'Facebook',
                  count: analytics.facebook,
                  total: analytics.totalShares,
                ),
                const SizedBox(height: 10),
                _PlatformRow(
                  icon: Icons.camera_alt_outlined,
                  label: 'Instagram',
                  count: analytics.instagram,
                  total: analytics.totalShares,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SocialCardTitle('Most shared'),
              const SizedBox(height: 14),
              if (failed)
                const _CentredNote("Couldn't load shared content.")
              else if (analytics.topContent.isEmpty)
                const _CentredNote('Nothing yet.')
              else
                for (var i = 0; i < analytics.topContent.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _TopContentRow(entry: analytics.topContent[i]),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CentredNote extends StatelessWidget {
  final String text;

  const _CentredNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12.5),
        ),
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final int total;

  const _PlatformRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(fontSize: 12.5),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.hairlineStrong,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: AppTextStyles.body.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TopContentRow extends StatelessWidget {
  final TopSharedContent entry;

  const _TopContentRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            entry.contentType.isEmpty ? 'Content' : entry.contentType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(fontSize: 12.5),
          ),
        ),
        const SizedBox(width: AppConstants.spacingS),
        Text(
          '${entry.count}',
          style: AppTextStyles.body.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
