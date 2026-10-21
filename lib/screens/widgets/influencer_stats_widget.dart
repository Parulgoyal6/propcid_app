import 'package:flutter/material.dart';

import '../../models/influencer_dashboard_model.dart';
import '../../widgets/shared/stat_kpi_card.dart';

/// Influencer overview metrics.
///
/// Re-skinned in Phase 3 to render the shared [MetricCard] (blueprint §16.5).
/// Metrics, labels, icons, accent colours and ordering are unchanged —
/// including the rupee-formatted earnings value.
class InfluencerStatsWidget extends StatelessWidget {
  final InfluencerDashboardModel stats;

  const InfluencerStatsWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return MetricCardGrid(
      cards: [
        MetricCard(
          label: "Videos",
          value: stats.totalVideos.toString(),
          icon: Icons.video_library_rounded,
        ),
        MetricCard(
          label: "Campaigns",
          value: stats.activeCampaigns.toString(),
          icon: Icons.campaign_rounded,
        ),
        MetricCard(
          label: "Views",
          value: stats.totalViews.toString(),
          icon: Icons.visibility_rounded,
        ),
        MetricCard(
          label: "Earnings",
          value: "₹${stats.totalEarnings.toStringAsFixed(0)}",
          icon: Icons.payments_rounded,
        ),
      ],
    );
  }
}
