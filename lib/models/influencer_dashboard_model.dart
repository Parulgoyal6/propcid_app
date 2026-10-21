class InfluencerDashboardModel {
  final int totalVideos;
  final int activeCampaigns;
  final int totalViews;
  final double totalEarnings;

  const InfluencerDashboardModel({
    required this.totalVideos,
    required this.activeCampaigns,
    required this.totalViews,
    required this.totalEarnings,
  });

  factory InfluencerDashboardModel.empty() {
    return const InfluencerDashboardModel(
      totalVideos: 0,
      activeCampaigns: 0,
      totalViews: 0,
      totalEarnings: 0,
    );
  }
}
