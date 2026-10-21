// Spec C — C-3 and C-4: the role-specific metrics, and the tile that had to go.
//
// What is pinned:
//
//   * "Saved Properties" appears only where `saved_properties` is queried. It was
//     on all four dashboards reading a permanent 0 on three of them;
//   * the broker's six listing metrics and three lead metrics render, and are
//     absent for every other role — null, not 0, because a broker with no
//     inquiries must still see the tile;
//   * the influencer's two watch metrics likewise;
//   * the formatters, which are the only new logic in the render path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/screens/dashboard/widgets/dashboard_tab_bodies.dart';
import 'package:propcid_app/widgets/shared/stat_kpi_card.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

/// The six metrics every role shares, so a fixture only states its extras.
const DashboardAnalytics _shared = DashboardAnalytics(
  totalViews: 4200,
  totalLikes: 310,
  avgEngagement: 7.38,
  totalInteractions: 4510,
  contentPosted: 6,
);

Future<void> _pumpAnalytics(
  WidgetTester tester,
  DashboardAnalytics analytics, {
  bool showSavedProperties = true,
  double textScale = 1.0,
  Size size = kSmall,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardAnalyticsBody(
            analytics: analytics,
            loading: false,
            failed: false,
            onRetry: () {},
            showSavedProperties: showSavedProperties,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAudience(
  WidgetTester tester,
  DashboardAudience audience, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = kSmall;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardAudienceBody(
            audience: audience,
            loading: false,
            failed: false,
            onRetry: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ── C-4. The Saved Properties tile ──────────────────────────────────────
  group('saved properties tile', () {
    testWidgets('shows for the role that computes it', (tester) async {
      await _pumpAnalytics(
        tester,
        const DashboardAnalytics(totalSaved: 12),
        showSavedProperties: true,
      );
      expect(find.text('Saved Properties'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('is hidden for the roles that do not', (tester) async {
      // Broker, builder and influencer never query `saved_properties`, so this
      // tile read 0 forever on three of the four dashboards.
      await _pumpAnalytics(tester, _shared, showSavedProperties: false);
      expect(find.text('Saved Properties'), findsNothing);
    });

    testWidgets('the shimmer matches the real card count', (tester) async {
      // A 6-card shimmer over a 5-card grid reflows the page as data lands.
      for (final show in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DashboardAnalyticsBody(
                  analytics: _shared,
                  loading: true,
                  failed: false,
                  onRetry: () {},
                  showSavedProperties: show,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester
              .widget<MetricCardGridShimmer>(
                  find.byType(MetricCardGridShimmer))
              .count,
          show ? 6 : 5,
        );
      }
    });

    testWidgets('the other five tiles are untouched', (tester) async {
      await _pumpAnalytics(tester, _shared, showSavedProperties: false);
      expect(find.text('Total Views'), findsOneWidget);
      expect(find.text('Total Likes'), findsOneWidget);
      expect(find.text('Avg Engagement'), findsOneWidget);
      expect(find.text('Total Interactions'), findsOneWidget);
      expect(find.text('Content Posted'), findsOneWidget);
    });
  });

  // ── C-3. Broker listing metrics ─────────────────────────────────────────
  group('broker listing metrics', () {
    const broker = DashboardAnalytics(
      totalViews: 4200,
      totalLikes: 310,
      avgEngagement: 7.38,
      totalInteractions: 4510,
      contentPosted: 6,
      activeCount: 4,
      soldCount: 2,
      totalInquiries: 37,
      totalValue: 38000000,
      totalCommission: 240000,
      commissionRate: 2,
    );

    testWidgets('all six render', (tester) async {
      await _pumpAnalytics(
        tester,
        broker,
        showSavedProperties: false,
        size: const Size(320, 1400),
      );

      expect(find.text('Active Listings'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Inquiries'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('Portfolio Value'), findsOneWidget);
      // 3.8 Cr, not 38000000 — a raw figure does not fit a tile.
      expect(find.text('₹3.8 Cr'), findsOneWidget);
      // The assumed rate is in the label, because it is an assumption.
      expect(find.text('Commission (2%)'), findsOneWidget);
      expect(find.text('₹2.4 L'), findsOneWidget);
    });

    testWidgets('none render for a role that leaves them null', (tester) async {
      await _pumpAnalytics(tester, _shared, showSavedProperties: false);

      for (final label in [
        'Active Listings',
        'Sold',
        'Inquiries',
        'Portfolio Value',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.textContaining('Commission'), findsNothing);
    });

    testWidgets('a broker with zero inquiries still sees the tile',
        (tester) async {
      // The reason these are nullable rather than defaulted to 0: "you have no
      // inquiries" is information, and hiding the tile would withhold it.
      await _pumpAnalytics(
        tester,
        const DashboardAnalytics(totalInquiries: 0, activeCount: 0),
        showSavedProperties: false,
      );

      expect(find.text('Inquiries'), findsOneWidget);
      expect(find.text('Active Listings'), findsOneWidget);
    });
  });

  // ── C-3. Influencer watch metrics ───────────────────────────────────────
  group('influencer watch metrics', () {
    testWidgets('both render', (tester) async {
      await _pumpAnalytics(
        tester,
        const DashboardAnalytics(
          totalViews: 4200,
          avgWatchTime: 95.4,
          // Not 62.55: its IEEE-754 value sits just below the midpoint, so
          // toStringAsFixed(1) gives 62.5 — as does JS toFixed(1), so the two
          // platforms agree. Avoided here so the test is about the tile, not
          // about float representation.
          avgCompletionRate: 62.64,
        ),
        showSavedProperties: false,
      );

      expect(find.text('Avg Watch Time'), findsOneWidget);
      expect(find.text('1:35'), findsOneWidget);
      expect(find.text('Avg Completion'), findsOneWidget);
      expect(find.text('62.6%'), findsOneWidget);
    });

    testWidgets('neither renders for a role that leaves them null',
        (tester) async {
      await _pumpAnalytics(tester, _shared, showSavedProperties: false);
      expect(find.text('Avg Watch Time'), findsNothing);
      expect(find.text('Avg Completion'), findsNothing);
    });
  });

  // ── C-3. Broker lead metrics ────────────────────────────────────────────
  group('broker lead metrics', () {
    const brokerAudience = DashboardAudience(
      totalFollowers: 88,
      followersGrowth: 12.5,
      totalViews: 4200,
      avgViewsPerPost: 700,
      engagementRate: 7.38,
      totalLeads: 37,
      leadConversionRate: 18.9,
      responseRate: 64.86,
    );

    testWidgets('all three appear in the insights card', (tester) async {
      await _pumpAudience(tester, brokerAudience);

      expect(find.text('Total Leads'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('Lead Conversion'), findsOneWidget);
      expect(find.text('18.9%'), findsOneWidget);
      expect(find.text('Response Rate'), findsOneWidget);
      expect(find.text('64.9%'), findsOneWidget);
    });

    testWidgets('the four shared rows still come first', (tester) async {
      await _pumpAudience(tester, brokerAudience);

      final shared = tester.getRect(find.text('Audience Size')).top;
      final added = tester.getRect(find.text('Total Leads')).top;
      expect(shared, lessThan(added),
          reason: 'appended, so the existing rows keep their order');
    });

    testWidgets('none render for a non-broker', (tester) async {
      await _pumpAudience(
        tester,
        const DashboardAudience(totalFollowers: 88, totalViews: 4200),
      );

      expect(find.text('Total Leads'), findsNothing);
      expect(find.text('Lead Conversion'), findsNothing);
      expect(find.text('Response Rate'), findsNothing);
      // The four shared rows are unaffected.
      expect(find.text('Audience Size'), findsOneWidget);
    });
  });

  // ── The formatters ──────────────────────────────────────────────────────
  group('formatCompactCurrency', () {
    test('crore, lakh and below', () {
      expect(formatCompactCurrency(38000000), '₹3.8 Cr');
      expect(formatCompactCurrency(10000000), '₹1 Cr');
      expect(formatCompactCurrency(4500000), '₹45 L');
      expect(formatCompactCurrency(240000), '₹2.4 L');
      expect(formatCompactCurrency(9500), '₹9,500');
      expect(formatCompactCurrency(0), '₹0');
    });

    test('a trailing .0 is dropped, a real decimal is kept', () {
      // ₹1.0 Cr reads as a rounding artefact; ₹1 Cr reads as a number.
      expect(formatCompactCurrency(10000000), '₹1 Cr');
      expect(formatCompactCurrency(12000000), '₹1.2 Cr');
    });

    test('the lakh boundary is exact', () {
      expect(formatCompactCurrency(99999), '₹99,999');
      expect(formatCompactCurrency(100000), '₹1 L');
    });
  });

  group('formatDuration', () {
    test('under a minute reads in seconds', () {
      expect(formatDuration(0), '0s');
      expect(formatDuration(45.4), '45s');
      expect(formatDuration(59.6), '1:00',
          reason: 'rounds to 60 first, so it is a minute');
    });

    test('a minute and over reads as m:ss', () {
      expect(formatDuration(60), '1:00');
      expect(formatDuration(95.4), '1:35');
      expect(formatDuration(3599), '59:59');
      // Hours are not split out: a watch time that long is not a real case, and
      // 60:00 still reads correctly.
      expect(formatDuration(3600), '60:00');
    });

    test('seconds are always two digits', () {
      expect(formatDuration(61), '1:01');
      expect(formatDuration(69), '1:09');
    });
  });

  // ── Layout ──────────────────────────────────────────────────────────────
  group('layout', () {
    testWidgets('eleven broker tiles lay out at 320 dp and 130% text',
        (tester) async {
      await _pumpAnalytics(
        tester,
        const DashboardAnalytics(
          totalViews: 4200000,
          totalLikes: 310000,
          avgEngagement: 7.38,
          totalInteractions: 4510000,
          contentPosted: 640,
          activeCount: 400,
          soldCount: 220,
          totalInquiries: 3700,
          totalValue: 38000000,
          totalCommission: 240000,
          commissionRate: 2,
        ),
        showSavedProperties: false,
        textScale: 1.3,
        size: const Size(320, 2400),
      );

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the seven-row broker insights card fits too', (tester) async {
      await _pumpAudience(
        tester,
        const DashboardAudience(
          totalFollowers: 8800,
          followersGrowth: 112.5,
          totalViews: 4200000,
          avgViewsPerPost: 70000,
          engagementRate: 7.38,
          totalLeads: 3700,
          leadConversionRate: 18.9,
          responseRate: 64.86,
        ),
        textScale: 1.3,
      );

      expect(overflowingBoxes(tester), isEmpty);
    });
  });
}
