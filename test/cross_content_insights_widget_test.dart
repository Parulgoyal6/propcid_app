// Feature 1 — cross-content Audience Insights, widget states.
//
// `DashboardAudienceBody`'s cross-content section is additive and defaults
// to invisible (`crossContentLoading`/`crossContentFailed` false,
// `audience.crossContent` null) so every existing caller — broker, builder,
// individual — renders exactly as `dashboard_design_parity_test.dart` /
// `dashboard_role_metrics_test.dart` already pin. This file exercises the
// section itself: loading, failure + retry, the empty state, populated data
// (Total Reach/Likes/Comments, Content Breakdown, Most Liked Content), and
// that a "Most Liked Content" tap reports the right item back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/screens/dashboard/widgets/dashboard_tab_bodies.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  ),
);

DashboardAudienceBody _body({
  DashboardAudience audience = DashboardAudience.empty,
  bool crossContentLoading = false,
  bool crossContentFailed = false,
  VoidCallback? onCrossContentRetry,
  ValueChanged<CrossContentItem>? onContentTap,
}) => DashboardAudienceBody(
  audience: audience,
  loading: false,
  failed: false,
  onRetry: () {},
  crossContentLoading: crossContentLoading,
  crossContentFailed: crossContentFailed,
  onCrossContentRetry: onCrossContentRetry,
  onContentTap: onContentTap,
);

void main() {
  testWidgets(
    'invisible by default — a non-influencer dashboard sees no new section',
    (tester) async {
      await tester.pumpWidget(_host(_body()));
      await tester.pumpAndSettle();

      expect(find.text('REACH ACROSS ALL CONTENT'), findsNothing);
      expect(find.text('Content Breakdown'), findsNothing);
      expect(find.text('MOST LIKED CONTENT'), findsNothing);
    },
  );

  testWidgets('shows a shimmer while loading, not zeros', (tester) async {
    await tester.pumpWidget(_host(_body(crossContentLoading: true)));
    await tester.pump();

    expect(find.text('REACH ACROSS ALL CONTENT'), findsOneWidget);
    expect(find.text('Reach (All Content)'), findsNothing);
  });

  testWidgets('a failure shows retry and it fires', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _host(
        _body(
          crossContentFailed: true,
          onCrossContentRetry: () => retried = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load this section"), findsOneWidget);
    final retryButton = find.text('Retry');
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    expect(retried, isTrue);
  });

  testWidgets('an empty result shows the empty state, not a blank section', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _body(
          audience: DashboardAudience.empty.copyWithCrossContent(
            CrossContentInsights.empty,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reach (All Content)'), findsOneWidget);
    expect(find.text('No content yet'), findsOneWidget);
  });

  testWidgets('populated data renders totals, breakdown and ranked content', (
    tester,
  ) async {
    final audience = DashboardAudience.empty.copyWithCrossContent(
      const CrossContentInsights(
        totalViews: 900,
        totalLikes: 300,
        totalComments: 45,
        breakdown: [
          ContentBreakdownItem(
            type: CrossContentType.reel,
            count: 3,
            views: 500,
            likes: 200,
            comments: 20,
          ),
          ContentBreakdownItem(
            type: CrossContentType.article,
            count: 1,
            views: 100,
            likes: 20,
            comments: 10,
          ),
        ],
        topContent: [
          CrossContentItem(
            id: 'reel-1',
            type: CrossContentType.reel,
            title: 'Best flip ever',
            views: 400,
            likes: 150,
            comments: 12,
          ),
          CrossContentItem(
            id: 'article-1',
            type: CrossContentType.article,
            title: 'Why Whitefield is booming',
            views: 100,
            likes: 20,
            comments: 10,
          ),
        ],
      ),
    );

    await tester.pumpWidget(_host(_body(audience: audience)));
    await tester.pumpAndSettle();

    expect(find.text('900'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('Reach (All Content)'), findsOneWidget);
    expect(find.text('Content Breakdown'), findsOneWidget);
    expect(find.text('Reel'), findsWidgets);
    expect(find.text('Article'), findsWidgets);
    expect(find.text('MOST LIKED CONTENT'), findsOneWidget);
    expect(find.text('Best flip ever'), findsOneWidget);
    expect(find.text('Why Whitefield is booming'), findsOneWidget);
    // Ranked #1/#2, not just listed in response order with no rank shown.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('tapping a Most Liked Content row reports that exact item back', (
    tester,
  ) async {
    CrossContentItem? tapped;
    const property = CrossContentItem(
      id: 'prop-9',
      type: CrossContentType.property,
      title: '3BHK in Whitefield',
      views: 200,
      likes: 60,
      comments: 8,
    );
    final audience = DashboardAudience.empty.copyWithCrossContent(
      const CrossContentInsights(topContent: [property]),
    );

    await tester.pumpWidget(
      _host(_body(audience: audience, onContentTap: (item) => tapped = item)),
    );
    await tester.pumpAndSettle();

    final finder = find.text('3BHK in Whitefield');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(tapped, isNotNull);
    expect(tapped!.id, 'prop-9');
    expect(tapped!.type, CrossContentType.property);
  });

  testWidgets('no tap affordance (chevron) when onContentTap is null', (
    tester,
  ) async {
    const reel = CrossContentItem(
      id: 'reel-2',
      type: CrossContentType.reel,
      title: 'A reel',
    );
    final audience = DashboardAudience.empty.copyWithCrossContent(
      const CrossContentInsights(topContent: [reel]),
    );

    await tester.pumpWidget(_host(_body(audience: audience)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });
}
