/// What a hero-banner tap should do. Banners never navigate themselves —
/// they build one of these and hand it to `BannerDestinationResolver`, so the
/// destination logic lives in exactly one place.
enum BannerDestinationType {
  property,
  collection,
  project,
  builder,
  externalUrl,
}

class BannerDestination {
  const BannerDestination.property(String propertyId)
    : type = BannerDestinationType.property,
      propertyId = propertyId,
      url = null,
      category = null,
      listingType = null,
      hashtag = null,
      city = null,
      subtype = null,
      budgetMin = null,
      budgetMax = null,
      comingSoonLabel = null;

  const BannerDestination.externalUrl(String url)
    : type = BannerDestinationType.externalUrl,
      url = url,
      propertyId = null,
      category = null,
      listingType = null,
      hashtag = null,
      city = null,
      subtype = null,
      budgetMin = null,
      budgetMax = null,
      comingSoonLabel = null;

  /// A "collection" is just a pre-applied set of `FilterProvider` fields —
  /// whichever of these are non-null get applied before navigating to
  /// search results. At least one should be set or the filter is a no-op.
  const BannerDestination.collection({
    this.category,
    this.listingType,
    this.hashtag,
    this.city,
    this.subtype,
    this.budgetMin,
    this.budgetMax,
  }) : type = BannerDestinationType.collection,
       propertyId = null,
       url = null,
       comingSoonLabel = null;

  /// Same filtering mechanism as `collection`, framed as "this project" —
  /// falls back to [comingSoonLabel] if no filter field is supplied, since
  /// there's no dedicated project-detail screen or project-id filter today.
  const BannerDestination.project({
    this.category,
    this.listingType,
    this.hashtag,
    this.city,
    this.subtype,
    this.budgetMin,
    this.budgetMax,
    this.comingSoonLabel = 'Project details coming soon',
  }) : type = BannerDestinationType.project,
       propertyId = null,
       url = null;

  /// Same filtering mechanism as `collection`, framed as "this builder" —
  /// falls back to [comingSoonLabel] if no filter field is supplied, since
  /// there's no builder-ID-scoped filter anywhere in `SearchQueryParams`
  /// today (only a `postedBy` user-type filter, not a specific builder).
  const BannerDestination.builder({
    this.category,
    this.listingType,
    this.hashtag,
    this.city,
    this.subtype,
    this.budgetMin,
    this.budgetMax,
    this.comingSoonLabel = 'Builder profile coming soon',
  }) : type = BannerDestinationType.builder,
       propertyId = null,
       url = null;

  final BannerDestinationType type;
  final String? propertyId;
  final String? url;
  final String? category;
  final String? listingType;
  final String? hashtag;
  final String? city;
  final String? subtype;
  final double? budgetMin;
  final double? budgetMax;
  final String? comingSoonLabel;

  bool get hasFilterFields =>
      category != null ||
      listingType != null ||
      hashtag != null ||
      city != null ||
      subtype != null ||
      budgetMin != null ||
      budgetMax != null;
}
