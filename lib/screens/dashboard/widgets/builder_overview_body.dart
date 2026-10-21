// screens/dashboard/widgets/builder_overview_body.dart
//
// The Builder dashboard's Overview tab — the mobile adaptation of
// `BuilderDashboardManage.tsx`'s `activeSection === 'overview'`.
//
// PRESENTATION ONLY, AND EVERY NUMBER IS ALREADY LOADED
// ----------------------------------------------------
// This widget issues no queries. The portal's Overview shows five stat cards and six
// cards of charts; each figure below comes from something an existing provider or
// service already fetched for this screen:
//
//   Total Projects / Active   → BuilderDashboardModel      (BuilderDashboardService)
//   Total Views               → DashboardAnalytics         (Spec C, builder_projects)
//   Inventory / Sold          → InventoryCounts            (Spec H, project_inventory)
//   Site Visits               → SiteVisitBooking count     (Spec H)
//   Project Performance chart → DashboardAnalytics.performance
//   Top Performing Projects   → DashboardAnalytics.topContent
//
// A sixth stat card, Average Rating (`BuilderDashboardModel.customerRating`),
// and a third Performance Overview row, Customer rating, were both removed to
// match the portal — the backing `builder_ratings` table, and the portal's
// own corresponding UI, were both dropped entirely
// (20270916080000_drop_builder_ratings_and_testimonials.sql).
//
// So the parent passes what it already has. Nothing here adds a round trip, and
// `BuilderDashboardService`, `DashboardAnalyticsService`, `ProjectInventoryService`
// and `SiteVisitService` are all untouched.
//
// WHAT IS ADAPTED RATHER THAN COPIED
// ----------------------------------
//   * five stat cards → a 2-up `MetricCardGrid`, the app's existing tile;
//   * the pie → a donut with the total in the middle, so the number the portal hides
//     in a tooltip is readable without a tap;
//   * the vertical bar chart → horizontal bars, because four vertical columns in
//     320 dp cannot label their own axis;
//   * the desktop two-column grid → one column of collapsible cards;
//   * "Recent Activity" is NOT rendered — see the note at the bottom of this file.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_dashboard_model.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/dashboard_analytics.dart';
import '../../../widgets/shared/app_chart_wrapper.dart';
import '../../../widgets/shared/app_mini_charts.dart';
import '../../../widgets/shared/app_surface_card.dart';
import '../../../widgets/shared/stat_kpi_card.dart';
import 'dashboard_primitives.dart';
// `formatThousands` — reused rather than re-implemented.
import 'dashboard_tab_bodies.dart';

class BuilderOverviewBody extends StatelessWidget {
  const BuilderOverviewBody({
    super.key,
    required this.stats,
    required this.analytics,
    required this.analyticsLoading,
    required this.analyticsFailed,
    required this.onRetryAnalytics,
    required this.unitCounts,
    required this.siteVisitCount,
    required this.onOpenInventory,
    required this.onOpenProject,
  });

  /// From `BuilderDashboardService`, already fetched by the screen's FutureBuilder.
  final BuilderDashboardModel stats;

  /// From `DashboardAnalyticsProvider`, sourced from `builder_projects` since C-2.
  final DashboardAnalytics analytics;
  final bool analyticsLoading;
  final bool analyticsFailed;
  final VoidCallback onRetryAnalytics;

  /// From `ProjectInventoryService.countsByProject`, already loaded by the screen.
  final Map<String, InventoryCounts> unitCounts;

  /// Number of `project_visit_bookings` rows the Site Visits section reported.
  final int siteVisitCount;

  /// Jumps to the Inventory tab — the portal's own affordance from this card.
  final VoidCallback onOpenInventory;

  final ValueChanged<String> onOpenProject;

  // ── Folds over data already in hand ──────────────────────────────────────

  int get _totalUnits =>
      unitCounts.values.fold<int>(0, (sum, c) => sum + c.total);

  int get _soldUnits =>
      unitCounts.values.fold<int>(0, (sum, c) => sum + c.sold);

  int get _availableUnits =>
      unitCounts.values.fold<int>(0, (sum, c) => sum + c.available);

  /// `project_inventory`'s CHECK allows `booked` and `blocked` too, and the portal's
  /// fold counts neither — so this is `total - sold - available`, and showing it is
  /// what stops the donut's slices failing to add up to its centre number.
  int get _otherUnits => _totalUnits - _soldUnits - _availableUnits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Five stat cards (portal `:790-845`) ────────────────────────────
        //
        // A sixth, "Average Rating", was removed here to match the portal:
        // the backing `builder_ratings` table was dropped entirely
        // (20270916080000_drop_builder_ratings_and_testimonials.sql, "the
        // Ratings & Testimonials builder feature was removed entirely ...
        // the Average Rating dashboard stat"), and the portal's own
        // dashboard has no such card any more either.
        if (analyticsLoading)
          const MetricCardGridShimmer(count: 5)
        else
          MetricCardGrid(
            cards: [
              MetricCard(
                icon: Icons.apartment_rounded,
                value: formatThousands(stats.totalProjects),
                label: 'Total Projects',
              ),
              MetricCard(
                icon: Icons.play_circle_outline_rounded,
                value: formatThousands(stats.activeProjects),
                label: 'Active Projects',
              ),
              MetricCard(
                icon: Icons.visibility_outlined,
                value: formatThousands(analytics.totalViews),
                label: 'Total Views',
              ),
              MetricCard(
                icon: Icons.event_available_outlined,
                value: formatThousands(siteVisitCount),
                label: 'Site Visits',
              ),
              MetricCard(
                icon: Icons.inventory_2_outlined,
                value: formatThousands(_totalUnits),
                label: 'Inventory',
              ),
            ],
          ),
        const SizedBox(height: 18),

        // ── Project Performance (portal `:879-920`, a line chart) ──────────
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardCardTitle('Project Performance'),
              const SizedBox(height: AppConstants.spacingM),
              if (analyticsFailed)
                _InlineRetry(onRetry: onRetryAnalytics)
              else
                DashboardLineChartHost(
                  points: analytics.performance,
                  loading: analyticsLoading,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),

        // ── Inventory Overview (portal `:930-1010`, a pie) ─────────────────
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: DashboardCardTitle('Inventory Overview'),
                  ),
                  // The portal's card is static; on mobile it doubles as the way
                  // into the Inventory tab, which saves a trip back to the pill.
                  if (_totalUnits > 0)
                    TextButton(
                      onPressed: onOpenInventory,
                      child: const Text('Manage'),
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingS),
              DashboardDonutChart(
                centerLabel: formatThousands(_totalUnits),
                emptyMessage: 'No inventory units added yet',
                slices: [
                  if (_availableUnits > 0)
                    DonutSlice(
                      label: 'Available',
                      value: _availableUnits.toDouble(),
                      color: AppColors.success,
                    ),
                  if (_soldUnits > 0)
                    DonutSlice(
                      label: 'Sold',
                      value: _soldUnits.toDouble(),
                      color: AppColors.primary,
                    ),
                  // Booked and blocked, which the portal's two counters drop.
                  if (_otherUnits > 0)
                    DonutSlice(
                      label: 'Booked / held',
                      value: _otherUnits.toDouble(),
                      color: AppColors.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),

        // ── Performance Overview (portal `:1080-1145`, three progress bars) ─
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardCardTitle('Performance Overview'),
              const SizedBox(height: AppConstants.spacingS),
              DashboardProgressRow(
                label: 'Active projects',
                value: stats.totalProjects == 0
                    ? 0
                    : stats.activeProjects / stats.totalProjects,
                caption:
                    '${stats.activeProjects} of ${stats.totalProjects} '
                    'projects active',
              ),
              DashboardProgressRow(
                label: 'Units sold',
                value: _totalUnits == 0 ? 0 : _soldUnits / _totalUnits,
                caption: _totalUnits == 0
                    // The portal renders "0 of 0 units sold", which reads as a
                    // failure rather than an absence.
                    ? 'No inventory units added yet'
                    : '$_soldUnits of $_totalUnits units sold',
                tint: AppColors.success,
              ),
              // A third row, "Customer rating", was removed here to match the
              // portal (`BuilderDashboardManage.tsx`'s own Performance
              // Overview card now has only these two rows) — same removal as
              // the Average Rating stat card above, and for the same reason.
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),

        // ── Top Performing Projects (portal `:1158-1195`) ──────────────────
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardCardTitle('Top Performing Projects'),
              const SizedBox(height: AppConstants.spacingS),
              if (analytics.topContent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Publish a project to see how it performs.',
                    style: AppTextStyles.caption,
                  ),
                )
              else
                for (final item in analytics.topContent)
                  _TopProjectRow(
                    item: item,
                    onTap: () => onOpenProject(item.id),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),

        // ── Team Overview (portal `:1205-1225`) ───────────────────────────
        //
        // A count and a way in, not a member list: the Team tab already renders
        // every member with their modules and scope, and repeating it here would be
        // the same rows twice in one scroll.
        DashboardCard(
          child: Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DashboardCardTitle('Team'),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.networkMembers} '
                      '${stats.networkMembers == 1 ? 'connection' : 'connections'} '
                      'in your network',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps the app's existing line chart with a loading state.
///
/// Extracted so the Overview and Analytics tabs render the same chart the same way.
class DashboardLineChartHost extends StatelessWidget {
  const DashboardLineChartHost({
    super.key,
    required this.points,
    required this.loading,
  });

  final List<ChartPoint> points;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return DashboardLineChart(
      points: points,
      height: 120,
      showDayLabels: true,
      emptyMessage: 'No performance data yet',
    );
  }
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text("Couldn't load performance", style: AppTextStyles.caption),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TopProjectRow extends StatelessWidget {
  const _TopProjectRow({required this.item, required this.onTap});

  final TopContentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 12,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${item.views}',
                        style: AppTextStyles.caption.copyWith(fontSize: 11),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.favorite_outline_rounded,
                        size: 12,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${item.likes}',
                        style: AppTextStyles.caption.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Why the Site Visits CHART is absent (the stat card is not) ─────────────
//
// The portal charts site visits per week (`:1123-1160`) from its own four-week
// aggregate (`:581-600`). On this side the bookings are owned by
// `BuilderSiteVisitsSection`, which reports only a count upward — so there is no
// per-day series here to plot, and producing one would mean a second read of
// `project_visit_bookings`, which this phase forbids.
//
// A first draft of this file had the card with a `_visitBars()` that returned an
// empty list unconditionally: a chart that could never draw anything. The total is
// shown as a stat card instead, which is true, and the chart is reported as a gap.
//
// ── Why "Recent Activity" is absent ─────────────────────────────────────────
//
// The portal's Overview has a Recent Activity card (`:1041-1078`) fed by three
// separate reads inside `BuilderDashboardManage.tsx` — recent projects, recent
// ratings and recent site visits (`:487-500`). None of those three are exposed by
// any existing Flutter service, so rendering the card would mean either new queries
// (which this phase forbids) or inventing rows.
//
// The Network hub's own Recent Activity card states the same absence in the same
// way rather than faking a feed, so this omission is consistent with what the app
// already does. Reported as a parity gap.
