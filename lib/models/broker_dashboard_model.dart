class BrokerDashboardModel {
  final int totalListings;
  final int activeListings;
  final int totalViews;
  final double averageRating;

  const BrokerDashboardModel({
    required this.totalListings,
    required this.activeListings,
    required this.totalViews,
    required this.averageRating,
  });

  factory BrokerDashboardModel.empty() {
    return const BrokerDashboardModel(
      totalListings: 0,
      activeListings: 0,
      totalViews: 0,
      averageRating: 0,
    );
  }
}
