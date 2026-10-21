class BrokerPropertyModel {
  final String id;
  final String title;
  final String location;
  final String image;
  final String status;
  final int views;
  final int likes;
  final double price;

  const BrokerPropertyModel({
    required this.id,
    required this.title,
    required this.location,
    required this.image,
    required this.status,
    required this.views,
    required this.likes,
    required this.price,
  });

  factory BrokerPropertyModel.fromSupabase(Map<String, dynamic> json) {
    final images = List<String>.from(json['media_urls'] ?? []);

    return BrokerPropertyModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      location: json['location'] ?? '',
      image: images.isNotEmpty ? images.first : '',
      status: json['status'] ?? '',
      views: json['views'] ?? 0,
      likes: json['likes'] ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}
