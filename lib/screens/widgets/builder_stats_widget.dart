import 'package:flutter/material.dart';
import '../../models/builder_dashboard_model.dart';
import '../../widgets/shared/stat_kpi_card.dart';

/// Builder overview metrics.
///
/// Re-skinned in Phase 3 to render the shared [MetricCard] (blueprint §16.5).
/// All six metrics keep their existing values, labels, icons, accent colours
/// and ordering; only the layout changed — from a single-column stack to the
/// prototype's two-column grid, matching the other three roles.
class BuilderStatsWidget extends StatelessWidget {
  final BuilderDashboardModel stats;

  const BuilderStatsWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return MetricCardGrid(
      cards: [
        MetricCard(
          label: 'Total Projects',
          value: stats.totalProjects.toString(),
          icon: Icons.business_rounded,
        ),
        MetricCard(
          label: 'Active Projects',
          value: stats.activeProjects.toString(),
          icon: Icons.trending_up_rounded,
        ),
        MetricCard(
          label: 'Delivered',
          value: stats.deliveredProjects.toString(),
          icon: Icons.check_circle_rounded,
        ),
        MetricCard(
          label: 'Network Members',
          value: stats.networkMembers.toString(),
          icon: Icons.people_alt_rounded,
        ),
        MetricCard(
          label: 'Customer Rating',
          value: stats.customerRating.toStringAsFixed(1),
          icon: Icons.star_rounded,
        ),
        MetricCard(
          label: 'Broker Rating',
          value: stats.brokerRating.toStringAsFixed(1),
          icon: Icons.workspace_premium_rounded,
        ),
      ],
    );
  }
}
