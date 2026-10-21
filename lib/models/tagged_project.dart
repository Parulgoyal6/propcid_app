/// A builder project as needed for *tagging* a listing to it.
///
/// Mirrors React's `TaggedProject`
/// (propcid/src/features/property/ProjectTagSelector.tsx:9). Deliberately not
/// [BuilderProjectModel], which carries dashboard-only fields (views, likes,
/// available units) that the tag flow neither queries nor needs.
///
/// T5 covers the tag only — creating and managing projects, and the inventory
/// subsystem, are explicitly out of scope for this migration.
class TaggedProject {
  const TaggedProject({
    required this.id,
    required this.title,
    required this.location,
    this.projectType,
    this.status,
    this.possessionDate,
    this.priceRangeMin,
    this.priceRangeMax,
    this.logoUrl,
    this.mediaUrls = const [],
    this.otherImages = const [],
    required this.builderId,
    this.builderName,
  });

  final String id;
  final String title;
  final String location;
  final String? projectType;
  final String? status;
  final String? possessionDate;
  final double? priceRangeMin;
  final double? priceRangeMax;
  final String? logoUrl;
  final List<String> mediaUrls;
  final List<String> otherImages;
  final String builderId;

  /// Resolved from `profiles_public` in a second query — `builder_projects`
  /// has no FK to profiles, so React cannot embed it either.
  final String? builderName;

  /// The exact column list React selects, so the two stay in step.
  static const String columns =
      'id, title, location, project_type, status, possession_date, '
      'price_range_min, price_range_max, logo_url, media_urls, other_images, '
      'builder_id';

  static List<String> _stringList(Object? value) => value is List
      ? value.where((e) => e != null).map((e) => e.toString()).toList()
      : const <String>[];

  factory TaggedProject.fromSupabase(Map<String, dynamic> row) {
    return TaggedProject(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      location: row['location']?.toString() ?? '',
      projectType: row['project_type']?.toString(),
      status: row['status']?.toString(),
      possessionDate: row['possession_date']?.toString(),
      priceRangeMin: (row['price_range_min'] as num?)?.toDouble(),
      priceRangeMax: (row['price_range_max'] as num?)?.toDouble(),
      logoUrl: row['logo_url']?.toString(),
      mediaUrls: _stringList(row['media_urls']),
      otherImages: _stringList(row['other_images']),
      builderId: row['builder_id']?.toString() ?? '',
    );
  }

  TaggedProject copyWith({String? builderName}) => TaggedProject(
    id: id,
    title: title,
    location: location,
    projectType: projectType,
    status: status,
    possessionDate: possessionDate,
    priceRangeMin: priceRangeMin,
    priceRangeMax: priceRangeMax,
    logoUrl: logoUrl,
    mediaUrls: mediaUrls,
    otherImages: otherImages,
    builderId: builderId,
    builderName: builderName ?? this.builderName,
  );

  /// First available image, matching React's `projectThumbnail` fallback order.
  String? get thumbnail {
    if (mediaUrls.isNotEmpty) return mediaUrls.first;
    if (otherImages.isNotEmpty) return otherImages.first;
    return logoUrl;
  }
}
