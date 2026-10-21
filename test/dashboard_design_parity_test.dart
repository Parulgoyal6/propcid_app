// Locks the Manage Dashboard against the approved mobile design: the six
// Analytics tiles, the four Audience tiles, both chart headers, the insight
// rows, the top-content row shape and the Content Manager empty state — with
// the design's own sample values. A regression here means the screen drifted
// from the design, which is exactly what this rebuild set out to fix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/widgets/shared/app_chart_wrapper.dart';
import 'package:propcid_app/screens/dashboard/widgets/dashboard_tab_bodies.dart';

List<ChartPoint> series(List<double> v) {
  final base = DateTime(2026, 8, 3);
  return [
    for (var i = 0; i < v.length; i++)
      ChartPoint(date: base.subtract(Duration(days: v.length - 1 - i)), value: v[i]),
  ];
}

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );

void main() {
  test('formatThousands matches the design', () {
    expect(formatThousands(1240), '1,240');
    expect(formatThousands(2300), '2,300');
    expect(formatThousands(89), '89');
    expect(formatThousands(0), '0');
    expect(formatThousands(1234567), '1,234,567');
  });

  testWidgets('chart paints the prototype series', (t) async {
    await t.pumpWidget(host(DashboardLineChart(
      points: series([420, 610, 540, 700, 860, 780, 1240]),
      height: 120,
      showDayLabels: true,
    )));
    expect(find.byType(CustomPaint), findsWidgets);
    // Seven weekday labels, as the design shows.
    for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(d), findsWidgets, reason: d);
    }
  });

  testWidgets('chart shows an honest empty state for a flat series', (t) async {
    await t.pumpWidget(host(DashboardLineChart(
      points: series([0, 0, 0, 0, 0, 0, 0]),
      emptyMessage: 'No performance data yet',
    )));
    expect(find.text('No performance data yet'), findsOneWidget);
  });

  testWidgets('analytics body renders all six design tiles', (t) async {
    await t.pumpWidget(host(DashboardAnalyticsBody(
      analytics: DashboardAnalytics(
        totalViews: 1240, totalLikes: 89, totalSaved: 34,
        avgEngagement: 6.2, totalInteractions: 156, contentPosted: 3,
        topContent: const [
          TopContentItem(id: '1', title: 'Luxury Villa in Dehradun', views: 412, likes: 38),
          TopContentItem(id: '2', title: 'Modern Apartment', views: 298, likes: 21),
        ],
        performance: series([420, 610, 540, 700, 860, 780, 1240]),
      ),
      loading: false, failed: false, onRetry: () {},
    )));
    await t.pumpAndSettle();

    for (final s in ['1,240', 'Total Views', '89', 'Total Likes', '34',
      'Saved Properties', '6.2%', 'Avg Engagement', '156', 'Total Interactions',
      '3', 'Content Posted', 'Performance Over Time', 'TOP PERFORMING CONTENT',
      'Luxury Villa in Dehradun', '412', '38', 'Modern Apartment']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
  });

  testWidgets('audience body renders the design tiles and insights', (t) async {
    await t.pumpWidget(host(DashboardAudienceBody(
      audience: DashboardAudience(
        totalFollowers: 2300, totalViews: 540, avgViewsPerPost: 180,
        engagementRate: 6.2, followersGrowth: 12,
        followerGrowth: series([1900, 1980, 2050, 2120, 2180, 2240, 2300]),
      ),
      loading: false, failed: false, onRetry: () {},
    )));
    await t.pumpAndSettle();

    for (final s in ['2,300', 'Total Followers', '540', '180', 'Avg Views/Post',
      '6.2%', 'Engagement Rate', 'Follower Growth', 'AUDIENCE INSIGHTS',
      'Avg Engagement', '+12%', 'Total Reach', 'Audience Size']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
  });

  testWidgets('content body shows the design empty state', (t) async {
    await t.pumpWidget(host(DashboardContentBody(
      onCreate: () {}, isEmpty: true, sections: const [],
    )));
    await t.pumpAndSettle();
    expect(find.text('Content Library'), findsOneWidget);
    expect(find.text('Create Post'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('Start creating content to build your presence'), findsOneWidget);
    expect(find.text('Create Your First Post'), findsOneWidget);
  });
}
