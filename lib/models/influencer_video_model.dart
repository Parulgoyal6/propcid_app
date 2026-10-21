// models/influencer_video_model.dart
//
// One `influencer_videos` row, in full.
//
// WHY THIS EXISTS ALONGSIDE InfluencerCampaignModel
// -------------------------------------------------
// `InfluencerCampaignModel` carries 8 of this table's 16 columns — enough for the
// dashboard's read-only "Recent Videos" strip, which is all it was built for. It
// has no `video_type`, `hashtags`, `approval_status`, `created_at` or `user_id`,
// and `video_type` is NOT NULL with a CHECK constraint, so an editor cannot round
// -trip a row through it without losing data. Widening it would change what every
// existing reader receives; this is a new type instead, and
// `InfluencerCampaignModel` is left exactly as it is.
//
// THE COLUMN LIST
// ---------------
// 20250828001551_a8c692e2…sql:7-22, plus three later additions:
//   * approval_status  text, DEFAULT 'pending'   — 20251213104811
//   * deleted_at       timestamptz              — 20270318040000 (soft delete)
//   * translations                              — 20260630000000, not read here
//
// NOT NULL is only on `title`, `video_url` and `video_type`. `user_id`'s NOT NULL
// was deliberately DROPPED by 20270318030000:144 so a user delete can null it
// instead of cascading, which is why `userId` is nullable below.

/// One influencer video, as stored.
class InfluencerVideoModel {
  const InfluencerVideoModel({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.videoType,
    this.userId,
    this.description = '',
    this.thumbnailUrl,
    this.propertyId,
    this.views = 0,
    this.likes = 0,
    this.hashtags = const [],
    this.status = 'active',
    this.approvalStatus = 'pending',
    this.createdAt,
    this.deletedAt,
    this.propertyLocation,
    this.propertyPrice,
    this.propertyListingType,
    this.propertyCategory,
    this.propertyBedrooms,
    this.propertyBathrooms,
    this.propertyArea,
  });

  final String id;

  /// Nullable by schema: see the note above about 20270318030000.
  final String? userId;

  final String title;

  /// `''` rather than null when the column is NULL, so callers can print it
  /// without a guard. The column is nullable; the form always sends a string.
  final String description;

  final String videoUrl;
  final String? thumbnailUrl;

  /// One of `property_listing`, `property_news`, `property_education`.
  final String videoType;

  /// Optional link to a listing, for `property_listing` videos. The portal's modal
  /// never sets it — it is populated by other flows — so an edit here must leave it
  /// alone rather than write null over it.
  final String? propertyId;

  final int views;
  final int likes;
  final List<String> hashtags;

  /// `active` | `inactive` | `pending`, per the column CHECK.
  final String status;

  /// `pending` | `approved` | `rejected`. Not CHECK-constrained, and NULL on rows
  /// predating 20251213104811 — normalised to `pending` here, which is the same
  /// fallback the portal's badge applies.
  final String approvalStatus;

  final DateTime? createdAt;

  /// Set by `soft_delete_content`. A RESTRICTIVE RLS policy hides such rows from
  /// every client read, so in practice this is always null on a fetched row; it is
  /// modelled so nothing silently drops it.
  final DateTime? deletedAt;

  // ── Property Listing Video fields ──────────────────────────────────────
  //
  // 20270916020000/20270916030000 — only meaningful when
  // `videoType == 'property_listing'`; forced to null server-side for every
  // other type (`influencer-video-save`'s `buildPropertyFields`), so a null
  // here always means "not a listing video" or "listing video with that
  // field left blank", never a decoding failure.

  /// TEXT, ≤200 chars.
  final String? propertyLocation;

  /// TEXT — a whole-rupee number as a string, matching the column's own
  /// type. Never parsed to a number here; formatting is a display concern.
  final String? propertyPrice;

  /// One of `sale` | `rent` | `lease`, or null.
  final String? propertyListingType;

  /// One of `residential` | `commercial` | `pg/Co-living` | `land` | `others`,
  /// or null. Note the exact casing/slash — it is the DB CHECK constraint's
  /// own spelling, not a display label.
  final String? propertyCategory;

  /// 0–20, or null (optional even for a listing video).
  final int? propertyBedrooms;
  final int? propertyBathrooms;

  /// TEXT — sq.ft as a string, same reasoning as [propertyPrice].
  final String? propertyArea;

  /// The exact column list this model reads.
  ///
  /// Spelled out rather than `select()` so a future column cannot start arriving
  /// unnoticed, and so the read cost is fixed. `translations` is omitted
  /// deliberately: it is a large JSONB the app has no reader for.
  static const String columns =
      'id, user_id, title, description, video_url, thumbnail_url, video_type, '
      'property_id, views, likes, hashtags, status, approval_status, '
      'created_at, deleted_at, property_location, property_price, '
      'property_listing_type, property_category, property_bedrooms, '
      'property_bathrooms, property_area';

  factory InfluencerVideoModel.fromSupabase(Map<String, dynamic> json) {
    return InfluencerVideoModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      thumbnailUrl: _nullIfEmpty(json['thumbnail_url']),
      videoType: json['video_type']?.toString() ?? '',
      propertyId: _nullIfEmpty(json['property_id']),
      views: _int(json['views']),
      likes: _int(json['likes']),
      hashtags: _stringList(json['hashtags']),
      status: json['status']?.toString() ?? 'active',
      approvalStatus: json['approval_status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
      deletedAt: _date(json['deleted_at']),
      propertyLocation: _nullIfEmpty(json['property_location']),
      propertyPrice: _nullIfEmpty(json['property_price']),
      propertyListingType: _nullIfEmpty(json['property_listing_type']),
      propertyCategory: _nullIfEmpty(json['property_category']),
      propertyBedrooms: _intOrNull(json['property_bedrooms']),
      propertyBathrooms: _intOrNull(json['property_bathrooms']),
      propertyArea: _nullIfEmpty(json['property_area']),
    );
  }

  InfluencerVideoModel copyWith({
    String? title,
    String? description,
    String? videoUrl,
    String? thumbnailUrl,
    String? videoType,
    List<String>? hashtags,
    String? status,
    String? approvalStatus,
  }) {
    return InfluencerVideoModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoType: videoType ?? this.videoType,
      propertyId: propertyId,
      views: views,
      likes: likes,
      hashtags: hashtags ?? this.hashtags,
      status: status ?? this.status,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      createdAt: createdAt,
      deletedAt: deletedAt,
      propertyLocation: propertyLocation,
      propertyPrice: propertyPrice,
      propertyListingType: propertyListingType,
      propertyCategory: propertyCategory,
      propertyBedrooms: propertyBedrooms,
      propertyBathrooms: propertyBathrooms,
      propertyArea: propertyArea,
    );
  }

  /// True while the row is waiting on a reviewer.
  ///
  /// The public read policy requires `approval_status = 'approved'`, so anything
  /// else means the video is invisible to everyone but its owner.
  bool get isAwaitingReview => approvalStatus != 'approved';

  // ── Coercion ────────────────────────────────────────────────────────────

  /// Treats `''` as absent.
  ///
  /// `thumbnail_url` and `property_id` are both nullable, but rows written by
  /// older code paths hold empty strings in them, and an empty string passed to
  /// `Image.network` throws where a null renders the placeholder.
  static String? _nullIfEmpty(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };

  static int? _intOrNull(Object? value) => switch (value) {
    null => null,
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
