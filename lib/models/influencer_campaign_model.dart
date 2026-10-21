class InfluencerCampaignModel {
  final String id;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final int views;
  final int likes;
  final String status;

  const InfluencerCampaignModel({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.views,
    required this.likes,
    required this.status,
  });

  factory InfluencerCampaignModel.fromSupabase(Map<String, dynamic> json) {
    return InfluencerCampaignModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['video_url'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      views: json['views'] ?? 0,
      likes: json['likes'] ?? 0,
      status: json['status'] ?? '',
    );
  }
}
