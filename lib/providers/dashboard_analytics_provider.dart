import 'package:flutter/foundation.dart';

import '../models/dashboard_analytics.dart';
import '../services/dashboard_analytics_service.dart';

/// Analytics + Audience state for the Manage Dashboard.
///
/// Additive: each role keeps its own existing dashboard provider for its own
/// business logic; this one only supplies the metrics the approved design shows
/// and which no Flutter service previously computed.
///
/// Follows the shape of the other feature providers (blueprint §1.2.1). The two
/// tabs load independently so a failure in one never blanks the other.
class DashboardAnalyticsProvider extends ChangeNotifier {
  DashboardAnalyticsProvider({
    required this.analyticsSource,
    required this.audienceSource,
    this.includeSavedProperties = false,
    this.growthFromContent = true,
    this.includeListingMetrics = false,
    this.includeWatchMetrics = false,
    this.includeLeadMetrics = false,
    this.includeCrossContentInsights = false,
    this.crossContentFunction = 'influencer-audience-insights',
    DashboardAnalyticsService? service,
  }) : _service = service ?? DashboardAnalyticsService();

  /// Content table for the Analytics tab.
  ///
  /// Separate from [audienceSource] because React is not consistent: for the
  /// Individual role `IndividualAnalytics.tsx` reads `influencer_videos` while
  /// `IndividualAudienceInsights.tsx` reads `properties`.
  final AnalyticsContentSource analyticsSource;

  /// Content table for the Audience tab.
  final AnalyticsContentSource audienceSource;

  /// Only the Individual variant queries `saved_properties` in React.
  final bool includeSavedProperties;

  /// Broker hard-codes its growth figures to 0 in React.
  final bool growthFromContent;

  /// Broker only: the six listing metrics `BrokerAnalytics.tsx` computes and no
  /// other variant does — inquiries, active/sold counts, portfolio value and
  /// commission.
  ///
  /// Off by default, in the same shape as [includeSavedProperties], so every
  /// role that does not opt in issues exactly the queries it did before Spec C.
  final bool includeListingMetrics;

  /// Influencer only: `avgWatchTime` and `avgCompletionRate` from
  /// `influencer_video_views` (`InfluencerAnalytics.tsx:75-87`).
  final bool includeWatchMetrics;

  /// Broker only: the three lead metrics from `property_inquiries`
  /// (`BrokerAudienceInsights.tsx:88-101`). Audience tab.
  final bool includeLeadMetrics;

  /// Influencer/builder only: the cross-content Reach/Likes/Comments, Content
  /// Breakdown and Most Liked Content that
  /// `DashboardAnalyticsService.fetchCrossContentInsights` gets from a
  /// deployed `*-audience-insights` edge function. Off by default, so every
  /// other role's Audience tab issues exactly the queries it did before this
  /// feature.
  final bool includeCrossContentInsights;

  /// Which edge function [includeCrossContentInsights] calls — defaults to
  /// influencer's; the builder dashboard passes `'builder-audience-insights'`.
  final String crossContentFunction;

  final DashboardAnalyticsService _service;

  String? _userId;
  bool _disposed = false;

  DashboardAnalytics _analytics = DashboardAnalytics.empty;
  bool _analyticsLoading = true;
  bool _analyticsFailed = false;

  DashboardAudience _audience = DashboardAudience.empty;
  bool _audienceLoading = true;
  bool _audienceFailed = false;

  /// Independent from [_audienceLoading]/[_audienceFailed] — a failed
  /// cross-content fetch must not blank the follower/views/engagement
  /// metrics [_loadAudience] already loaded, and vice versa.
  bool _crossContentLoading = false;
  bool _crossContentFailed = false;

  DashboardAnalytics get analytics => _analytics;
  bool get analyticsLoading => _analyticsLoading;
  bool get analyticsFailed => _analyticsFailed;

  DashboardAudience get audience => _audience;
  bool get audienceLoading => _audienceLoading;
  bool get audienceFailed => _audienceFailed;

  bool get crossContentLoading => _crossContentLoading;
  bool get crossContentFailed => _crossContentFailed;

  Future<void> load(String userId) async {
    _userId = userId;
    await Future.wait([
      _loadAnalytics(userId),
      _loadAudience(userId),
      if (includeCrossContentInsights) _loadCrossContentInsights(),
    ]);
  }

  /// Retries only the cross-content section — the follower/views/engagement
  /// metrics above it stay exactly as they are, so a transient edge-function
  /// failure does not force a full-tab reload to recover from.
  Future<void> retryCrossContentInsights() {
    if (!includeCrossContentInsights) return Future.value();
    return _loadCrossContentInsights();
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    await load(userId);
  }

  Future<void> _loadAnalytics(String userId) async {
    _analyticsLoading = true;
    _analyticsFailed = false;
    _safeNotify();

    try {
      _analytics = await _service.fetchAnalytics(
        userId: userId,
        source: analyticsSource,
        includeSavedProperties: includeSavedProperties,
        growthFromContent: growthFromContent,
        includeListingMetrics: includeListingMetrics,
        includeWatchMetrics: includeWatchMetrics,
      );
    } catch (e) {
      debugPrint('DashboardAnalyticsProvider._loadAnalytics failed: $e');
      _analyticsFailed = true;
      _analytics = DashboardAnalytics.empty;
    } finally {
      _analyticsLoading = false;
      _safeNotify();
    }
  }

  Future<void> _loadAudience(String userId) async {
    _audienceLoading = true;
    _audienceFailed = false;
    _safeNotify();

    try {
      final fresh = await _service.fetchAudience(
        userId: userId,
        source: audienceSource,
        includeLeadMetrics: includeLeadMetrics,
      );
      // `_loadCrossContentInsights` runs concurrently with this (see [load])
      // and may already have merged its result into `_audience` — carry it
      // forward rather than letting this assignment silently drop it.
      final existingCrossContent = _audience.crossContent;
      _audience = existingCrossContent != null
          ? fresh.copyWithCrossContent(existingCrossContent)
          : fresh;
    } catch (e) {
      debugPrint('DashboardAnalyticsProvider._loadAudience failed: $e');
      _audienceFailed = true;
      // Reset the base metrics, but keep a cross-content result that already
      // loaded successfully — this failure is not that section's failure.
      final existingCrossContent = _audience.crossContent;
      _audience = existingCrossContent != null
          ? DashboardAudience.empty.copyWithCrossContent(existingCrossContent)
          : DashboardAudience.empty;
    } finally {
      _audienceLoading = false;
      _safeNotify();
    }
  }

  /// Merges into whatever [_audience] currently holds rather than replacing
  /// it — [_loadAudience] and this run independently (see [load]), and
  /// either can finish first.
  Future<void> _loadCrossContentInsights() async {
    _crossContentLoading = true;
    _crossContentFailed = false;
    _safeNotify();

    try {
      final insights = await _service.fetchCrossContentInsights(
        functionName: crossContentFunction,
      );
      _audience = _audience.copyWithCrossContent(insights);
    } catch (e) {
      debugPrint(
        'DashboardAnalyticsProvider._loadCrossContentInsights failed: $e',
      );
      _crossContentFailed = true;
    } finally {
      _crossContentLoading = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
