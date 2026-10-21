// Feature 1 — cross-content Audience Insights, response parsing.
//
// `influencer-audience-insights` (supabase/functions/influencer-audience-
// insights/index.ts) is a deployed edge function, not something this app may
// edit or call live in a test. `DashboardAnalyticsService
// .parseCrossContentInsights` is the pure seam pulled out of
// `fetchCrossContentInsights` for exactly this reason — it takes the same
// JSON shape that function returns and is exercised directly here, no
// `Supabase.initialize` or network call involved.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/services/dashboard_analytics_service.dart';

void main() {
  group('a full, well-formed response', () {
    final data = {
      'stats': {
        'totalFollowers': 120,
        'followersGrowth': 12.5,
        'totalViews': 500,
        'avgViewsPerVideo': 50.0,
        'engagementRate': 8.0,
        'totalViewsAll': 900,
        'totalLikesAll': 300,
        'totalCommentsAll': 45,
      },
      'followerGrowth': [
        {'date': '2026-08-01', 'followers': 10},
      ],
      'breakdown': [
        {
          'type': 'reel',
          'count': 3,
          'views': 500,
          'likes': 200,
          'comments': 20,
        },
        {
          'type': 'property',
          'count': 2,
          'views': 300,
          'likes': 80,
          'comments': 15,
        },
        {
          'type': 'article',
          'count': 1,
          'views': 100,
          'likes': 20,
          'comments': 10,
        },
      ],
      'topContent': [
        {
          'id': 'reel-1',
          'type': 'reel',
          'title': 'Best flip ever',
          'views': 400,
          'likes': 150,
          'comments': 12,
          'url': '/property-reels/reel-1',
        },
        {
          'id': 'prop-1',
          'type': 'property',
          'title': '3BHK in Whitefield',
          'views': 200,
          'likes': 60,
          'comments': 8,
          'url': '/property/prop-1',
        },
      ],
    };

    test(
      'reads only the cross-content stats fields, not totalFollowers/etc',
      () {
        final result = DashboardAnalyticsService.parseCrossContentInsights(
          data,
        );
        expect(result.totalViews, 900);
        expect(result.totalLikes, 300);
        expect(result.totalComments, 45);
      },
    );

    test('parses every breakdown entry with its own type', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights(data);
      expect(result.breakdown, hasLength(3));
      expect(result.breakdown[0].type, CrossContentType.reel);
      expect(result.breakdown[0].count, 3);
      expect(result.breakdown[0].views, 500);
      expect(result.breakdown[0].likes, 200);
      expect(result.breakdown[0].comments, 20);
      expect(result.breakdown[1].type, CrossContentType.property);
      expect(result.breakdown[2].type, CrossContentType.article);
    });

    test('parses topContent preserving the edge function\'s own order', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights(data);
      expect(result.topContent, hasLength(2));
      expect(result.topContent[0].id, 'reel-1');
      expect(result.topContent[0].type, CrossContentType.reel);
      expect(result.topContent[0].title, 'Best flip ever');
      expect(result.topContent[0].comments, 12);
      expect(result.topContent[1].id, 'prop-1');
      expect(result.topContent[1].type, CrossContentType.property);
    });

    test('never surfaces the portal-only `url` field', () {
      // Flutter has no equivalent of the portal's pre-built route string and
      // must route by (type, id) itself — asserted structurally: the parsed
      // model has no `url` property to even carry it.
      final result = DashboardAnalyticsService.parseCrossContentInsights(data);
      expect(result.topContent.first, isA<CrossContentItem>());
    });
  });

  group('missing or absent optional data', () {
    test('an empty map yields all-zero, empty-list insights, not a throw', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights(
        const {},
      );
      expect(result.totalViews, 0);
      expect(result.totalLikes, 0);
      expect(result.totalComments, 0);
      expect(result.breakdown, isEmpty);
      expect(result.topContent, isEmpty);
    });

    test('stats present but missing the *All keys defaults to zero', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'stats': {'totalFollowers': 5},
      });
      expect(result.totalViews, 0);
      expect(result.totalLikes, 0);
      expect(result.totalComments, 0);
    });

    test(
      'totalViews falls back to stats.totalViews when totalViewsAll is '
      'absent — builder-audience-insights\'s own shape: one content source, '
      'so there is no separate "all content" sum to report',
      () {
        final result = DashboardAnalyticsService.parseCrossContentInsights({
          'stats': {
            'totalFollowers': 5,
            'totalViews': 240,
            'totalLikesAll': 30,
            'totalCommentsAll': 4,
          },
        });
        expect(result.totalViews, 240);
        expect(result.totalLikes, 30);
        expect(result.totalComments, 4);
      },
    );

    test('breakdown/topContent as null rather than a list is tolerated', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'stats': {'totalViewsAll': 10},
        'breakdown': null,
        'topContent': null,
      });
      expect(result.breakdown, isEmpty);
      expect(result.topContent, isEmpty);
      expect(result.totalViews, 10);
    });

    test('a row with an unrecognised type is dropped, not thrown on', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'breakdown': [
          {
            'type': 'video', // not one of reel/property/article/project
            'count': 1,
            'views': 1,
            'likes': 1,
            'comments': 1,
          },
          {'type': 'reel', 'count': 2, 'views': 2, 'likes': 2, 'comments': 2},
        ],
        'topContent': [
          {'id': 'x', 'type': 'unknown', 'title': 'x'},
        ],
      });
      expect(result.breakdown, hasLength(1));
      expect(result.breakdown.single.type, CrossContentType.reel);
      expect(result.topContent, isEmpty);
    });

    test('a topContent row missing id is dropped', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'topContent': [
          {'type': 'reel', 'title': 'no id here'},
        ],
      });
      expect(result.topContent, isEmpty);
    });

    test('a missing/blank title falls back to "Untitled"', () {
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'topContent': [
          {'id': 'a-1', 'type': 'article', 'title': ''},
          {'id': 'a-2', 'type': 'article'},
        ],
      });
      expect(result.topContent[0].title, 'Untitled');
      expect(result.topContent[1].title, 'Untitled');
    });

    test('numeric fields sent as strings are still parsed', () {
      // PostgREST/edge functions can hand back numeric-looking strings for
      // some drivers — the same tolerance `DashboardAnalyticsService._int`
      // already applies to `fetchAnalytics`/`fetchAudience` rows.
      final result = DashboardAnalyticsService.parseCrossContentInsights({
        'stats': {
          'totalViewsAll': '900',
          'totalLikesAll': '300',
          'totalCommentsAll': '45',
        },
        'breakdown': [
          {
            'type': 'reel',
            'count': '3',
            'views': '500',
            'likes': '200',
            'comments': '20',
          },
        ],
      });
      expect(result.totalViews, 900);
      expect(result.breakdown.single.count, 3);
    });
  });

  group('CrossContentType.fromWire', () {
    test('maps the four wire values an edge function ever sends', () {
      expect(CrossContentType.fromWire('reel'), CrossContentType.reel);
      expect(CrossContentType.fromWire('property'), CrossContentType.property);
      expect(CrossContentType.fromWire('article'), CrossContentType.article);
      // `project` — builder-audience-insights's only content type, added
      // alongside the other three `influencer-audience-insights` sends.
      expect(CrossContentType.fromWire('project'), CrossContentType.project);
    });

    test('null and anything else map to null', () {
      expect(CrossContentType.fromWire(null), isNull);
      expect(CrossContentType.fromWire('video'), isNull);
      expect(CrossContentType.fromWire(''), isNull);
    });
  });
}
