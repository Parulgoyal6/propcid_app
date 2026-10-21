import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/network_analytics.dart';
import 'package:propcid_app/providers/network_analytics_provider.dart';
import 'package:propcid_app/screens/network/network_analytics_screen.dart';
import 'package:propcid_app/services/network_analytics_service.dart';

Widget _host(Widget child) => MaterialApp(home: child);

NetworkPerformanceEntry _entry({
  String id = 'p1',
  String memberId = 'm1',
  int leadsReceived = 10,
  int leadsConverted = 4,
  double conversionRate = 40,
  double performanceScore = 72,
  double totalCommissionEarned = 5000,
  String? displayName = 'Amy Rao',
  String? userType = 'broker',
}) {
  return NetworkPerformanceEntry.fromSupabase(
    {
      'id': id,
      'member_id': memberId,
      'leads_received': leadsReceived,
      'leads_converted': leadsConverted,
      'conversion_rate': conversionRate,
      'performance_score': performanceScore,
      'total_commission_earned': totalCommissionEarned,
    },
    displayName: displayName,
    userType: userType,
  );
}

void main() {
  group('NetworkAnalyticsStats', () {
    test(
      'conversion rate and active rate are 0 with no leads/members, not NaN',
      () {
        const stats = NetworkAnalyticsStats.empty;
        expect(stats.averageConversionRate, 0);
        expect(stats.activeMemberRate, 0);
      },
    );

    test('derives conversion rate and active rate from real counts', () {
      const stats = NetworkAnalyticsStats(
        totalMembers: 10,
        activeMembers: 6,
        totalLeadsDistributed: 20,
        convertedLeads: 5,
      );
      expect(stats.activeMemberRate, 60);
      expect(stats.averageConversionRate, 25);
      expect(stats.conversionRateDisplay, '25.0%');
    });

    test(
      'formats commissions paid the same way the rest of the module does',
      () {
        const stats = NetworkAnalyticsStats(totalCommissionsPaid: 24500);
        expect(stats.commissionsPaidDisplay, '₹24,500');
      },
    );
  });

  group('NetworkPerformanceEntry', () {
    test('parses the leaderboard fields and resolves a display name', () {
      final entry = _entry();
      expect(entry.leadsReceived, 10);
      expect(entry.leadsConverted, 4);
      expect(entry.resolvedName, 'Amy Rao');
      expect(entry.roleLabel, 'Broker');
      expect(entry.conversionRateDisplay, '40.0%');
      expect(entry.commissionEarnedDisplay, '₹5,000');
    });

    test('an unresolved profile falls back to Unknown / Member', () {
      final entry = _entry(displayName: null, userType: null);
      expect(entry.resolvedName, 'Unknown');
      expect(entry.initial, 'U');
      expect(entry.roleLabel, 'Member');
    });
  });

  group('NetworkAnalyticsProvider', () {
    late _FakeAnalyticsService service;
    late NetworkAnalyticsProvider provider;

    setUp(() {
      service = _FakeAnalyticsService();
      provider = NetworkAnalyticsProvider(service: service);
    });

    tearDown(() => provider.dispose());

    test('load populates stats and the performance leaderboard', () async {
      service.nextStats = const NetworkAnalyticsStats(
        totalMembers: 3,
        activeMembers: 2,
      );
      service.nextPerformance = [_entry()];

      await provider.load('builder-1');

      expect(provider.loading, isFalse);
      expect(provider.failed, isFalse);
      expect(provider.stats.totalMembers, 3);
      expect(provider.performance.length, 1);
    });

    test('a failed load is distinguished from a genuinely empty one', () async {
      service.nextError = Exception('down');

      await provider.load('builder-1');

      expect(provider.failed, isTrue);
      expect(provider.stats.totalMembers, 0);
      expect(provider.performance, isEmpty);
    });

    test('a stale response never overwrites a newer user\'s data', () async {
      final firstLoad = provider.load('user-a');
      service.nextStats = const NetworkAnalyticsStats(totalMembers: 9);
      await provider.load('user-b');
      await firstLoad;

      expect(provider.stats.totalMembers, 9);
    });
  });

  group('NetworkAnalyticsBody', () {
    testWidgets('renders the four KPI tiles with real (zeroed) values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkAnalyticsBody(
            stats: NetworkAnalyticsStats.empty,
            performance: [],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Network Analytics'), findsWidgets);
      expect(find.text('Total Members'), findsOneWidget);
      // Appears twice, same as the portal: once as the KPI tile label and
      // once as the Network Health card's "Leads Distributed" count below.
      expect(find.text('Leads Distributed'), findsWidgets);
      expect(find.text('Conversion Rate'), findsOneWidget);
      expect(find.text('Commissions Paid'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets(
      'the Overview tab shows Network Health and a static Performance card',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const NetworkAnalyticsBody(
              stats: NetworkAnalyticsStats.empty,
              performance: [],
              loading: false,
              failed: false,
            ),
          ),
        );

        expect(find.text('Network Health'), findsOneWidget);
        expect(find.text('Active Members'), findsOneWidget);
        expect(find.text('Lead Conversion'), findsOneWidget);
        expect(find.text('Performance Dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'Performance tab shows a real leaderboard row when data exists',
      (tester) async {
        await tester.pumpWidget(
          _host(
            NetworkAnalyticsBody(
              stats: NetworkAnalyticsStats.empty,
              performance: [_entry()],
              loading: false,
              failed: false,
            ),
          ),
        );

        await tester.tap(find.text('Performance'));
        await tester.pumpAndSettle();

        expect(find.text('Amy Rao'), findsOneWidget);
        expect(find.text('Broker'), findsOneWidget);
        expect(find.text('No Performance Data'), findsNothing);
      },
    );

    testWidgets('Performance tab shows the empty state with no data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkAnalyticsBody(
            stats: NetworkAnalyticsStats.empty,
            performance: [],
            loading: false,
            failed: false,
          ),
        ),
      );

      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(find.text('No Performance Data'), findsOneWidget);
    });

    testWidgets(
      'Trends and Insights are static placeholders, matching the portal copy',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const NetworkAnalyticsBody(
              stats: NetworkAnalyticsStats.empty,
              performance: [],
              loading: false,
              failed: false,
            ),
          ),
        );

        await tester.tap(find.text('Trends'));
        await tester.pumpAndSettle();
        expect(find.text('Trend Analysis Coming Soon'), findsOneWidget);

        await tester.tap(find.text('Insights'));
        await tester.pumpAndSettle();
        expect(find.text('AI-Powered Insights'), findsOneWidget);
      },
    );

    testWidgets('a failed load shows a retry state, not zeroed KPI tiles', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkAnalyticsBody(
            stats: NetworkAnalyticsStats.empty,
            performance: [],
            loading: false,
            failed: true,
          ),
        ),
      );

      expect(find.text("Couldn't load analytics"), findsOneWidget);
      expect(find.text('Total Members'), findsNothing);
    });
  });
}

class _FakeAnalyticsService extends NetworkAnalyticsService {
  NetworkAnalyticsStats nextStats = NetworkAnalyticsStats.empty;
  List<NetworkPerformanceEntry> nextPerformance = const [];
  Object? nextError;

  @override
  Future<NetworkAnalyticsStats> getStats(String builderId) async {
    final error = nextError;
    if (error != null) throw error;
    return nextStats;
  }

  @override
  Future<List<NetworkPerformanceEntry>> listPerformance(
    String builderId, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final error = nextError;
    if (error != null) throw error;
    return nextPerformance;
  }
}
