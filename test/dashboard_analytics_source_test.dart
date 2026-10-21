// Spec C — C-1 and C-2: the content source each role's analytics reads.
//
// What is pinned:
//
//   * `builder_projects` names its owner column `builder_id`, not `user_id`. The
//     shared service used to hard-code `user_id`, so this is the fact that makes
//     a third source possible at all;
//   * the builder reads `builder_projects`. It read `properties` until Spec C,
//     which a builder has no rows in — BuilderListingsBlock hides My Listings for
//     that exact reason — so both tabs rendered all zeros;
//   * the two pre-existing sources are unchanged, owner column included, because
//     every other role's numbers depend on that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/models/influencer_video_model.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/dashboard_analytics_provider.dart';
import 'package:propcid_app/screens/dashboard/builder_dashboard_screen.dart';
import 'package:propcid_app/services/dashboard_analytics_service.dart';

/// Records the arguments the provider hands the service, and replays fixtures.
class _RecordingService extends DashboardAnalyticsService {
  _RecordingService({
    this.analytics = DashboardAnalytics.empty,
    this.audience = DashboardAudience.empty,
  });

  final DashboardAnalytics analytics;
  final DashboardAudience audience;

  final List<({String userId, AnalyticsContentSource source, bool saved,
      bool growth, bool listings, bool watch})> analyticsCalls = [];
  final List<({String userId, AnalyticsContentSource source, bool leads})>
      audienceCalls = [];

  @override
  Future<DashboardAnalytics> fetchAnalytics({
    required String userId,
    required AnalyticsContentSource source,
    bool includeSavedProperties = false,
    bool growthFromContent = true,
    bool includeListingMetrics = false,
    bool includeWatchMetrics = false,
  }) async {
    analyticsCalls.add((
      userId: userId,
      source: source,
      saved: includeSavedProperties,
      growth: growthFromContent,
      listings: includeListingMetrics,
      watch: includeWatchMetrics,
    ));
    return analytics;
  }

  @override
  Future<DashboardAudience> fetchAudience({
    required String userId,
    required AnalyticsContentSource source,
    bool includeLeadMetrics = false,
  }) async {
    audienceCalls.add((
      userId: userId,
      source: source,
      leads: includeLeadMetrics,
    ));
    return audience;
  }
}

class _FakeAuth extends AuthProvider {
  @override
  String? get userId => 'b-1';

  @override
  bool get isLoggedIn => true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // ── C-1. The enum ───────────────────────────────────────────────────────
  group('AnalyticsContentSource', () {
    test('every value names its table', () {
      expect(AnalyticsContentSource.properties.table, 'properties');
      expect(
        AnalyticsContentSource.influencerVideos.table,
        'influencer_videos',
      );
      expect(
        AnalyticsContentSource.builderProjects.table,
        'builder_projects',
      );
    });

    test('builder_projects owns rows by builder_id, not user_id', () {
      // The whole reason ownerColumn exists. `.eq('user_id', …)` against
      // builder_projects is a 42703 undefined_column, not a silent zero.
      expect(
        AnalyticsContentSource.builderProjects.ownerColumn,
        'builder_id',
      );
    });

    test('the two pre-existing sources still use user_id', () {
      // C-1 must not change any existing role's query.
      expect(AnalyticsContentSource.properties.ownerColumn, 'user_id');
      expect(
        AnalyticsContentSource.influencerVideos.ownerColumn,
        'user_id',
      );
    });

    // ── The Spec C regression ─────────────────────────────────────────────
    //
    // Spec C selected `id, title, views, likes, created_at, status, price` for
    // EVERY source. Only `properties` has a `price` column, so that query was a
    // `42703 undefined_column` against `builder_projects` and `influencer_videos`
    // — the Analytics tab failed outright for builders and influencers, showing
    // "Couldn't load analytics".
    //
    // These assert the column list per source, which is the layer the original
    // Spec C tests never reached: their fake overrode `fetchAnalytics` wholesale,
    // so no test ever saw the SQL.
    test('only properties has a price column', () {
      expect(AnalyticsContentSource.properties.hasPriceColumn, isTrue);
      expect(AnalyticsContentSource.builderProjects.hasPriceColumn, isFalse);
      expect(AnalyticsContentSource.influencerVideos.hasPriceColumn, isFalse);
    });

    test('price is selected for properties and nowhere else', () {
      expect(
        AnalyticsContentSource.properties.analyticsColumns,
        contains('price'),
      );
      // `builder_projects` prices a range — price_range_min / price_range_max —
      // and `influencer_videos` has no notion of price at all.
      expect(
        AnalyticsContentSource.builderProjects.analyticsColumns,
        isNot(contains('price')),
      );
      expect(
        AnalyticsContentSource.influencerVideos.analyticsColumns,
        isNot(contains('price')),
      );
    });

    test('every source selects the columns the shared folds need', () {
      // `status` is declared by all three, so it stays in the common list even
      // though only the broker branch reads it.
      for (final source in AnalyticsContentSource.values) {
        final columns = source.analyticsColumns;
        for (final column in ['id', 'title', 'views', 'likes', 'created_at',
                              'status']) {
          expect(columns, contains(column), reason: '${source.name}.$column');
        }
      }
    });

    test('no source selects a column its own model does not declare', () {
      // The models are the schema of record for these two tables, so a column in the
      // analytics select that is absent from the model is the 42703 waiting to
      // happen.
      //
      // Compared as EXACT TOKENS, not substrings, and that distinction is the whole
      // test: `'price_range_min'.contains('price')` is **true**, so a substring
      // check would have passed against the very bug this guards — the model
      // declares `price_range_min`, the select asked for `price`, and a
      // `contains` would have called that a match.
      Set<String> tokens(String columns) =>
          columns.split(',').map((c) => c.trim()).toSet();

      final declared = {
        AnalyticsContentSource.builderProjects: tokens(ProjectModel.columns),
        AnalyticsContentSource.influencerVideos:
            tokens(InfluencerVideoModel.columns),
      };

      for (final entry in declared.entries) {
        for (final column in tokens(entry.key.analyticsColumns)) {
          expect(
            entry.value.contains(column),
            isTrue,
            reason: '${entry.key.name} selects "$column" but its model does '
                'not declare it',
          );
        }
      }
    });

    test('there are exactly three sources', () {
      // A fourth would need its own ownerColumn case; the switch is exhaustive,
      // so this is a reminder rather than a guard.
      expect(AnalyticsContentSource.values, hasLength(3));
    });
  });

  // ── C-2. The builder screen asks for the right table ────────────────────
  group('BuilderDashboardScreen', () {
    testWidgets('requests builder_projects for both tabs', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The screen creates its own DashboardAnalyticsProvider in build(), so it
      // is read back from a descendant context rather than injected. Its own
      // BuilderDashboardService call fails against the loopback client and lands
      // in the error state, which is fine — the provider is built either way and
      // the source is decided at construction.
      DashboardAnalyticsProvider? captured;

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: _FakeAuth(),
          child: MaterialApp(
            home: Builder(
              builder: (_) => const BuilderDashboardScreen(),
            ),
            builder: (context, child) => child!,
          ),
        ),
      );
      await tester.pump();

      captured = Provider.of<DashboardAnalyticsProvider>(
        tester.element(find.byType(Scaffold).first),
        listen: false,
      );

      expect(
        captured.analyticsSource,
        AnalyticsContentSource.builderProjects,
        reason: 'a builder owns builder_projects rows, not properties rows',
      );
      expect(
        captured.audienceSource,
        AnalyticsContentSource.builderProjects,
      );
    });
  });

  // ── The provider passes the source straight through ─────────────────────
  group('DashboardAnalyticsProvider', () {
    test('a builder provider asks the service for builder_projects', () async {
      final service = _RecordingService();
      final provider = DashboardAnalyticsProvider(
        analyticsSource: AnalyticsContentSource.builderProjects,
        audienceSource: AnalyticsContentSource.builderProjects,
        service: service,
      );
      addTearDown(provider.dispose);

      await provider.load('b-1');

      expect(service.analyticsCalls.single.source,
          AnalyticsContentSource.builderProjects);
      expect(service.audienceCalls.single.source,
          AnalyticsContentSource.builderProjects);
      expect(service.analyticsCalls.single.userId, 'b-1');
    });

    test('builder analytics and audience populate from project rows', () async {
      // The regression this closes: every one of these was 0 before C-2 because
      // the query filtered `properties` by a builder's id.
      final service = _RecordingService(
        analytics: const DashboardAnalytics(
          totalViews: 4200,
          totalLikes: 310,
          avgEngagement: 7.38,
          totalInteractions: 4510,
          contentPosted: 6,
          topContent: [
            TopContentItem(
              id: 'p-1',
              title: 'Green Valley Heights',
              views: 1800,
              likes: 140,
            ),
          ],
        ),
        audience: const DashboardAudience(
          totalFollowers: 88,
          followersGrowth: 12.5,
          totalViews: 4200,
          avgViewsPerPost: 700,
          engagementRate: 7.38,
        ),
      );
      final provider = DashboardAnalyticsProvider(
        analyticsSource: AnalyticsContentSource.builderProjects,
        audienceSource: AnalyticsContentSource.builderProjects,
        service: service,
      );
      addTearDown(provider.dispose);

      await provider.load('b-1');

      expect(provider.analyticsLoading, isFalse);
      expect(provider.analyticsFailed, isFalse);
      expect(provider.analytics.totalViews, 4200);
      expect(provider.analytics.contentPosted, 6);
      expect(provider.analytics.topContent.single.title,
          'Green Valley Heights');

      expect(provider.audienceLoading, isFalse);
      expect(provider.audience.totalFollowers, 88);
      expect(provider.audience.avgViewsPerPost, 700);
    });

    test('a builder does not query saved_properties or fake its growth',
        () async {
      // Only the Individual variant reads saved_properties, and only the broker
      // hard-codes growth to 0. The builder does neither.
      final service = _RecordingService();
      final provider = DashboardAnalyticsProvider(
        analyticsSource: AnalyticsContentSource.builderProjects,
        audienceSource: AnalyticsContentSource.builderProjects,
        service: service,
      );
      addTearDown(provider.dispose);

      await provider.load('b-1');

      expect(service.analyticsCalls.single.saved, isFalse);
      expect(service.analyticsCalls.single.growth, isTrue);
    });

    test('the other roles still ask for their own tables', () async {
      for (final source in [
        AnalyticsContentSource.properties,
        AnalyticsContentSource.influencerVideos,
      ]) {
        final service = _RecordingService();
        final provider = DashboardAnalyticsProvider(
          analyticsSource: source,
          audienceSource: source,
          service: service,
        );
        await provider.load('u-1');
        expect(service.analyticsCalls.single.source, source);
        provider.dispose();
      }
    });
  });
}
