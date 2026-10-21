// Feature 1 — cross-content Audience Insights, provider orchestration.
//
// `DashboardAnalyticsService.fetchCrossContentInsights`'s own parsing
// contract is pinned in `cross_content_insights_parsing_test.dart`. This
// file pins `DashboardAnalyticsProvider`'s wiring around it: the fetch only
// runs when `includeCrossContentInsights` is set, it has its own independent
// loading/failure state so it never blanks the base audience metrics (or
// vice versa), a merge race in either direction still ends with both halves
// present, and `retryCrossContentInsights` retries only that section.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/providers/dashboard_analytics_provider.dart';
import 'package:propcid_app/services/dashboard_analytics_service.dart';

class _FakeService extends DashboardAnalyticsService {
  _FakeService({
    this.audience = DashboardAudience.empty,
    this.crossContent = CrossContentInsights.empty,
    this.failAudience = false,
    this.failCrossContent = false,
    this.audienceDelay = Duration.zero,
    this.crossContentDelay = Duration.zero,
  });

  DashboardAudience audience;
  CrossContentInsights crossContent;
  bool failAudience;
  bool failCrossContent;
  Duration audienceDelay;
  Duration crossContentDelay;

  int audienceCalls = 0;
  int crossContentCalls = 0;
  String? lastFunctionName;

  @override
  Future<DashboardAnalytics> fetchAnalytics({
    required String userId,
    required AnalyticsContentSource source,
    bool includeSavedProperties = false,
    bool growthFromContent = true,
    bool includeListingMetrics = false,
    bool includeWatchMetrics = false,
  }) async => DashboardAnalytics.empty;

  @override
  Future<DashboardAudience> fetchAudience({
    required String userId,
    required AnalyticsContentSource source,
    bool includeLeadMetrics = false,
  }) async {
    audienceCalls++;
    if (audienceDelay > Duration.zero) await Future.delayed(audienceDelay);
    if (failAudience) throw StateError('audience fetch failed');
    return audience;
  }

  @override
  Future<CrossContentInsights> fetchCrossContentInsights({
    String functionName = 'influencer-audience-insights',
  }) async {
    crossContentCalls++;
    lastFunctionName = functionName;
    if (crossContentDelay > Duration.zero) {
      await Future.delayed(crossContentDelay);
    }
    if (failCrossContent) throw StateError('cross-content fetch failed');
    return crossContent;
  }
}

DashboardAnalyticsProvider _newProvider(
  _FakeService service, {
  bool includeCrossContentInsights = true,
  String crossContentFunction = 'influencer-audience-insights',
}) {
  return DashboardAnalyticsProvider(
    analyticsSource: AnalyticsContentSource.influencerVideos,
    audienceSource: AnalyticsContentSource.influencerVideos,
    includeCrossContentInsights: includeCrossContentInsights,
    crossContentFunction: crossContentFunction,
    service: service,
  );
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

  test('off by default — no other role\'s dashboard is affected', () async {
    final service = _FakeService();
    final provider = _newProvider(service, includeCrossContentInsights: false);
    addTearDown(provider.dispose);

    await provider.load('u-1');

    expect(service.crossContentCalls, 0);
    expect(provider.audience.crossContent, isNull);
    expect(provider.crossContentLoading, isFalse);
    expect(provider.crossContentFailed, isFalse);
  });

  test(
    'defaults to influencer\'s edge function when the caller does not '
    'override crossContentFunction',
    () async {
      final service = _FakeService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(service.lastFunctionName, 'influencer-audience-insights');
    },
  );

  test(
    'passes crossContentFunction through — the builder dashboard uses this '
    'to call builder-audience-insights instead',
    () async {
      final service = _FakeService();
      final provider = _newProvider(
        service,
        crossContentFunction: 'builder-audience-insights',
      );
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(service.lastFunctionName, 'builder-audience-insights');
    },
  );

  test(
    'when enabled, merges into the same audience the base fetch loaded',
    () async {
      final service = _FakeService(
        audience: const DashboardAudience(totalFollowers: 42),
        crossContent: const CrossContentInsights(totalViews: 900),
      );
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.audience.totalFollowers, 42);
      expect(provider.audience.crossContent?.totalViews, 900);
    },
  );

  test(
    'a cross-content failure never blanks the base audience metrics',
    () async {
      final service = _FakeService(
        audience: const DashboardAudience(totalFollowers: 42),
        failCrossContent: true,
      );
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.audienceFailed, isFalse);
      expect(provider.audience.totalFollowers, 42);
      expect(provider.crossContentFailed, isTrue);
      expect(provider.audience.crossContent, isNull);
    },
  );

  test(
    'a base-audience failure never discards a cross-content result that already loaded',
    () async {
      // Cross-content resolves first, then the base fetch fails and would
      // otherwise reset `_audience` to `.empty` wholesale.
      final service = _FakeService(
        failAudience: true,
        crossContent: const CrossContentInsights(totalViews: 900),
        crossContentDelay: Duration.zero,
        audienceDelay: const Duration(milliseconds: 10),
      );
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.audienceFailed, isTrue);
      expect(provider.audience.totalFollowers, 0, reason: 'base metrics reset');
      expect(
        provider.audience.crossContent?.totalViews,
        900,
        reason: 'but the section that actually succeeded survives',
      );
    },
  );

  test('merges correctly regardless of which fetch resolves first', () async {
    final crossContentFirst = _FakeService(
      audience: const DashboardAudience(totalFollowers: 5),
      crossContent: const CrossContentInsights(totalViews: 10),
      audienceDelay: const Duration(milliseconds: 15),
    );
    final providerA = _newProvider(crossContentFirst);
    addTearDown(providerA.dispose);
    await providerA.load('u-1');
    expect(providerA.audience.totalFollowers, 5);
    expect(providerA.audience.crossContent?.totalViews, 10);

    final audienceFirst = _FakeService(
      audience: const DashboardAudience(totalFollowers: 7),
      crossContent: const CrossContentInsights(totalViews: 20),
      crossContentDelay: const Duration(milliseconds: 15),
    );
    final providerB = _newProvider(audienceFirst);
    addTearDown(providerB.dispose);
    await providerB.load('u-1');
    expect(providerB.audience.totalFollowers, 7);
    expect(providerB.audience.crossContent?.totalViews, 20);
  });

  test('retryCrossContentInsights only refetches that section', () async {
    final service = _FakeService(
      audience: const DashboardAudience(totalFollowers: 42),
      failCrossContent: true,
    );
    final provider = _newProvider(service);
    addTearDown(provider.dispose);
    await provider.load('u-1');
    expect(provider.crossContentFailed, isTrue);
    expect(service.audienceCalls, 1);

    service.failCrossContent = false;
    service.crossContent = const CrossContentInsights(totalViews: 900);
    await provider.retryCrossContentInsights();

    expect(provider.crossContentFailed, isFalse);
    expect(provider.audience.crossContent?.totalViews, 900);
    // The base audience metrics were not refetched by this retry.
    expect(service.audienceCalls, 1);
    expect(provider.audience.totalFollowers, 42);
  });

  test('retryCrossContentInsights is a no-op when the flag is off', () async {
    final service = _FakeService();
    final provider = _newProvider(service, includeCrossContentInsights: false);
    addTearDown(provider.dispose);
    await provider.load('u-1');

    await provider.retryCrossContentInsights();

    expect(service.crossContentCalls, 0);
  });

  test('loading state is true only while the fetch is in flight', () async {
    final service = _FakeService(
      crossContentDelay: const Duration(milliseconds: 20),
    );
    final provider = _newProvider(service);
    addTearDown(provider.dispose);

    final future = provider.load('u-1');
    expect(provider.crossContentLoading, isTrue);
    await future;
    expect(provider.crossContentLoading, isFalse);
  });
}
