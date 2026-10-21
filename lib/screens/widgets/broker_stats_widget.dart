import 'package:flutter/material.dart';

import '../../models/broker_dashboard_model.dart';
import '../../widgets/shared/stat_kpi_card.dart';

/// Broker overview metrics.
///
/// Re-skinned in Phase 3 to render the shared [MetricCard] so all four role
/// dashboards use one card language (blueprint §16.5). Every metric, label,
/// icon, accent colour and ordering is unchanged — only the container,
/// spacing and typography moved to the prototype's spec.
class BrokerStatsWidget extends StatelessWidget {
  final BrokerDashboardModel stats;

  const BrokerStatsWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return MetricCardGrid(
      cards: [
        MetricCard(
          label: "Listings",
          value: stats.totalListings.toString(),
          icon: Icons.home_work_rounded,
        ),
        MetricCard(
          label: "Active",
          value: stats.activeListings.toString(),
          icon: Icons.check_circle,
        ),
        MetricCard(
          label: "Views",
          value: stats.totalViews.toString(),
          icon: Icons.visibility,
        ),
        MetricCard(
          label: "Rating",
          value: stats.averageRating.toStringAsFixed(1),
          icon: Icons.star,
        ),
      ],
    );
  }
}
