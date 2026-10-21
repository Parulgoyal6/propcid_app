// Regression gate for the Manage Dashboard rebuild.
//
// Verifies the rebuilt presentation layer against the two things that can only
// be proven at runtime: that it lays out without overflow on the smallest
// devices the app ships to, and that every tab state (loading / empty /
// populated / failed) renders. Uses the repo's own geometry-based
// `overflowingBoxes` harness rather than `takeException()`, which misses
// hatched overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/providers/dashboard_analytics_provider.dart';
import 'package:propcid_app/screens/dashboard/widgets/dashboard_tab_bodies.dart';
import 'package:propcid_app/widgets/shared/section_header_back_button.dart';
import 'package:propcid_app/screens/dashboard/widgets/dashboard_tab_selector.dart';

import 'support/overflow_detector.dart';

/// Smallest viewports the app realistically runs on.
const _devices = <String, Size>{
  'iPhone SE (320x568)': Size(320, 568),
  'small Android (360x640)': Size(360, 640),
  'iPhone 12 (390x844)': Size(390, 844),
};

List<ChartPoint> _series(List<double> values) {
  final base = DateTime(2026, 8, 3);
  return [
    for (var i = 0; i < values.length; i++)
      ChartPoint(
        date: base.subtract(Duration(days: values.length - 1 - i)),
        value: values[i],
      ),
  ];
}

final _populatedAnalytics = DashboardAnalytics(
  totalViews: 1240,
  totalLikes: 89,
  totalSaved: 34,
  avgEngagement: 6.2,
  totalInteractions: 156,
  contentPosted: 3,
  topContent: const [
    TopContentItem(
      id: '1',
      title: 'Luxury Villa in Dehradun with a deliberately long title',
      views: 412,
      likes: 38,
    ),
    TopContentItem(id: '2', title: 'Modern Apartment', views: 298, likes: 21),
  ],
  performance: _series([420, 610, 540, 700, 860, 780, 1240]),
);

final _populatedAudience = DashboardAudience(
  totalFollowers: 2300,
  followersGrowth: 12,
  totalViews: 540,
  avgViewsPerPost: 180,
  engagementRate: 6.2,
  followerGrowth: _series([1900, 1980, 2050, 2120, 2180, 2240, 2300]),
);

/// Mirrors each dashboard's real shell: scroll view, 20 dp side padding,
/// header and tab selector above the body.
Future<void> _pumpShell(
  WidgetTester tester,
  Size size,
  Widget body, {
  DashboardTab tab = DashboardTab.analytics,
  /// The shimmer placeholder animates indefinitely, so `pumpAndSettle` would
  /// never return for loading states — pump a single frame instead.
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DashboardHeaderBar(
                      title: 'Manage Dashboard',
                      subtitle: 'Manage your content and track performance',
                    ),
                    const SizedBox(height: 18),
                    DashboardTabSelector(selected: tab, onChanged: (_) {}),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: body,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('no overflow on small devices', () {
    _devices.forEach((label, size) {
      testWidgets('analytics populated — $label', (tester) async {
        await _pumpShell(
          tester,
          size,
          DashboardAnalyticsBody(
            analytics: _populatedAnalytics,
            loading: false,
            failed: false,
            onRetry: () {},
          ),
        );
        expect(overflowingBoxes(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('analytics empty — $label', (tester) async {
        await _pumpShell(
          tester,
          size,
          DashboardAnalyticsBody(
            analytics: DashboardAnalytics.empty,
            loading: false,
            failed: false,
            onRetry: () {},
          ),
        );
        expect(overflowingBoxes(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('audience populated — $label', (tester) async {
        await _pumpShell(
          tester,
          size,
          DashboardAudienceBody(
            audience: _populatedAudience,
            loading: false,
            failed: false,
            onRetry: () {},
          ),
          tab: DashboardTab.audience,
        );
        expect(overflowingBoxes(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('content empty state — $label', (tester) async {
        await _pumpShell(
          tester,
          size,
          DashboardContentBody(
            onCreate: () {},
            isEmpty: true,
            sections: const [],
          ),
          tab: DashboardTab.content,
        );
        expect(overflowingBoxes(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('content with sections — $label', (tester) async {
        await _pumpShell(
          tester,
          size,
          DashboardContentBody(
            onCreate: () {},
            sections: const [
              SizedBox(height: 120, child: Placeholder()),
              SizedBox(height: 200, child: Placeholder()),
            ],
          ),
          tab: DashboardTab.content,
        );
        expect(overflowingBoxes(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('every state renders', () {
    testWidgets('loading shows shimmer placeholders, not zeros', (tester) async {
      await _pumpShell(
        tester,
        const Size(390, 844),
        DashboardAnalyticsBody(
          analytics: DashboardAnalytics.empty,
          loading: true,
          failed: false,
          onRetry: () {},
        ),
        settle: false,
      );
      // A bare "0" during load would read as a real (wrong) answer.
      expect(find.text('Total Views'), findsNothing);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('failed shows a retry that fires', (tester) async {
      var retried = false;
      await _pumpShell(
        tester,
        const Size(390, 844),
        DashboardAnalyticsBody(
          analytics: DashboardAnalytics.empty,
          loading: false,
          failed: true,
          onRetry: () => retried = true,
        ),
      );
      expect(find.text("Couldn't load analytics"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('empty analytics keeps the design layout, not a blank page',
        (tester) async {
      await _pumpShell(
        tester,
        const Size(390, 844),
        DashboardAnalyticsBody(
          analytics: DashboardAnalytics.empty,
          loading: false,
          failed: false,
          onRetry: () {},
        ),
      );
      // All six tiles still present, showing honest zeros.
      for (final label in [
        'Total Views',
        'Total Likes',
        'Saved Properties',
        'Avg Engagement',
        'Total Interactions',
        'Content Posted',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Performance Over Time'), findsOneWidget);
      expect(find.text('No performance data yet'), findsOneWidget);
      expect(find.text('No content yet'), findsOneWidget);
    });
  });

  group('tab switching', () {
    testWidgets('all three tabs select and report back', (tester) async {
      final selected = <DashboardTab>[];
      var current = DashboardTab.analytics;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Padding(
                padding: const EdgeInsets.all(20),
                child: DashboardTabSelector(
                  selected: current,
                  onChanged: (t) {
                    selected.add(t);
                    setState(() => current = t);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Content Manager'), findsOneWidget);
      expect(find.text('Audience'), findsOneWidget);

      await tester.tap(find.text('Content Manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audience'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      expect(selected, [
        DashboardTab.content,
        DashboardTab.audience,
        DashboardTab.analytics,
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  group('provider lifecycle', () {
    test('dispose is safe and late notifications do not throw', () async {
      final provider = DashboardAnalyticsProvider(
        analyticsSource: AnalyticsContentSource.properties,
        audienceSource: AnalyticsContentSource.properties,
      );

      var notified = 0;
      provider.addListener(() => notified++);

      provider.dispose();

      // refresh() with no prior load() must be a no-op rather than touching a
      // disposed notifier — this is what guards the post-dispose async gap.
      await provider.refresh();
      expect(notified, 0);
    });

    test('starts in a loading state with zeroed models', () {
      final provider = DashboardAnalyticsProvider(
        analyticsSource: AnalyticsContentSource.influencerVideos,
        audienceSource: AnalyticsContentSource.influencerVideos,
      );
      addTearDown(provider.dispose);

      expect(provider.analyticsLoading, isTrue);
      expect(provider.audienceLoading, isTrue);
      expect(provider.analyticsFailed, isFalse);
      expect(provider.analytics.totalViews, 0);
      expect(provider.audience.totalFollowers, 0);
    });
  });
}
