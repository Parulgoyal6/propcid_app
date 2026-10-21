/// Which table a role's "content" lives in, and which column names its owner.
///
/// React uses a different source per role but an identical set of formulas:
/// `BrokerAnalytics.tsx` and the audience variants read `properties`, while
/// `InfluencerAnalytics.tsx` and `IndividualAnalytics.tsx` read
/// `influencer_videos`. Modelling it as a source keeps one code path.
///
/// [builderProjects] was added with Spec C. It is the one value whose owner
/// column is **not** `user_id` — `builder_projects` names it `builder_id` — which
/// is why [ownerColumn] exists rather than the service hard-coding `user_id`.
/// Both pre-existing values keep `user_id`, so no existing caller changes.
enum AnalyticsContentSource {
  properties,
  influencerVideos,
  builderProjects;

  String get table => switch (this) {
    AnalyticsContentSource.properties => 'properties',
    AnalyticsContentSource.influencerVideos => 'influencer_videos',
    AnalyticsContentSource.builderProjects => 'builder_projects',
  };

  /// The column holding the owning user's id.
  ///
  /// `builder_projects.builder_id` is a plain uuid to `auth.users`, same as the
  /// other two tables' `user_id` — only the name differs.
  String get ownerColumn => switch (this) {
    AnalyticsContentSource.properties => 'user_id',
    AnalyticsContentSource.influencerVideos => 'user_id',
    AnalyticsContentSource.builderProjects => 'builder_id',
  };

  /// Whether this table has a `price` column.
  ///
  /// **Only `properties` does.** `builder_projects` prices a range —
  /// `price_range_min` / `price_range_max` — and `influencer_videos` has no notion
  /// of price at all.
  ///
  /// This exists because assuming otherwise was a live bug: Spec C selected
  /// `price` unconditionally for all three sources, which is a
  /// `42703 undefined_column` against two of them and took out the whole Analytics
  /// tab for builders and influencers. The column list is now derived from the
  /// source rather than shared blindly.
  bool get hasPriceColumn => this == AnalyticsContentSource.properties;

  /// The columns `fetchAnalytics` selects from this table.
  ///
  /// Shared where the tables agree and divergent where they do not, which is the
  /// point: all three carry `id, title, views, likes, created_at, status`, and only
  /// `properties` adds `price`.
  ///
  /// `status` is safe on all three — `properties`, `builder_projects` and
  /// `influencer_videos` each declare it — so it stays in the common list even
  /// though only the broker branch reads it.
  String get analyticsColumns =>
      'id, title, views, likes, created_at, status${hasPriceColumn ? ', price' : ''}';
}

/// One point in a dashboard chart series.
class ChartPoint {
  final DateTime date;
  final double value;

  const ChartPoint({required this.date, required this.value});
}

/// The Analytics tab's six metrics, plus its chart and top-content list.
///
/// Mirrors the state assembled by `IndividualAnalytics.tsx` /
/// `BrokerAnalytics.tsx` / `InfluencerAnalytics.tsx`.
class DashboardAnalytics {
  final int totalViews;
  final int totalLikes;

  /// `saved_properties` row count. Only `IndividualAnalytics.tsx` computes
  /// this; the other roles leave it at zero, as React does.
  final int totalSaved;

  /// `(totalLikes / totalViews) * 100`, or 0 when there are no views.
  final double avgEngagement;

  /// `totalViews + totalLikes`.
  final int totalInteractions;

  /// Number of content rows the user owns.
  final int contentPosted;

  /// Last 7 days vs the 7 before, as a percentage. `BrokerAnalytics.tsx`
  /// hard-codes these to 0 with the comment that growth needs historical
  /// engagement tracking, so brokers keep 0.
  final double viewsGrowth;
  final double likesGrowth;

  /// Top 5 by views, descending.
  final List<TopContentItem> topContent;

  /// Seven points ending today — the window the design's Mon–Sun axis shows.
  final List<ChartPoint> performance;

  // ── Broker-only, added with Spec C ──────────────────────────────────────
  //
  // `BrokerAnalytics.tsx:9-22` declares six metrics the shared model had no
  // field for. All six are null for every other role, which is how the UI
  // decides whether to render them — a `0` would be indistinguishable from a
  // broker who genuinely has no inquiries.

  /// `property_inquiries` rows across all of this broker's listings
  /// (`BrokerAnalytics.tsx:107-117`).
  final int? totalInquiries;

  /// Listings with `status = 'active'` / `'sold'` (`:85-86`).
  final int? activeCount;
  final int? soldCount;

  /// Σ `price` of active listings (`:88-95`).
  ///
  /// The portal parses the free-text `price` column with
  /// `parseFloat(String(p.price).replace(/[^0-9.]/g, ''))`, so this carries the
  /// same lossy parse rather than a cleaner one.
  final double? totalValue;

  /// `soldValue * (commissionRate / 100)` (`:97-105`).
  final double? totalCommission;

  /// Hard-coded to 2 in the portal, with the comment "assuming 2% commission
  /// rate" (`:104`). Carried as a field rather than a constant so the tile can
  /// label itself with whatever the value is.
  final double? commissionRate;

  // ── Influencer-only, added with Spec C ──────────────────────────────────

  /// Mean `watch_duration_seconds` over every `influencer_video_views` row for
  /// this influencer's videos (`InfluencerAnalytics.tsx:84-86`).
  final double? avgWatchTime;

  /// Mean `watch_percentage` over the same rows (`:86`).
  final double? avgCompletionRate;

  const DashboardAnalytics({
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalSaved = 0,
    this.avgEngagement = 0,
    this.totalInteractions = 0,
    this.contentPosted = 0,
    this.viewsGrowth = 0,
    this.likesGrowth = 0,
    this.topContent = const [],
    this.performance = const [],
    this.totalInquiries,
    this.activeCount,
    this.soldCount,
    this.totalValue,
    this.totalCommission,
    this.commissionRate,
    this.avgWatchTime,
    this.avgCompletionRate,
  });

  static const DashboardAnalytics empty = DashboardAnalytics();

  bool get hasPerformanceData => performance.any((p) => p.value > 0);
}

/// The Audience tab's four metrics, its chart and its insight rows.
///
/// Mirrors `IndividualAudienceInsights.tsx` / `BrokerAudienceInsights.tsx` /
/// `InfluencerAudienceInsights.tsx`, which are identical apart from the
/// content table they read.
class DashboardAudience {
  final int totalFollowers;

  /// Last 7 days vs the 7 before. React's fallback differs from the analytics
  /// one: when there is no previous window it returns 100 if there were any
  /// recent followers, else 0.
  final double followersGrowth;

  final int totalViews;

  /// `totalViews / contentCount`, rounded for display.
  final double avgViewsPerPost;

  /// `(totalLikes / totalViews) * 100`.
  final double engagementRate;

  /// 31 cumulative points, matching React's `for (let i = 30; i >= 0; i--)`
  /// loop. Rendered unlabelled, as the design shows.
  final List<ChartPoint> followerGrowth;

  // ── Broker-only, added with Spec C ──────────────────────────────────────
  //
  // `BrokerAudienceInsights.tsx:9-18` declares three metrics the other two
  // audience variants do not. Null for every other role.

  /// `property_inquiries` rows across this broker's listings (`:96`).
  final int? totalLeads;

  /// `closed / total * 100`, where closed is `status = 'closed'` (`:97-98`).
  final double? leadConversionRate;

  /// `contacted / total * 100`, where contacted is
  /// `status IN ('contacted', 'scheduled', 'approved')` (`:99-100`).
  ///
  /// Note the portal counts three statuses as "responded", not one.
  final double? responseRate;

  // ── Influencer-only, cross-content ───────────────────────────────────────
  //
  // Populated only when `DashboardAnalyticsProvider.includeCrossContentInsights`
  // is set (influencer role) — see `DashboardAnalyticsService
  // .fetchCrossContentInsights`. Null for every other role, and null (not
  // [CrossContentInsights.empty]) until that fetch has actually completed, so
  // the UI can tell "not fetched for this role" apart from "fetched, and this
  // influencer genuinely has no content yet".
  final CrossContentInsights? crossContent;

  const DashboardAudience({
    this.totalFollowers = 0,
    this.followersGrowth = 0,
    this.totalViews = 0,
    this.avgViewsPerPost = 0,
    this.engagementRate = 0,
    this.followerGrowth = const [],
    this.totalLeads,
    this.leadConversionRate,
    this.responseRate,
    this.crossContent,
  });

  static const DashboardAudience empty = DashboardAudience();

  bool get hasGrowthData => followerGrowth.any((p) => p.value > 0);

  /// A copy with [crossContent] replaced — the only field
  /// `DashboardAnalyticsProvider` needs to merge in after its own,
  /// independent fetch, without disturbing anything [fetchAudience] already
  /// computed.
  DashboardAudience copyWithCrossContent(CrossContentInsights value) =>
      DashboardAudience(
        totalFollowers: totalFollowers,
        followersGrowth: followersGrowth,
        totalViews: totalViews,
        avgViewsPerPost: avgViewsPerPost,
        engagementRate: engagementRate,
        followerGrowth: followerGrowth,
        totalLeads: totalLeads,
        leadConversionRate: leadConversionRate,
        responseRate: responseRate,
        crossContent: value,
      );
}

/// One row of "Top Performing Content".
class TopContentItem {
  final String id;
  final String title;
  final int views;
  final int likes;

  const TopContentItem({
    required this.id,
    required this.title,
    this.views = 0,
    this.likes = 0,
  });
}

/// Which content table a cross-content row or breakdown entry came from —
/// the `influencer-audience-insights` edge function's own `type` discriminator
/// (`_shared/topContent.ts`). Used to route a tap to the right detail screen;
/// a reel id and an article id are never interchangeable with a property id.
enum CrossContentType {
  reel,
  property,
  article,
  project;

  static CrossContentType? fromWire(String? value) => switch (value) {
    'reel' => CrossContentType.reel,
    'property' => CrossContentType.property,
    'article' => CrossContentType.article,
    'project' => CrossContentType.project,
    _ => null,
  };
}

/// One entry of the edge function's `breakdown` — cross-content totals
/// grouped by [CrossContentType].
class ContentBreakdownItem {
  final CrossContentType type;
  final int count;
  final int views;
  final int likes;
  final int comments;

  const ContentBreakdownItem({
    required this.type,
    this.count = 0,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
  });
}

/// One row of the edge function's `topContent` — ranked by likes desc, views
/// desc (`summarizeContent`'s default), capped at 5, spanning reels,
/// properties and articles.
///
/// Distinct from [TopContentItem]: that one is single-source and carries no
/// [type]/[comments], so it cannot drive per-type navigation.
class CrossContentItem {
  final String id;
  final CrossContentType type;
  final String title;
  final int views;
  final int likes;
  final int comments;

  const CrossContentItem({
    required this.id,
    required this.type,
    required this.title,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
  });
}

/// Cross-content audience metrics from the `influencer-audience-insights`
/// edge function — reach/likes/comments and rankings spanning reels,
/// properties and articles, which no single-table query can produce.
///
/// Present (non-null on [DashboardAudience.crossContent]) only for the
/// influencer role; every other dashboard variant leaves it null rather than
/// showing a permanent zero for a section it never fetches.
class CrossContentInsights {
  final int totalViews;
  final int totalLikes;
  final int totalComments;
  final List<ContentBreakdownItem> breakdown;
  final List<CrossContentItem> topContent;

  const CrossContentInsights({
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.breakdown = const [],
    this.topContent = const [],
  });

  static const CrossContentInsights empty = CrossContentInsights();
}
