import '../core/utils/profile_link.dart';
import '../screens/post_property/listing_constants.dart' show kAreaUnitLabels;
import 'amenity_model.dart';
import 'property_model.dart';

/// Reel model backed by the `influencer_videos` Supabase table.
///
/// ── What's real vs. derived ──────────────────────────────────────────────
/// Columns that actually exist on `influencer_videos` (see
/// `src/integrations/supabase/types.ts` in the website repo, which is the
/// generated source of truth for the schema):
///   id, user_id, title, description, video_url, thumbnail_url, video_type,
///   views, likes, hashtags, status, approval_status, property_id,
///   created_at, updated_at.
///
/// Everything else the premium reels UI shows (builder name/avatar/phone/
/// verified, price, location, beds/baths/parking, area, possession status,
/// featured flag, amenities) is **not** a column on this table. It's
/// resolved the same way the website's own `InfluencerVideoFeed.tsx` does
/// it: builder identity comes from a separate `profiles` lookup keyed by
/// `user_id`, and — when a reel has a non-null `property_id` — property
/// specs come from `properties` (+ its `properties_residential` /
/// `properties_commercial` subtype rows, the same shape
/// [PropertyModel.fromSupabase] already parses).
///
/// [ReelsService.getReels] does both lookups and merges the results onto
/// each video row under `_profile` / `_property` before this factory ever
/// sees it, so this file stays a pure "shape the JSON" concern.
class ReelModel {
  final String id;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final String videoType;
  final int views;
  final int likes;

  /// Real column — free-form hashtags the uploader attached to the reel
  /// (e.g. "#luxury", "#readytomove"). Shown as-is; not property amenities.
  final List<String> hashtags;

  // ── Builder identity — resolved from a joined `profiles` row ─────────
  final String? builderName;
  final String? builderAvatarUrl;
  final String? builderPhone;
  final bool isVerified;

  /// `influencer_videos.user_id` — the uploader's own id, not the joined
  /// `profiles` row. Kept separate from the identity fields above (which all
  /// come from that joined row) because it's needed to navigate to the
  /// uploader's public profile even when their profile fields are thin.
  final String? builderUserId;

  // ── Linked property (only present when property_id is set) ──────────
  final String? propertyId;

  /// First photo of the linked property, from `properties.media_urls`.
  ///
  /// Only a fallback cover for [previewImageUrl] — the reel itself is the
  /// video. `thumbnail_url` is optional at upload (the influencer form leaves
  /// it null when no cover is picked), so without this a reel card has no
  /// image to show at all even though the property it advertises has photos.
  ///
  /// Costs nothing to read: `ReelsService.getReels` already selects `*` from
  /// `properties`, so `media_urls` was being fetched and then dropped here.
  final String? propertyImageUrl;

  final String? price;
  final String? location;
  final int? beds;
  final int? baths;
  final int? parking;
  final int? sqft;
  // Additive, decimal-accurate counterpart to [sqft] — which stays an
  // `int` (rounded) so no existing caller/constructor breaks. [sqft] was
  // previously also populated via `int.tryParse`, which returns null
  // outright for a decimal string ("1200.5"), silently dropping the area
  // for both a linked property with a decimal area AND a manually-entered
  // one (the manual Reel form's own "Area" field explicitly allows
  // decimals — influencer_video_form_screen.dart's `_propertyArea`).
  final double? areaValue;
  // Raw unit id (e.g. 'acres') for a LINKED property only — null for a
  // manually-entered listing, which has no unit picker anywhere in the
  // Reel upload form and is always sq.ft by convention (see that form's
  // "Optional, in sq.ft." helper text). Resolved to a human label by the
  // [areaUnit] getter below; kept separate from manual entries per the
  // same precedence this factory already uses for every other field.
  final String? _linkedAreaUnit;
  final String? possessionStatus;
  final bool isFeatured;
  final List<AmenityModel> amenities;

  /// Only set for a manually-entered Property Listing Video (see
  /// [ReelModel.fromSupabase]'s `hasManualListing` branch) — a linked
  /// property has no equivalent single "category"/"listing type" badge in
  /// this model, matching the portal's own `hasManualListing ? ... : null`.
  final String? category;
  final String? listingType;

  /// `influencer_videos.comments` — a real denormalized counter column
  /// (confirmed against the live schema), read by `ReelsService.getReels`'s
  /// `select('*')`. Comments themselves are backed by `post_comments` with
  /// `post_type = 'video'`, mirroring the website's ReelView.tsx
  /// (`postType={reel.type === 'influencer_video' ? 'video' : 'property'}`).
  final int commentCount;

  /// `profiles.comments_enabled` for the uploader — gates the comment input
  /// the same way the website's `reel.profiles?.comments_enabled ?? true`
  /// does. Defaults to true when the profile row/column is absent.
  final bool commentsEnabled;

  /// True for a reel built from a listing's own video (a `properties` row
  /// whose `media_urls` holds a video — the portal's "Property Video"
  /// upload), not an `influencer_videos` row. Mirrors the portal's
  /// `type: "property_video"` (reels-feed-list): for these, [id] and
  /// [propertyId] are both the property id, and likes/saves/comments belong
  /// to the property (`user_likes.property_id`, `saved_properties`,
  /// `post_type = 'property'`), never the reel tables.
  final bool isPropertyVideo;

  const ReelModel({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    this.thumbnailUrl = '',
    this.videoType = 'property_listing',
    this.views = 0,
    this.likes = 0,
    this.hashtags = const [],
    this.builderName,
    this.builderAvatarUrl,
    this.builderPhone,
    this.builderUserId,
    this.isVerified = false,
    this.propertyId,
    this.propertyImageUrl,
    this.price,
    this.location,
    this.beds,
    this.baths,
    this.parking,
    this.sqft,
    this.areaValue,
    String? linkedAreaUnit,
    this.possessionStatus,
    this.isFeatured = false,
    this.amenities = const [],
    this.category,
    this.listingType,
    this.commentCount = 0,
    this.commentsEnabled = true,
    this.isPropertyVideo = false,
  }) : _linkedAreaUnit = linkedAreaUnit;

  factory ReelModel.fromSupabase(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile =
        json['_profile'] as Map<String, dynamic>?;
    final Map<String, dynamic>? property =
        json['_property'] as Map<String, dynamic>?;
    final Map<String, dynamic>? residential =
        property?['properties_residential'] as Map<String, dynamic>?;
    final Map<String, dynamic>? commercial =
        property?['properties_commercial'] as Map<String, dynamic>?;
    final Map<String, dynamic> metadata =
        (property?['metadata'] as Map<String, dynamic>?) ?? const {};

    // A manually-entered Property Listing Video's own property_* columns —
    // set directly on `influencer_videos` by `influencer-video-save` —
    // take precedence over a linked `properties` row, mirroring the
    // portal's own `hasManualListing` precedence in `reels-feed-list`
    // (`toInfluencerVideoItems`). `ReelsService.getReels` selects `*` on
    // `influencer_videos`, so these columns are already present in [json]
    // even though nothing here read them before this feature.
    final String? manualLocation = _str(json['property_location']);
    final bool hasManualListing =
        json['video_type'] == 'property_listing' && manualLocation != null;

    int? beds;
    int? baths;
    int? parking;
    if (residential != null) {
      beds = (residential['bedrooms'] as num?)?.toInt();
      baths = (residential['bathrooms'] as num?)?.toInt();
      parking = (residential['parking_spaces'] as num?)?.toInt();
    } else if (commercial != null) {
      baths = (commercial['washrooms'] as num?)?.toInt();
      parking = (commercial['parking_spaces'] as num?)?.toInt();
    }
    // Manual listing values win outright — there is no join to fall back
    // into partially, matching the portal's ternary (never a merge of both
    // sources). No manual equivalent of `parking` exists on
    // `influencer_videos`, so it stays whatever the (absent, for a manual
    // listing) property join produced — i.e. null.
    if (hasManualListing) {
      beds = (json['property_bedrooms'] as num?)?.toInt();
      baths = (json['property_bathrooms'] as num?)?.toInt();
    }

    // Same heuristic PropertyModel.fromSupabase uses — there's no dedicated
    // `is_featured` column on `properties` either.
    final int propertyViews = (property?['views'] as num?)?.toInt() ?? 0;

    return ReelModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['video_url'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      videoType: json['video_type'] ?? 'property_listing',
      views: (json['views'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      hashtags:
          (json['hashtags'] as List<dynamic>?)?.cast<String>() ?? const [],
      builderName:
          _str(profile?['display_name']) ?? _str(profile?['company_name']),
      builderAvatarUrl:
          _str(profile?['avatar_url']) ?? _str(profile?['company_logo_url']),
      builderPhone: _str(profile?['phone']),
      builderUserId: _str(json['user_id']),
      isVerified: profile?['verification_status'] == 'verified',
      propertyId: _str(json['property_id']),
      // Same parse `PropertyModel.fromSupabase` runs on the same column.
      propertyImageUrl: PropertyModel.parseMediaUrls(
        property?['media_urls'],
      ).firstOrNull,
      price: hasManualListing
          ? _str(json['property_price'])
          : _str(property?['price']),
      location: hasManualListing ? manualLocation : _str(property?['location']),
      beds: beds,
      baths: baths,
      parking: parking,
      sqft: hasManualListing
          ? double.tryParse(json['property_area']?.toString() ?? '')?.round()
          : double.tryParse(property?['area']?.toString() ?? '')?.round(),
      areaValue: hasManualListing
          ? double.tryParse(json['property_area']?.toString() ?? '')
          : double.tryParse(property?['area']?.toString() ?? ''),
      linkedAreaUnit: hasManualListing
          ? null
          : property?['area_unit']?.toString(),
      possessionStatus: _str(metadata['propertyCondition']),
      isFeatured: propertyViews >= 1,
      amenities: PropertyModel.parseAmenities(property?['amenities']),
      // A manual listing carries its own values; a linked property supplies
      // them from its own `category` / `property_type` columns (the reel feed
      // already returns both), so every property reel can show its tags.
      category: hasManualListing
          ? _str(json['property_category'])
          : _str(property?['category']),
      listingType: hasManualListing
          ? _str(json['property_listing_type'])
          : _str(property?['property_type']),
      commentCount: (json['comments'] as num?)?.toInt() ?? 0,
      commentsEnabled: profile?['comments_enabled'] as bool? ?? true,
      // Set by `ReelsService` on rows it built from a listing video.
      isPropertyVideo: json['_type'] == 'property_video',
    );
  }

  /// The still image to show for this reel before/instead of playing it.
  ///
  /// The uploader's own cover wins; the linked property's first photo is the
  /// fallback. Empty when there is neither, which callers must check — an
  /// empty string handed to `CachedNetworkImage` never resolves and never
  /// reaches `errorWidget`, it just sits on the placeholder. `ReelVideoView`
  /// already guards this way; the home rail now does too.
  String get previewImageUrl {
    if (thumbnailUrl.trim().isNotEmpty) return thumbnailUrl;
    return propertyImageUrl ?? '';
  }

  bool get hasPrice => price != null && price!.trim().isNotEmpty;
  bool get hasLocation => location != null && location!.trim().isNotEmpty;
  bool get hasBuilder => builderName != null && builderName!.trim().isNotEmpty;
  bool get hasPossessionStatus =>
      possessionStatus != null && possessionStatus!.trim().isNotEmpty;
  bool get hasSpecs =>
      beds != null || baths != null || parking != null || sqft != null;

  // ── Compatibility aliases for reel_property_card.dart ────────────────
  // That widget was written against an earlier draft of this model that
  // used different names for the same data (status/areaLabel/bedrooms/
  // etc.). Rather than rename the real fields above (which would ripple
  // into reel_action_row.dart, reels_screen.dart, and the service/provider
  // wiring), these getters just expose the same values under the names
  // the widget already expects. Purely additive — nothing above changed.

  /// Alias for [possessionStatus].
  String? get status => possessionStatus;

  /// Alias for [hasPossessionStatus].
  bool get hasStatus => hasPossessionStatus;

  /// Alias for [beds].
  int? get bedrooms => beds;

  /// Alias for [baths].
  int? get bathrooms => baths;

  /// Alias for [parking].
  int? get parkingSpots => parking;

  /// Decimal-accurate label for the card's area text — was `sqft?.toString()`
  /// (the rounded int), which lost precision for any non-whole area.
  String? get areaLabel {
    final value = areaValue ?? sqft?.toDouble();
    if (value == null) return null;
    if (value == value.roundToDouble()) return value.toInt().toString();
    final fixed = value.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// Unit label to pair with [areaLabel]. A manually-entered listing has no
  /// per-reel unit anywhere in the schema (always sq.ft by the upload
  /// form's own convention), so [_linkedAreaUnit] is null and this falls
  /// back to that fixed default — unchanged from before. A reel linked to a
  /// property now shows that property's real unit (e.g. "Acres" for Land)
  /// instead of always claiming "Sq.ft" regardless of what was actually
  /// saved.
  String get areaUnit => switch (_linkedAreaUnit) {
    null => 'Sq.ft',
    final u when kAreaUnitLabels.containsKey(u) => kAreaUnitLabels[u]!,
    final u => u,
  };

  /// Property highlights as plain labels for the card's highlight chips —
  /// derived from [amenities] (already parsed from the real `properties`
  /// data via [PropertyModel.parseAmenities]), not a separate data source.
  List<String> get highlights => amenities.map((a) => a.name).toList();

  /// Where a shared reel should open, mirroring `ReelView.handleShare`
  /// (`ReelView.tsx:577-590`), which always links to this reel's own
  /// `/property-reels/:id/:slug` page (`reelPath` in `seoSlug.ts`) regardless
  /// of whether it's backed by a property — that route pins the feed to this
  /// exact reel (`ReelView`'s `pathReelId`), not just the generic feed.
  String get shareUrl => reelShareUrl(id, title: title);

  /// Best-effort share message built from whatever property data exists.
  /// Falls back to the title + a generic call-to-action when metadata is thin.
  ///
  /// Ends with [shareUrl]. `Share.share` takes one text blob where the web uses
  /// `navigator.share({title, url})`, so the link has to live in the body — the
  /// same shape [profileShareMessage] already uses for profile sharing.
  String get shareMessage {
    final buffer = StringBuffer();
    buffer.writeln(
      '🏡 ${title.isNotEmpty ? title : 'Check out this property'}',
    );

    if (hasPrice) buffer.writeln('💰 $price');
    if (hasLocation) buffer.writeln('📍 $location');
    if (hasBuilder) buffer.writeln('🏢 by $builderName');

    if (description.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(description.trim());
    }

    buffer.writeln();
    buffer.writeln('Discover more premium properties on PropCID.');
    buffer.writeln(shareUrl);

    return buffer.toString().trim();
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
