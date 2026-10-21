class BuilderProjectModel {
  final String id;
  final String title;
  final String location;
  final String status;
  final String image;
  final int views;
  final int likes;
  final int availableUnits;
  final double minPrice;
  final double maxPrice;

  const BuilderProjectModel({
    required this.id,
    required this.title,
    required this.location,
    required this.status,
    required this.image,
    required this.views,
    required this.likes,
    required this.availableUnits,
    required this.minPrice,
    required this.maxPrice,
  });

  factory BuilderProjectModel.fromSupabase(Map<String, dynamic> json) {
    final images = List<String>.from(json['media_urls'] ?? []);

    return BuilderProjectModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      location: json['location'] ?? '',
      status: json['status'] ?? '',
      image: images.isNotEmpty ? images.first : '',
      views: json['views'] ?? 0,
      likes: json['likes'] ?? 0,
      availableUnits: json['available_units'] ?? 0,
      minPrice: (json['price_range_min'] as num?)?.toDouble() ?? 0,
      maxPrice: (json['price_range_max'] as num?)?.toDouble() ?? 0,
    );
  }
}
