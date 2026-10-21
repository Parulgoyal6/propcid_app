import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_analytics.dart';

/// Read-only analytics for the Manage Dashboard.
///
/// Ported from the React portal's `features/analytics/*` — see blueprint §9.
/// The three Analytics files (`IndividualAnalytics.tsx`,
/// `BrokerAnalytics.tsx`, `InfluencerAnalytics.tsx`) and the three Audience
/// files (`IndividualAudienceInsights.tsx`, `BrokerAudienceInsights.tsx`,
/// `InfluencerAudienceInsights.tsx`) apply identical formulas and differ only
/// in which table holds the user's content, so both are expressed once here
/// with an [AnalyticsContentSource].
///
/// No schema, RLS, API or business-logic change: every call below is a SELECT.
class DashboardAnalyticsService {
  /// Resolved on first use rather than at construction, so the service (and the
  /// provider that owns one) can be instantiated in a widget test without a
  /// live `Supabase.initialize`.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Days in the performance window. React groups the last 30 days; the design
  /// shows a seven-point Mon–Sun axis, so the same per-day aggregation is
  /// rendered over the last seven days.
  static const int performanceWindowDays = 7;

  /// Days in the follower-growth series, matching React's
  /// `for (let i = 30; i >= 0; i--)` loop — 31 points.
  static const int followerWindowDays = 30;

  // ── Analytics tab ─────────────────────────────────────────────────────────

  /// Mirrors `fetchAnalytics` in the three `*Analytics.tsx` files.
  ///
  /// [includeSavedProperties] reflects that only `IndividualAnalytics.tsx`
  /// queries `saved_properties`; the other roles leave that tile at zero.
  /// [growthFromContent] reflects that `BrokerAnalytics.tsx` deliberately
  /// hard-codes its growth figures to 0, noting that real growth needs
  /// historical engagement tracking.
  /// [includeListingMetrics] adds the six metrics `BrokerAnalytics.tsx` computes
  /// that no other variant does — inquiry count, active/sold counts, portfolio
  /// value and commission. Broker only.
  ///
  /// [includeWatchMetrics] adds the two `InfluencerAnalytics.tsx` computes from
  /// `influencer_video_views`. Influencer only.
  ///
  /// Both default to false, so every existing caller behaves exactly as before
  /// and issues exactly the same queries.
  Future<DashboardAnalytics> fetchAnalytics({
    required String userId,
    required AnalyticsContentSource source,
    bool includeSavedProperties = false,
    bool growthFromContent = true,
    bool includeListingMetrics = false,
    bool includeWatchMetrics = false,
  }) async {
    try {
      final rows = await _supabase
          .from(source.table)
          // Per-source, NOT a shared literal. Spec C selected `price`
          // unconditionally here, which is a 42703 against `builder_projects`
          // (which prices a range) and `influencer_videos` (which has no price at
          // all) — it broke the Analytics tab outright for both roles. See
          // AnalyticsContentSource.analyticsColumns.
          .select(source.analyticsColumns)
          // Not a literal 'user_id': builder_projects names its owner column
          // `builder_id`. See AnalyticsContentSource.ownerColumn.
          .eq(source.ownerColumn, userId)
          .order('created_at', ascending: false);

      final content = List<Map<String, dynamic>>.from(rows as List);

      // React returns early with all-zero state when the user has no content.
      if (content.isEmpty) return DashboardAnalytics.empty;

      final totalViews = _sum(content, 'views');
      final totalLikes = _sum(content, 'likes');
      final avgEngagement = totalViews > 0
          ? (totalLikes / totalViews) * 100
          : 0.0;

      var totalSaved = 0;
      if (includeSavedProperties) {
        final saved = await _supabase
            .from('saved_properties')
            .select('id')
            .eq('user_id', userId);
        totalSaved = (saved as List).length;
      }

      double viewsGrowth = 0;
      double likesGrowth = 0;
      if (growthFromContent) {
        viewsGrowth = _growth(content, 'views');
        likesGrowth = _growth(content, 'likes');
      }

      // Top 5 by views, descending — React's `.sort(...).slice(0, 5)`.
      final sorted = List<Map<String, dynamic>>.from(content)
        ..sort((a, b) => _int(b['views']).compareTo(_int(a['views'])));

      final topContent = sorted
          .take(5)
          .map(
            (row) => TopContentItem(
              id: row['id'].toString(),
              title: (row['title'] as String?)?.trim().isNotEmpty == true
                  ? row['title'] as String
                  : 'Untitled',
              views: _int(row['views']),
              likes: _int(row['likes']),
            ),
          )
          .toList();

      // ── Broker listing metrics (BrokerAnalytics.tsx:85-117) ──────────────
      int? totalInquiries;
      int? activeCount;
      int? soldCount;
      double? totalValue;
      double? totalCommission;
      double? commissionRate;

      if (includeListingMetrics) {
        // Status counts are safe on any source — all three declare `status`.
        activeCount = content.where((r) => r['status'] == 'active').length;
        soldCount = content.where((r) => r['status'] == 'sold').length;

        // The money metrics are guarded on the column existing, not on the caller
        // having asked. A caller that opts into listing metrics for a source with
        // no `price` gets the counts and inquiries it can have, and null for the
        // two it cannot — rather than a query that fails and takes the whole tab
        // with it. Today only the broker opts in, and only `properties` has the
        // column; the guard is what stops that pairing being load-bearing.
        if (source.hasPriceColumn) {
          totalValue = _sumPrices(content, 'active');
          // "assuming 2% commission rate" — the portal's own constant (`:104`).
          commissionRate = 2;
          totalCommission =
              _sumPrices(content, 'sold') * (commissionRate / 100);
        }

        totalInquiries = await _countInquiries(
          content.map((r) => r['id'].toString()).toList(),
        );
      }

      // ── Influencer watch metrics (InfluencerAnalytics.tsx:75-87) ──────────
      double? avgWatchTime;
      double? avgCompletionRate;

      if (includeWatchMetrics) {
        final watch = await _fetchWatchMetrics(
          content.map((r) => r['id'].toString()).toList(),
        );
        avgWatchTime = watch.avgWatchTime;
        avgCompletionRate = watch.avgCompletionRate;
      }

      return DashboardAnalytics(
        totalViews: totalViews,
        totalLikes: totalLikes,
        totalSaved: totalSaved,
        avgEngagement: avgEngagement,
        totalInteractions: totalViews + totalLikes,
        // React shows `topContent.length` here, which its own `.slice(0, 5)`
        // caps at five. The tile is labelled "Total posts", so the real count
        // is used instead — the same call made for the article-edit RLS quirk.
        contentPosted: content.length,
        viewsGrowth: viewsGrowth,
        likesGrowth: likesGrowth,
        topContent: topContent,
        performance: _dailySeries(content, 'views', performanceWindowDays),
        totalInquiries: totalInquiries,
        activeCount: activeCount,
        soldCount: soldCount,
        totalValue: totalValue,
        totalCommission: totalCommission,
        commissionRate: commissionRate,
        avgWatchTime: avgWatchTime,
        avgCompletionRate: avgCompletionRate,
      );
    } catch (e) {
      debugPrint('DashboardAnalyticsService.fetchAnalytics failed: $e');
      rethrow;
    }
  }

  // ── Audience tab ──────────────────────────────────────────────────────────

  /// Mirrors `fetchAudienceInsights` in the three `*AudienceInsights.tsx`
  /// files.
  ///
  /// Followers come from the `followers` table keyed on `following_id`, which
  /// is what all three React audience files read. (The Profile screen's
  /// Followers tile intentionally stays on `builder_networks`, because
  /// `ProfileDashboardShell.tsx` — its own reference — uses that instead.)
  /// [includeLeadMetrics] adds the three `BrokerAudienceInsights.tsx` computes
  /// from `property_inquiries`. Broker only; false leaves the query set and the
  /// returned fields exactly as they were.
  Future<DashboardAudience> fetchAudience({
    required String userId,
    required AnalyticsContentSource source,
    bool includeLeadMetrics = false,
  }) async {
    try {
      final followerRows = await _supabase
          .from('followers')
          .select('created_at')
          .eq('following_id', userId);

      final followers = List<Map<String, dynamic>>.from(followerRows as List);
      final totalFollowers = followers.length;

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final fourteenDaysAgo = now.subtract(const Duration(days: 14));

      final recent = followers.where((f) {
        final d = _date(f['created_at']);
        return d != null && !d.isBefore(sevenDaysAgo);
      }).length;

      final previous = followers.where((f) {
        final d = _date(f['created_at']);
        return d != null &&
            !d.isBefore(fourteenDaysAgo) &&
            d.isBefore(sevenDaysAgo);
      }).length;

      // React's audience fallback differs from its analytics one: with no
      // previous window it returns 100 when there were recent followers.
      final followersGrowth = previous > 0
          ? ((recent - previous) / previous) * 100
          : (recent > 0 ? 100.0 : 0.0);

      final contentRows = await _supabase
          .from(source.table)
          // `id` is only needed by the lead branch; see the note in
          // fetchAnalytics about selecting it unconditionally.
          .select('id, views, likes')
          .eq(source.ownerColumn, userId);

      final content = List<Map<String, dynamic>>.from(contentRows as List);
      final totalViews = _sum(content, 'views');
      final totalLikes = _sum(content, 'likes');

      // -- Broker lead metrics (BrokerAudienceInsights.tsx:88-101) -----------
      int? totalLeads;
      double? leadConversionRate;
      double? responseRate;

      if (includeLeadMetrics) {
        final leads = await _fetchLeadMetrics(
          content.map((r) => r['id'].toString()).toList(),
        );
        totalLeads = leads.total;
        leadConversionRate = leads.conversionRate;
        responseRate = leads.responseRate;
      }

      return DashboardAudience(
        totalFollowers: totalFollowers,
        followersGrowth: followersGrowth,
        totalViews: totalViews,
        avgViewsPerPost: content.isNotEmpty ? totalViews / content.length : 0.0,
        engagementRate: totalViews > 0 ? (totalLikes / totalViews) * 100 : 0.0,
        followerGrowth: _cumulativeFollowerSeries(
          followers: followers,
          totalFollowers: totalFollowers,
          recentCount: recent,
          now: now,
        ),
        totalLeads: totalLeads,
        leadConversionRate: leadConversionRate,
        responseRate: responseRate,
      );
    } catch (e) {
      debugPrint('DashboardAnalyticsService.fetchAudience failed: $e');
      rethrow;
    }
  }

  // ── Cross-content insights (influencer, builder) ─────────────────────────

  /// Calls [functionName] — a deployed per-role `*-audience-insights` edge
  /// function, reused, never recreated. `influencer-audience-insights`
  /// already joins `influencer_videos` + `properties` + `cms_posts`;
  /// `builder-audience-insights` reads `builder_projects` (a builder's only
  /// content type). Both rank/group through the same
  /// `_shared/topContent.ts`'s `summarizeContent`, so this does not
  /// duplicate that cross-table calculation client-side.
  ///
  /// Only the response's cross-content fields (`totalViewsAll`/
  /// `totalLikesAll`/`totalCommentsAll`/`breakdown`/`topContent`) are read.
  /// The function also returns `stats.totalFollowers` etc. and its own
  /// `followerGrowth`, but those duplicate what [fetchAudience] already
  /// computes from the `followers` table for every role — reading them here
  /// too would give the Audience tab two disagreeing sources for the same
  /// numbers, so they are deliberately ignored.
  Future<CrossContentInsights> fetchCrossContentInsights({
    String functionName = 'influencer-audience-insights',
  }) async {
    try {
      final data = await _invoke(functionName);
      return parseCrossContentInsights(data);
    } catch (e) {
      debugPrint(
        'DashboardAnalyticsService.fetchCrossContentInsights failed: $e',
      );
      rethrow;
    }
  }

  /// The response → [CrossContentInsights] mapping, pulled out of
  /// [fetchCrossContentInsights] as a pure function so the parsing contract
  /// (missing keys, an unrecognised `type`, empty lists) can be tested
  /// directly against a JSON fixture — no live edge function or
  /// `Supabase.initialize` required.
  @visibleForTesting
  static CrossContentInsights parseCrossContentInsights(
    Map<String, dynamic> data,
  ) {
    final stats = data['stats'];
    final statsMap = stats is Map ? Map<String, dynamic>.from(stats) : const {};

    final breakdownRaw = data['breakdown'];
    final breakdown = breakdownRaw is List
        ? breakdownRaw
              .map((r) => r is Map ? Map<String, dynamic>.from(r) : null)
              .whereType<Map<String, dynamic>>()
              .map(_parseBreakdownItem)
              .whereType<ContentBreakdownItem>()
              .toList()
        : <ContentBreakdownItem>[];

    final topRaw = data['topContent'];
    final topContent = topRaw is List
        ? topRaw
              .map((r) => r is Map ? Map<String, dynamic>.from(r) : null)
              .whereType<Map<String, dynamic>>()
              .map(_parseCrossContentItem)
              .whereType<CrossContentItem>()
              .toList()
        : <CrossContentItem>[];

    return CrossContentInsights(
      // `builder-audience-insights` has only one content source, so its
      // `stats` has no separate "all content" sum — just `totalViews` — and
      // omits `totalViewsAll` entirely (unlike influencer's three-table
      // response, where the two legitimately differ). Falling back to
      // `totalViews` avoids reading that as a true zero for a builder who
      // actually has views.
      totalViews: _int(statsMap['totalViewsAll'] ?? statsMap['totalViews']),
      totalLikes: _int(statsMap['totalLikesAll']),
      totalComments: _int(statsMap['totalCommentsAll']),
      breakdown: breakdown,
      topContent: topContent,
    );
  }

  /// Null when `type` is missing or not one of the three this function ever
  /// sends — safe against an absent/unexpected key rather than throwing and
  /// taking out the whole section.
  static ContentBreakdownItem? _parseBreakdownItem(Map<String, dynamic> row) {
    final type = CrossContentType.fromWire(row['type'] as String?);
    if (type == null) return null;
    return ContentBreakdownItem(
      type: type,
      count: _int(row['count']),
      views: _int(row['views']),
      likes: _int(row['likes']),
      comments: _int(row['comments']),
    );
  }

  static CrossContentItem? _parseCrossContentItem(Map<String, dynamic> row) {
    final type = CrossContentType.fromWire(row['type'] as String?);
    final id = row['id']?.toString();
    if (type == null || id == null || id.isEmpty) return null;
    final title = row['title'] as String?;
    return CrossContentItem(
      id: id,
      type: type,
      title: title?.trim().isNotEmpty == true ? title! : 'Untitled',
      views: _int(row['views']),
      likes: _int(row['likes']),
      comments: _int(row['comments']),
    );
  }

  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — same unwrap `EdgeFunctionsService`/`MetaOAuthService` already
  /// use for every other edge function this app calls.
  Future<Map<String, dynamic>> _invoke(
    String function, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _supabase.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ??
          'Could not load audience insights. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  // -- Spec C helpers -------------------------------------------------------

  /// Sums `price` over rows whose `status` matches, using the portal's own parse.
  ///
  /// `properties.price` is TEXT -- free-form, so rows hold "95,00,000", "1.2 Cr",
  /// "Price on request". `BrokerAnalytics.tsx:88-95` handles it with
  /// `parseFloat(String(p.price).replace(/[^0-9.]/g, ''))`, and that is
  /// reproduced rather than improved: a stricter parse here would make the two
  /// platforms report different portfolio values for the same rows.
  ///
  /// The one behaviour worth naming: stripping every non-digit turns "1.2 Cr"
  /// into `1.2`, not 12000000, on **both** platforms. That is a portal bug,
  /// faithfully carried.
  double _sumPrices(List<Map<String, dynamic>> rows, String status) {
    var total = 0.0;
    for (final row in rows) {
      if (row['status'] != status) continue;
      final raw = row['price'];
      if (raw == null) continue;
      if (raw is num) {
        total += raw.toDouble();
        continue;
      }
      final digits = raw.toString().replaceAll(RegExp(r'[^0-9.]'), '');
      // JS parseFloat("") is NaN and the portal maps that to 0; Dart's tryParse
      // returns null, so `?? 0` lands on the same number.
      total += double.tryParse(digits) ?? 0;
    }
    return total;
  }

  /// `property_inquiries` row count across [propertyIds].
  ///
  /// `BrokerAnalytics.tsx:107-117`. Returns 0 for an empty id list rather than
  /// issuing `inFilter('property_id', [])`, which PostgREST answers with every
  /// row the caller can see -- the difference between "no listings, no
  /// inquiries" and "every inquiry in the table".
  Future<int> _countInquiries(List<String> propertyIds) async {
    if (propertyIds.isEmpty) return 0;
    final rows = await _supabase
        .from('property_inquiries')
        .select('id')
        .inFilter('property_id', propertyIds);
    return (rows as List).length;
  }

  /// The three broker lead metrics (`BrokerAudienceInsights.tsx:88-101`).
  Future<({int total, double conversionRate, double responseRate})>
  _fetchLeadMetrics(List<String> propertyIds) async {
    if (propertyIds.isEmpty) {
      return (total: 0, conversionRate: 0.0, responseRate: 0.0);
    }

    final rows = await _supabase
        .from('property_inquiries')
        .select('id, status')
        .inFilter('property_id', propertyIds);

    final inquiries = List<Map<String, dynamic>>.from(rows as List);
    final total = inquiries.length;
    if (total == 0) {
      return (total: 0, conversionRate: 0.0, responseRate: 0.0);
    }

    final closed = inquiries.where((i) => i['status'] == 'closed').length;
    // Three statuses count as "responded", not one (`:99`).
    final contacted = inquiries
        .where(
          (i) => const {
            'contacted',
            'scheduled',
            'approved',
          }.contains(i['status']),
        )
        .length;

    return (
      total: total,
      conversionRate: (closed / total) * 100,
      responseRate: (contacted / total) * 100,
    );
  }

  /// Mean watch duration and completion over every view of [videoIds].
  ///
  /// `InfluencerAnalytics.tsx:75-87`. Averaged over **view rows**, not over
  /// videos -- a video watched twice counts twice, which is what the portal does.
  Future<({double avgWatchTime, double avgCompletionRate})> _fetchWatchMetrics(
    List<String> videoIds,
  ) async {
    if (videoIds.isEmpty) {
      return (avgWatchTime: 0.0, avgCompletionRate: 0.0);
    }

    final rows = await _supabase
        .from('influencer_video_views')
        .select('watch_duration_seconds, watch_percentage')
        .inFilter('video_id', videoIds);

    final views = List<Map<String, dynamic>>.from(rows as List);
    if (views.isEmpty) {
      return (avgWatchTime: 0.0, avgCompletionRate: 0.0);
    }

    final duration = views.fold<double>(
      0,
      (sum, v) => sum + _double(v['watch_duration_seconds']),
    );
    final percentage = views.fold<double>(
      0,
      (sum, v) => sum + _double(v['watch_percentage']),
    );

    return (
      avgWatchTime: duration / views.length,
      avgCompletionRate: percentage / views.length,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _sum(List<Map<String, dynamic>> rows, String key) =>
      rows.fold<int>(0, (total, row) => total + _int(row[key]));

  /// `prev > 0 ? ((recent - prev) / prev) * 100 : 0` over the two trailing
  /// 7-day windows — React's analytics growth formula.
  double _growth(List<Map<String, dynamic>> rows, String key) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));

    var recent = 0;
    var previous = 0;

    for (final row in rows) {
      final created = _date(row['created_at']);
      if (created == null) continue;
      final value = _int(row[key]);

      if (!created.isBefore(sevenDaysAgo)) {
        recent += value;
      } else if (!created.isBefore(fourteenDaysAgo)) {
        previous += value;
      }
    }

    if (previous <= 0) return 0;
    return ((recent - previous) / previous) * 100;
  }

  /// Per-day totals for the trailing [days] window, oldest first.
  ///
  /// Same aggregation React performs — bucket content by its `created_at` day
  /// and sum the metric — with every day in the window present so the chart
  /// has a fixed number of points.
  List<ChartPoint> _dailySeries(
    List<Map<String, dynamic>> rows,
    String key,
    int days,
  ) {
    final today = DateTime.now();
    final buckets = <DateTime, double>{};

    for (var i = days - 1; i >= 0; i--) {
      final day = _dayOnly(today.subtract(Duration(days: i)));
      buckets[day] = 0;
    }

    for (final row in rows) {
      final created = _date(row['created_at']);
      if (created == null) continue;
      final day = _dayOnly(created);
      if (buckets.containsKey(day)) {
        buckets[day] = buckets[day]! + _int(row[key]);
      }
    }

    return buckets.entries
        .map((e) => ChartPoint(date: e.key, value: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 31 cumulative points, starting from the follower count that predates the
  /// window — React's `cumulative = totalFollowers - recentFollowers`.
  List<ChartPoint> _cumulativeFollowerSeries({
    required List<Map<String, dynamic>> followers,
    required int totalFollowers,
    required int recentCount,
    required DateTime now,
  }) {
    final perDay = <DateTime, int>{};
    for (var i = followerWindowDays; i >= 0; i--) {
      perDay[_dayOnly(now.subtract(Duration(days: i)))] = 0;
    }

    for (final follower in followers) {
      final created = _date(follower['created_at']);
      if (created == null) continue;
      final day = _dayOnly(created);
      if (perDay.containsKey(day)) perDay[day] = perDay[day]! + 1;
    }

    final days = perDay.keys.toList()..sort();
    var cumulative = (totalFollowers - recentCount).toDouble();

    return days.map((day) {
      cumulative += perDay[day]!;
      return ChartPoint(date: day, value: cumulative);
    }).toList();
  }

  static DateTime _dayOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// `watch_duration_seconds` and `watch_percentage` are numeric columns, so a
  /// row can hand back an int, a double or a string depending on the driver.
  static double _double(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _date(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is DateTime) return value;
    return null;
  }
}
