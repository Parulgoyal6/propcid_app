import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/config/role_plan_config.dart';
import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/widgets/scale_tap.dart';
import 'package:propcid_app/core/navigation/workspace_destinations.dart';
import 'package:propcid_app/models/network_stats.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/network_hub_provider.dart';
import 'package:propcid_app/screens/network/network_hub_screen.dart';
import 'package:propcid_app/services/network_service.dart';
import 'package:propcid_app/screens/social/social_hub_screen.dart';
import 'package:propcid_app/screens/subscription/plan_catalogue.dart';
import 'package:propcid_app/screens/subscription/upgrade_screen.dart';
import 'package:propcid_app/widgets/manage_list_tile.dart';
import 'package:propcid_app/widgets/shared/stat_kpi_card.dart';
import 'package:propcid_app/widgets/shared/toggle_row.dart';

// The promoted surface primitives, reached through both paths, to prove the
// Phase 6 re-export shim resolves to the same classes.
import 'package:propcid_app/screens/dashboard/widgets/dashboard_primitives.dart'
    as legacy;
import 'package:propcid_app/widgets/shared/app_surface_card.dart' as shared;

import 'support/overflow_detector.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// An [AuthProvider] whose role and id are set directly.
///
/// The Upgrade screen reads `userType` to pick the plan ladder and `userId` to
/// decide whether there is a subscription to look up, so both are overridden and
/// nothing else is.
class _FakeAuth extends AuthProvider {
  _FakeAuth({this.id, this.type});

  final String? id;
  final String? type;

  @override
  String? get userId => id;

  @override
  String? get userType => type;

  @override
  bool get isLoggedIn => id != null;
}

/// The Upgrade screen needs an [AuthProvider]; it creates its own
/// [SubscriptionProvider] internally. Signed out by default, which is the state
/// that exercises the free-tier defaults without reaching the network.
Widget _upgradeHost({String? userId, String? userType}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuth(id: userId, type: userType),
    ),
  ],
  child: const MaterialApp(home: UpgradeScreen()),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `AuthProvider`'s constructor subscribes to auth state, which needs a
    // client. Nothing here talks to a server.
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  group('NetworkStats', () {
    test('starts zeroed', () {
      const stats = NetworkStats.empty;
      expect(stats.totalNetworks, 0);
      expect(stats.activeLeads, 0);
      expect(stats.totalReferrals, 0);
      expect(stats.monthlyCommissions, 0);
    });

    test('formats commissions with Indian digit grouping', () {
      String display(double v) =>
          NetworkStats(monthlyCommissions: v).monthlyCommissionsDisplay;

      expect(display(0), '₹0');
      expect(display(500), '₹500');
      // The design's own example value.
      expect(display(24500), '₹24,500');
      // Above a lakh the grouping switches to pairs, not thousands.
      expect(display(124500), '₹1,24,500');
      expect(display(10000000), '₹1,00,00,000');
    });

    test('rounds fractional amounts and keeps the sign', () {
      expect(
        const NetworkStats(
          monthlyCommissions: 1499.6,
        ).monthlyCommissionsDisplay,
        '₹1,500',
      );
      expect(
        const NetworkStats(monthlyCommissions: -2500).monthlyCommissionsDisplay,
        '-₹2,500',
      );
    });

    test('mirrors React by reporting no referral count', () {
      // React: `const referralsCount = 0; // Temporarily disable this query`.
      expect(const NetworkStats().totalReferrals, 0);
    });

    test('the three performance figures are em dashes with no data', () {
      const stats = NetworkStats.empty;
      expect(stats.successRateDisplay, '—');
      expect(stats.avgResponseTimeDisplay, '—');
      expect(stats.networkRatingDisplay, '—');
    });

    test(
      'formats real performance figures, not the portal\'s hardcoded ones',
      () {
        const stats = NetworkStats(
          successRatePercent: 84.6,
          avgResponseTimeHours: 2.34,
          networkRating: 4.8,
        );
        expect(stats.successRateDisplay, '85%'); // rounds, does not truncate
        expect(stats.avgResponseTimeDisplay, '2.3 hrs');
        expect(stats.networkRatingDisplay, '4.8/5');
      },
    );
  });

  group('NetworkService.computePerformanceMetrics', () {
    test('an empty lead list is no data, not a zero rate', () {
      final result = NetworkService.computePerformanceMetrics(const []);
      expect(result.successRate, isNull);
      expect(result.avgResponseTimeHours, isNull);
    });

    test('success rate counts converted over every lead, any status', () {
      final result = NetworkService.computePerformanceMetrics([
        {'status': 'converted', 'assigned_at': null, 'contacted_at': null},
        {'status': 'pending', 'assigned_at': null, 'contacted_at': null},
        {'status': 'lost', 'assigned_at': null, 'contacted_at': null},
        {'status': 'assigned', 'assigned_at': null, 'contacted_at': null},
      ]);
      expect(result.successRate, 25.0);
    });

    test('response time only counts contacted/converted leads with both '
        'timestamps', () {
      final result = NetworkService.computePerformanceMetrics([
        // Counts: 2 hours.
        {
          'status': 'contacted',
          'assigned_at': '2026-01-01T10:00:00Z',
          'contacted_at': '2026-01-01T12:00:00Z',
        },
        // Counts: 4 hours.
        {
          'status': 'converted',
          'assigned_at': '2026-01-02T09:00:00Z',
          'contacted_at': '2026-01-02T13:00:00Z',
        },
        // Not contacted yet — excluded even though it has an assigned_at.
        {
          'status': 'assigned',
          'assigned_at': '2026-01-03T09:00:00Z',
          'contacted_at': null,
        },
        // Contacted but missing assigned_at — cannot be timed, excluded.
        {
          'status': 'contacted',
          'assigned_at': null,
          'contacted_at': '2026-01-04T09:00:00Z',
        },
      ]);
      expect(result.avgResponseTimeHours, 3.0); // (2 + 4) / 2
    });

    test('leads exist but none were ever contacted: rate yes, time no', () {
      final result = NetworkService.computePerformanceMetrics([
        {'status': 'pending', 'assigned_at': null, 'contacted_at': null},
      ]);
      expect(result.successRate, 0.0);
      expect(result.avgResponseTimeHours, isNull);
    });
  });

  group('NetworkHubProvider', () {
    test('begins loading with zeroed stats', () {
      final provider = NetworkHubProvider();
      addTearDown(provider.dispose);

      expect(provider.loading, isTrue);
      expect(provider.failed, isFalse);
      expect(provider.stats.totalNetworks, 0);
    });

    test(
      'reports failure instead of zeros when the query cannot run',
      () async {
        // Supabase is not initialised in a unit test, so the service throws on
        // construction — exactly the path a real query failure takes.
        final provider = NetworkHubProvider();
        addTearDown(provider.dispose);

        await provider.load('user-1', isBuilder: true);

        expect(provider.loading, isFalse);
        expect(provider.failed, isTrue);
        expect(provider.stats.totalNetworks, 0);
      },
    );

    test('notifying after dispose does not throw', () async {
      final provider = NetworkHubProvider();
      provider.dispose();

      // refresh() with no prior load is a no-op and must stay silent.
      await provider.refresh();
    });
  });

  group('Network hub', () {
    testWidgets('renders the design\'s four KPIs and three destinations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats(
              totalNetworks: 3,
              activeLeads: 5,
              monthlyCommissions: 24500,
            ),
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Memberships, leads & referrals'), findsOneWidget);

      for (final label in const [
        'Networks Joined',
        'Active Leads',
        'Total Referrals',
        'Monthly Commissions',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('₹24,500'), findsOneWidget);

      for (final label in const [
        'My Networks',
        'My Referrals',
        'Communication',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Removed for every role — a builder already had this excluded as a
      // dashboard duplicate, and that was extended to apply to everyone.
      expect(find.text('My Leads'), findsNothing);

      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Performance Summary'), findsOneWidget);
    });

    testWidgets('drives nav-card subtitles from the live counts', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats(totalNetworks: 3, activeLeads: 5),
            loading: false,
            failed: false,
          ),
        ),
      );

      // Non-builder (the default) reads as "networks joined" — a builder's
      // own owned-network count uses different wording, see the next test.
      expect(find.text('3 networks joined'), findsOneWidget);
    });

    testWidgets(
      "drives a builder's nav-card subtitle from the live member count",
      (tester) async {
        await tester.pumpWidget(
          _host(
            const NetworkHubBody(
              stats: NetworkStats(totalNetworks: 3, activeLeads: 5),
              loading: false,
              failed: false,
              isBuilder: true,
            ),
          ),
        );

        expect(find.text('3 network members'), findsOneWidget);
      },
    );

    testWidgets('shows a shimmer, not zeros, while loading', (tester) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats.empty,
            loading: true,
            failed: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MetricCardGridShimmer), findsOneWidget);
      expect(find.text('Networks Joined'), findsNothing);
      // Subtitles fall back to descriptors rather than "0 active networks".
      expect(find.text('0 active networks'), findsNothing);
      expect(find.text('Builder networks you belong to'), findsOneWidget);
    });

    testWidgets('shows em dashes, not zeros, when the query failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats.empty,
            loading: false,
            failed: true,
          ),
        ),
      );

      // Four KPI values plus the three Performance Summary pills.
      expect(find.text('—'), findsNWidgets(7));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('never presents the invented performance figures', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats.empty,
            loading: false,
            failed: false,
          ),
        ),
      );

      // React hardcodes these three with no query behind them.
      expect(find.text('85%'), findsNothing);
      expect(find.text('2.3 hrs'), findsNothing);
      expect(find.text('4.8/5'), findsNothing);
      // The rows themselves are still present, awaiting a real source.
      expect(find.text('Success Rate'), findsOneWidget);
      expect(find.text('Response Time'), findsOneWidget);
      expect(find.text('Network Rating'), findsOneWidget);
    });

    testWidgets('renders real performance figures once a source exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats(
              successRatePercent: 85,
              avgResponseTimeHours: 2.3,
              networkRating: 4.8,
            ),
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('85%'), findsOneWidget);
      expect(find.text('2.3 hrs'), findsOneWidget);
      expect(find.text('4.8/5'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(
          // The widest realistic values, to stress the 2×2 grid's cells.
          const NetworkHubBody(
            stats: NetworkStats(
              totalNetworks: 128,
              activeLeads: 4096,
              monthlyCommissions: 12345678,
            ),
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('a nav card navigates rather than dead-ending', (tester) async {
      // Phase 6 shipped this hub with every card on the honest placeholder.
      // Phase 9 delivered the four real leaf screens, so the card now pushes a
      // named route. The invariant this test protects is unchanged — a card
      // must always go somewhere — only the destination moved on. Same update
      // as the Social hub's equivalent test after Phase 8.
      final pushed = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: const NetworkHubBody(
            stats: NetworkStats.empty,
            loading: false,
            failed: false,
          ),
          onGenerateRoute: (settings) {
            if (settings.name != null) pushed.add(settings.name!);
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SizedBox.shrink(),
            );
          },
        ),
      );

      await tester.tap(find.text('My Networks'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppConstants.myNetworksScreen));
    });
  });

  group('Social hub', () {
    testWidgets('renders the header and all six design destinations', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const SocialHubScreen()));

      expect(find.text('Social'), findsOneWidget);
      expect(
        find.text('Connect Facebook & Instagram, publish everywhere'),
        findsOneWidget,
      );

      for (final label in const [
        'Social Accounts',
        'Social Campaigns',
        'Social Leads',
        'Social Preferences',
        'Social Activity',
        'Social Analytics',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // The design's subtitles, verbatim.
      expect(find.text('Facebook & Instagram connection'), findsOneWidget);
      expect(find.text('Reach & post performance'), findsOneWidget);

      expect(find.byType(ManageListTile), findsNWidgets(6));
    });

    testWidgets('a card navigates rather than dead-ending', (tester) async {
      // Phase 6 shipped this hub with every card on the honest placeholder.
      // Phase 8 delivered the six real leaf screens, so the card now pushes a
      // named route. The invariant this test protects is unchanged — a card
      // must always go somewhere — only the destination moved on.
      final pushed = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: const SocialHubScreen(),
          onGenerateRoute: (settings) {
            if (settings.name != null) pushed.add(settings.name!);
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SizedBox.shrink(),
            );
          },
        ),
      );

      await tester.tap(find.text('Social Campaigns'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppConstants.socialCampaignsScreen));
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(const SocialHubScreen()));
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Upgrade screen', () {
    testWidgets('renders the individual ladder at monthly pricing', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();

      expect(find.text('Upgrade Your Plan'), findsOneWidget);
      expect(
        find.text('Unlock more features and grow faster on PropCid'),
        findsOneWidget,
      );

      for (final name in const [
        'Free',
        'Owner Plus',
        'Owner Pro',
        'Concierge',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }

      expect(find.text('₹0'), findsOneWidget);
      expect(find.text('₹9'), findsOneWidget);
      expect(find.text('₹19'), findsOneWidget);
      expect(find.text('₹49'), findsOneWidget);
      expect(find.text('/month'), findsNWidgets(4));

      expect(find.text(PlanCatalogue.yearlySavingLabel), findsNothing);
    });

    testWidgets('yearly reprices every card to the flat annual charge', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();

      expect(find.text('₹7'), findsOneWidget);
      expect(find.text('₹15'), findsOneWidget);
      expect(find.text('₹39'), findsOneWidget);
      expect(find.text('/year'), findsNWidgets(4));

      expect(find.text(PlanCatalogue.yearlySavingLabel), findsOneWidget);

      // ₹7/year is the whole annual charge, so there is no separate annual
      // total to print — the old "Billed annually (₹84/year)" note contradicted
      // both the headline and `create-order`. See role_plan_config.dart.
      expect(find.textContaining('Billed annually'), findsNothing);
    });

    testWidgets('tapping the Monthly/Yearly labels also switches', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(find.text('/year'), findsNWidgets(4));

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('/month'), findsNWidgets(4));
    });

    testWidgets('a broker sees the broker ladder, not the individual one', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost(userType: 'broker'));
      await tester.pumpAndSettle();

      // The bug this fixes: every role used to be quoted the individual prices
      // while `create-order` charged from their real `user_type`.
      expect(find.text('Broker Pro'), findsOneWidget);
      expect(find.text('₹29'), findsOneWidget);
      expect(find.text('Owner Plus'), findsNothing);
      expect(find.text('₹9'), findsNothing);
    });

    testWidgets('an unknown role falls back to the individual ladder', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost(userType: 'admin'));
      await tester.pumpAndSettle();

      expect(find.text('Owner Plus'), findsOneWidget);
    });

    testWidgets('the account plan is marked current and is not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();

      // No subscription row means the free tier, which is what
      // `SubscriptionSummary.free` and the portal both default to.
      expect(find.text('Current Plan'), findsOneWidget);
      expect(find.text('Most Popular'), findsOneWidget);

      // The current plan's CTA is a label: no ScaleTap wrapper at all, so a tap
      // would land on nothing.
      expect(
        find.ancestor(
          of: find.text('Current Plan'),
          matching: find.byType(ScaleTap),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text('Choose Owner Plus'),
          matching: find.byType(ScaleTap),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a paid CTA signed out asks for sign-in and buys nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();

      // The second card sits below the test viewport, so scroll its CTA into
      // view before tapping — otherwise the tap lands outside the view.
      await tester.ensureVisible(find.text('Choose Owner Plus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose Owner Plus'));
      await tester.pumpAndSettle();

      expect(find.text('Please sign in to change your plan.'), findsOneWidget);
      // Nothing opened, and no plan changed.
      expect(find.text('Current Plan'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_upgradeHost());
      await tester.pumpAndSettle();
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Role plan config', () {
    test('every role ships the four canonical plan ids in tier order', () {
      for (final entry in kRolePlans.entries) {
        expect(
          entry.value.map((p) => p.id).toList(),
          PlanId.values,
          reason: entry.key.name,
        );
      }
    });

    test('yearly is a flat annual charge below the monthly rate', () {
      // Not `monthly * 12`, and not above it either — the whole point of the
      // yearly option is that it costs less than a month does.
      for (final entry in kRolePlans.entries) {
        for (final plan in entry.value) {
          expect(
            plan.yearlyPrice,
            lessThanOrEqualTo(plan.monthlyPrice),
            reason: '${entry.key.name}/${plan.id.wire}',
          );
        }
      }
    });

    test('exactly one plan per role carries the popular badge', () {
      for (final entry in kRolePlans.entries) {
        final badged = entry.value.where((p) => p.badge != null).toList();
        expect(badged.length, 1, reason: entry.key.name);
        // The portal sets `popular: true` on the `pro` tier only.
        expect(badged.single.id, PlanId.pro, reason: entry.key.name);
      }
    });

    test('plansForRole maps each wire role, and falls back for the rest', () {
      expect(plansForRole('broker'), same(kRolePlans[UserRole.broker]));
      expect(plansForRole('builder'), same(kRolePlans[UserRole.builder]));
      expect(plansForRole('influencer'), same(kRolePlans[UserRole.influencer]));
      expect(plansForRole('individual'), same(kRolePlans[UserRole.individual]));

      // Unset, unknown and admin all quote the lowest ladder rather than
      // guessing at a higher-priced one.
      expect(plansForRole(null), same(kRolePlans[UserRole.individual]));
      expect(plansForRole('admin'), same(kRolePlans[UserRole.individual]));
    });

    test('PlanId round-trips its wire value and defaults to free', () {
      for (final id in PlanId.values) {
        expect(PlanId.fromWire(id.wire), id);
      }
      expect(PlanId.fromWire('PRO'), PlanId.pro);
      expect(PlanId.fromWire('legacy-plan'), PlanId.free);
      expect(PlanId.fromWire(null), PlanId.free);
    });

    test('tier order matches PLAN_TIER, so downgrades compare correctly', () {
      expect(PlanId.free.tier, 0);
      expect(PlanId.pro.tier, 1);
      expect(PlanId.builder.tier, 2);
      expect(PlanId.enterprise.tier, 3);
    });
  });

  group('AppToggle geometry', () {
    testWidgets('default settings-row size is unchanged by Phase 6', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(Center(child: AppToggle(value: false, onChanged: (_) {}))),
      );

      final track = tester.getSize(
        find.descendant(
          of: find.byType(AppToggle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(track.width, 40);
      expect(track.height, 24);
    });

    testWidgets('accepts the design\'s larger billing-period size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: AppToggle(
              value: false,
              onChanged: (_) {},
              trackWidth: 44,
              trackHeight: 26,
              knobSize: 22,
            ),
          ),
        ),
      );

      final track = tester.getSize(
        find.descendant(
          of: find.byType(AppToggle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(track.width, 44);
      expect(track.height, 26);
    });
  });

  group('Phase 6 promotion and routing', () {
    test('the surface primitives are the same classes through both paths', () {
      expect(shared.DashboardCard, legacy.DashboardCard);
      expect(shared.DashboardCardTitle, legacy.DashboardCardTitle);
      expect(shared.DashboardSectionLabel, legacy.DashboardSectionLabel);
    });

    test('the promoted shimmer reuses the real grid geometry', () {
      // Guards the invariant the dashboards relied on: placeholder and real
      // grid must share one delegate so nothing shifts when values land.
      expect(MetricCardGrid.delegate.mainAxisExtent, MetricCardGrid.cardHeight);
      expect(MetricCardGrid.delegate.crossAxisCount, 2);
    });

    test('the three hub routes are distinct named routes', () {
      final routes = {
        AppConstants.networkScreen,
        AppConstants.socialScreen,
        AppConstants.upgradeScreen,
      };
      expect(routes.length, 3);
      expect(AppConstants.networkScreen, '/network');
      expect(AppConstants.socialScreen, '/social');
      expect(AppConstants.upgradeScreen, '/upgrade');
    });

    testWidgets('destinations push the hub routes, not the placeholder', (
      tester,
    ) async {
      final pushed = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name != null) pushed.add(settings.name!);
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SizedBox.shrink(),
            );
          },
        ),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      WorkspaceDestinations.network(navigator);
      WorkspaceDestinations.social(navigator);
      WorkspaceDestinations.upgrade(navigator);
      await tester.pumpAndSettle();

      // Network and Social are unaffected by the subscriptions launch flag —
      // both still push their real hub routes, not a placeholder.
      expect(
        pushed,
        containsAll(<String>[
          AppConstants.networkScreen,
          AppConstants.socialScreen,
        ]),
      );
      // Upgrade is the one hub gated by `LaunchFeatures.subscriptions`
      // (defaulted off, as every `flutter test` run compiles it) — its own
      // defensive guard means this call is a no-op rather than pushing
      // `/upgrade`. Covered as its own behaviour, not a "placeholder" bug,
      // by `test/route_protection_test.dart` and
      // `test/workspace_navigation_gates_test.dart`.
      expect(pushed, isNot(contains(AppConstants.upgradeScreen)));
    });
  });
}
