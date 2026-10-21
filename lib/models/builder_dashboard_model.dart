class BuilderDashboardModel {
  final int totalProjects;
  final int activeProjects;
  final int deliveredProjects;
  final int networkMembers;
  final double customerRating;
  final double brokerRating;

  const BuilderDashboardModel({
    required this.totalProjects,
    required this.activeProjects,
    required this.deliveredProjects,
    required this.networkMembers,
    required this.customerRating,
    required this.brokerRating,
  });

  factory BuilderDashboardModel.empty() {
    return const BuilderDashboardModel(
      totalProjects: 0,
      activeProjects: 0,
      deliveredProjects: 0,
      networkMembers: 0,
      customerRating: 0,
      brokerRating: 0,
    );
  }
}
