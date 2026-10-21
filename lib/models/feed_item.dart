// models/feed_item.dart
//
// One entry in the "Feed" screen — a client-side merge of `properties`,
// `builder_projects` and `influencer_videos`, mirroring the portal's
// `CombinedFeed.tsx` (propcid/src/features/content/CombinedFeed.tsx). The
// portal has no single `posts` table; neither does this model invent one —
// it just carries whichever of the three rows produced it, plus the poster's
// profile fields needed to render a card and to run the role filter below.

import '../models/property_model.dart' show PropertyModel;

enum FeedItemType { property, project, video }

/// The Feed screen's filter chips, in the portal's own order and copy
/// (`CombinedFeed.tsx`'s `filters` array — "Brokers", "Builders",
/// "Influencers", "Exclusive"; the portal has no "All" tab and opens on
/// "Brokers"). [exclusive] is broker/admin-only (see [isExclusiveViewer]) and
/// is backed by `builder_project_offers` ([FeedOffer]), not the content
/// items the other three filter.
enum FeedRoleFilter {
  broker('Brokers'),
  builder('Builders'),
  influencer('Influencers'),
  exclusive('Exclusive');

  const FeedRoleFilter(this.label);

  final String label;

  /// Portal gate for the Exclusive tab:
  /// `userProfile?.user_type === 'broker' || userProfile?.user_type === 'admin'`.
  static bool isExclusiveViewer(String? userType) =>
      userType == 'broker' || userType == 'admin';
}

/// One `builder_project_offers` row as `combined-feed-list` returns it for
/// `category: 'exclusive-offers'` (`*, project:builder_projects(*),
/// builder:profiles(*)`) — the fields the portal's `ProjectOfferCard` shows.
class FeedOffer {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;

  /// Every `offer_media_urls` entry, in order — [imageUrl] is just
  /// `mediaUrls.first`. Carried separately so the card's photo tap can open
  /// the full gallery viewer instead of only ever showing the cover photo.
  final List<String> mediaUrls;
  final DateTime? createdAt;
  final String? builderId;
  final String builderName;
  final String? builderAvatarUrl;
  final String? projectId;
  final String projectTitle;
  final String projectLocation;

  /// Project price range label, or null when neither bound is set.
  final String? priceLabel;

  const FeedOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.builderName,
    required this.projectTitle,
    required this.projectLocation,
    this.imageUrl,
    this.mediaUrls = const [],
    this.createdAt,
    this.builderId,
    this.builderAvatarUrl,
    this.projectId,
    this.priceLabel,
  });

  factory FeedOffer.fromJson(Map<String, dynamic> json) {
    final media = List<dynamic>.from(
      json['offer_media_urls'] as List? ?? [],
    ).map((u) => u?.toString() ?? '').where((u) => u.isNotEmpty).toList();
    final project = json['project'] is Map
        ? Map<String, dynamic>.from(json['project'] as Map)
        : const <String, dynamic>{};
    final builder = json['builder'] is Map
        ? Map<String, dynamic>.from(json['builder'] as Map)
        : const <String, dynamic>{};
    final company = builder['company_name']?.toString() ?? '';
    return FeedOffer(
      id: json['id']?.toString() ?? '',
      title: json['offer_title']?.toString() ?? '',
      description: json['offer_description']?.toString() ?? '',
      imageUrl: media.isNotEmpty ? media.first : null,
      mediaUrls: media,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      builderId: json['builder_id']?.toString(),
      // Portal: `offer.builder.company_name || offer.builder.display_name`.
      builderName: company.isNotEmpty
          ? company
          : (builder['display_name']?.toString() ?? 'Builder'),
      builderAvatarUrl: builder['avatar_url']?.toString(),
      projectId: project['id']?.toString(),
      projectTitle: project['title']?.toString() ?? '',
      projectLocation: project['location']?.toString() ?? '',
      priceLabel: FeedItem._projectPriceLabel(
        project['price_range_min'],
        project['price_range_max'],
      ),
    );
  }
}

class FeedItem {
  final FeedItemType type;
  final String id;
  final DateTime? createdAt;
  final String title;
  final String subtitle;

  /// `properties.location` / `builder_projects.location`, shown as its own
  /// pin-icon row on the card. Videos have no location concept, so this
  /// stays empty for those.
  final String location;
  final String? imageUrl;
  final String? videoUrl;

  /// Every `media_urls` entry for a property/project item, in order —
  /// [imageUrl] is just `mediaUrls.first`. Empty for a video item (its
  /// `videoUrl`/[imageUrl] thumbnail pair already covers it; there is no
  /// multi-item gallery for a single reel). Carried separately so the
  /// card's photo tap can open the full gallery viewer instead of only
  /// ever showing the cover photo.
  final List<String> mediaUrls;
  final int views;
  final int likes;

  /// `properties.comments` / `builder_projects.comments` — populated for
  /// property and project items alike, both of which show a Comment count
  /// on their Feed card (`_PropertyFeedActions`/`_ProjectFeedActions`).
  /// Still unused for a video item, which has no comment affordance.
  final int comments;

  final String? posterUserId;
  final String posterName;
  final String? posterAvatarUrl;

  /// `profiles.user_type` of the poster — drives both the role pill and the
  /// filter predicate below.
  final String? posterUserType;

  /// `properties.category` / `properties.property_type` — only populated for
  /// property items, so the Feed's property cards can show the same
  /// category/listing-type chips the Search results property card already
  /// shows.
  final String? category;
  final String? propertyType;

  /// `builder_projects.project_type` — a project's equivalent of a
  /// property's [category]/[propertyType] chip (e.g. "Residential Project",
  /// "Commercial Project"). Only populated for project items.
  final String? projectType;

  /// `properties.media_urls.length` / `builder_projects.media_urls.length` —
  /// the photo-count badge shown on the card's media block.
  final int photoCount;

  const FeedItem({
    required this.type,
    required this.id,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    this.location = '',
    required this.views,
    required this.likes,
    this.comments = 0,
    required this.posterName,
    this.imageUrl,
    this.videoUrl,
    this.mediaUrls = const [],
    this.posterUserId,
    this.posterAvatarUrl,
    this.posterUserType,
    this.category,
    this.propertyType,
    this.projectType,
    this.photoCount = 0,
  });

  /// Mirrors `CombinedFeed.tsx`'s per-filter predicate exactly (including its
  /// quirks — "Brokers" also matches `individual`, and "Builders" excludes
  /// the viewer's own posts), so a filter changes the *data*, not just the
  /// chip's selected style.
  bool matchesFilter(FeedRoleFilter filter, String? currentUserId) {
    switch (filter) {
      // Exclusive shows [FeedOffer]s, never content items.
      case FeedRoleFilter.exclusive:
        return false;
      case FeedRoleFilter.broker:
        return posterUserType == 'broker' ||
            posterUserType == 'professional_broker' ||
            posterUserType == 'individual';
      case FeedRoleFilter.builder:
        return posterUserType == 'builder' &&
            (type == FeedItemType.project || type == FeedItemType.property) &&
            posterUserId != currentUserId;
      case FeedRoleFilter.influencer:
        return type == FeedItemType.video || posterUserType == 'influencer';
    }
  }

  factory FeedItem.fromProperty(
    Map<String, dynamic> json,
    Map<String, dynamic>? profile,
  ) {
    final images = List<String>.from(json['media_urls'] as List? ?? const []);
    return FeedItem(
      type: FeedItemType.property,
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      title: json['title']?.toString() ?? '',
      subtitle: PropertyModel.formatIndianPrice(json['price']),
      location: json['location']?.toString() ?? '',
      imageUrl: images.isNotEmpty ? images.first : null,
      mediaUrls: images,
      views: _int(json['views']),
      likes: _int(json['likes']),
      comments: _int(json['comments']),
      posterUserId: json['user_id']?.toString(),
      posterName: profile?['display_name']?.toString() ?? 'User',
      posterAvatarUrl: profile?['avatar_url']?.toString(),
      posterUserType: profile?['user_type']?.toString(),
      category: json['category']?.toString(),
      propertyType: json['property_type']?.toString(),
      photoCount: images.length,
    );
  }

  factory FeedItem.fromProject(
    Map<String, dynamic> json,
    Map<String, dynamic>? profile,
  ) {
    final images = List<String>.from(json['media_urls'] as List? ?? const []);
    return FeedItem(
      type: FeedItemType.project,
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      title: json['title']?.toString() ?? '',
      // Genuinely absent when neither price_range column is set (both
      // default to 0 in the DB, same "0 means absent" convention
      // `ProjectModel.hasPriceRange` already uses) — never shown as "₹0".
      subtitle:
          _projectPriceLabel(
            json['price_range_min'],
            json['price_range_max'],
          ) ??
          '',
      location: json['location']?.toString() ?? '',
      imageUrl: images.isNotEmpty ? images.first : null,
      mediaUrls: images,
      views: _int(json['views']),
      likes: _int(json['likes']),
      comments: _int(json['comments']),
      posterUserId: json['builder_id']?.toString(),
      posterName: profile?['display_name']?.toString() ?? 'User',
      posterAvatarUrl: profile?['avatar_url']?.toString(),
      posterUserType: profile?['user_type']?.toString(),
      projectType: json['project_type']?.toString(),
      // Previously always 0 (never set here), so a project's photo-count
      // badge never showed even when it had a full gallery.
      photoCount: images.length,
    );
  }

  factory FeedItem.fromVideo(
    Map<String, dynamic> json,
    Map<String, dynamic>? profile,
  ) {
    return FeedItem(
      type: FeedItemType.video,
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      title: json['title']?.toString() ?? '',
      subtitle: 'Video',
      imageUrl: json['thumbnail_url']?.toString(),
      videoUrl: json['video_url']?.toString(),
      views: _int(json['views']),
      likes: _int(json['likes']),
      posterUserId: json['user_id']?.toString(),
      posterName: profile?['display_name']?.toString() ?? 'User',
      posterAvatarUrl: profile?['avatar_url']?.toString(),
      posterUserType: profile?['user_type']?.toString(),
    );
  }

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };

  /// A project's price line — "₹1.2 Cr - ₹1.8 Cr" when both bounds are set,
  /// "From ₹1.2 Cr" when only one is, or null when neither is (both columns
  /// default to 0 in the DB — 0 means absent, same convention
  /// `ProjectModel.hasPriceRange` already uses elsewhere). Null means the
  /// card hides the price line entirely rather than showing "₹0".
  static String? _projectPriceLabel(Object? rawMin, Object? rawMax) {
    final min = double.tryParse(rawMin?.toString() ?? '') ?? 0;
    final max = double.tryParse(rawMax?.toString() ?? '') ?? 0;
    if (min <= 0 && max <= 0) return null;
    if (min > 0 && max > 0 && max != min) {
      return '${PropertyModel.formatIndianPrice(min)} - ${PropertyModel.formatIndianPrice(max)}';
    }
    return 'From ${PropertyModel.formatIndianPrice(min > 0 ? min : max)}';
  }
}
