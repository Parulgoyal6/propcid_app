import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/subscription_summary.dart';
import 'package:propcid_app/providers/subscription_provider.dart';
import 'package:propcid_app/screens/stubs/coming_soon_screen.dart';
import 'package:propcid_app/screens/subscription/billing_policies_screen.dart';
import 'package:propcid_app/screens/subscription/plan_features.dart';
import 'package:propcid_app/screens/subscription/subscription_billing_screen.dart';
import 'package:propcid_app/screens/subscription/widgets/plan_usage_donut.dart';
import 'package:propcid_app/screens/subscription/widgets/subscription_tabs.dart';
import 'package:propcid_app/widgets/shared/section_header_back_button.dart';

import 'support/overflow_detector.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// A body wired to the given data, with the upgrade route captured.
Widget _screen(SubscriptionTabData data, {List<String>? pushed}) {
  return MaterialApp(
    home: SubscriptionBillingBody(data: data, loading: false),
    onGenerateRoute: (settings) {
      if (settings.name != null) pushed?.add(settings.name!);
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const SizedBox.shrink(),
      );
    },
  );
}

SubscriptionTabData _data({
  SubscriptionSummary? subscription,
  BillingProfile? profile,
  List<BillingHistoryItem> payments = const [],
  List<BillingHistoryItem> refunds = const [],
  double totalBilled = 0,
  bool historyFailed = false,
  bool subscriptionFailed = false,
}) {
  return SubscriptionTabData(
    subscription: subscription ?? SubscriptionSummary.free,
    billingProfile: profile,
    payments: payments,
    refunds: refunds,
    totalBilled: totalBilled,
    historyFailed: historyFailed,
    subscriptionFailed: subscriptionFailed,
  );
}

/// The widest realistic payload — long plan, long company name, eight-figure
/// amounts and a long invoice number — to stress every fixed-height cell.
SubscriptionTabData _wideData() {
  final item = BillingHistoryItem.fromJson(const {
    'id': 'inv-1',
    'date': '2026-08-01T10:00:00Z',
    'plan': 'enterprise',
    'amount': 1234567800,
    'finalAmount': 1456789000,
    'paymentStatus': 'completed',
    'refundStatus': 'none',
    'transactionId': 'pay_a_very_long_gateway_reference_value',
    'invoiceNumber': 'INV-0000000001',
  });

  return _data(
    subscription: SubscriptionSummary.fromJson(const {
      'plan': 'enterprise',
      'status': 'active',
      'billing_cycle': 'yearly',
      'expires_at': '2027-09-02T00:00:00Z',
      'auto_renew': true,
      'cancel_at_period_end': false,
    }),
    profile: BillingProfile.fromJson(const {
      'company_name': 'A Very Long Placeholder Company Name Private Limited',
      'gst_number': '00XXXXX0000X0X0',
      'address': 'A long placeholder street address that keeps on going',
      'city': 'Placeholderville',
      'state': 'Placeholder State',
      'postal_code': '000000',
      'country': 'India',
      'phone': '+00 00000 00000',
      'email': 'billing@example.invalid',
    }),
    payments: [item],
    totalBilled: 14567890,
  );
}

/// The tab strip's horizontal scrollable, as distinct from the page's vertical
/// one.
///
/// A function, not a stored `Finder`: `FinderBase` caches its match results, so
/// a single shared instance goes stale once a later test pumps a new tree and
/// then resolves to nothing.
Finder _tabStrip() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );

/// Opens a tab, scrolling its pill into view first.
///
/// The strip is a lazy horizontal `ListView`, so pills past the viewport are not
/// in the render tree at all and cannot be found until scrolled to — hence
/// `scrollUntilVisible` rather than `ensureVisible`.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    120,
    scrollable: _tabStrip(),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  group('BillingHistoryItem', () {
    test('converts every money field from paise to rupees', () {
      // The backend stores paise; React divides by 100 in mapBackendBillingItem
      // for exactly this field set.
      final item = BillingHistoryItem.fromJson(const {
        'id': 'inv-1',
        'date': '2026-08-01T10:00:00Z',
        'plan': 'pro',
        'amount': 199900,
        'billingCycle': 'monthly',
        'paymentStatus': 'completed',
        'refundStatus': 'none',
        'transactionId': 'pay_abc',
        'gstAmount': 35982,
        'finalAmount': 235882,
        'originalAmount': 235882,
        'invoiceNumber': 'INV-0001',
      });

      expect(item.amount, 1999);
      expect(item.gstAmount, 359.82);
      expect(item.finalAmount, 2358.82);
      expect(item.originalAmount, 2358.82);
      expect(item.invoiceNumber, 'INV-0001');
      expect(item.date, isNotNull);
      expect(item.hasRefund, isFalse);
    });

    test('tolerates a sparse payload', () {
      final item = BillingHistoryItem.fromJson(const {'id': 'x'});

      expect(item.amount, 0);
      expect(item.plan, 'free');
      expect(item.paymentStatus, 'pending');
      expect(item.refundStatus, 'none');
      expect(item.gstAmount, isNull);
      expect(item.date, isNull);
    });

    test('flags a refunded item', () {
      final item = BillingHistoryItem.fromJson(const {
        'id': 'x',
        'refundStatus': 'refunded',
        'refundAmount': 100000,
      });

      expect(item.hasRefund, isTrue);
      expect(item.refundAmount, 1000);
    });
  });

  group('SubscriptionSummary', () {
    test('free is React\'s no-row fallback', () {
      const sub = SubscriptionSummary.free;
      expect(sub.plan, 'free');
      expect(sub.status, 'active');
      expect(sub.billingCycle, 'monthly');
      expect(sub.autoRenew, isFalse);
      expect(sub.isRecorded, isFalse);
      expect(sub.isFree, isTrue);
      expect(sub.renewalLabel, isNull);
    });

    test('maps the real column names', () {
      final sub = SubscriptionSummary.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'billing_cycle': 'yearly',
        'starts_at': '2026-08-02T00:00:00Z',
        'expires_at': '2026-09-02T00:00:00Z',
        'auto_renew': true,
        'cancel_at_period_end': false,
      });

      expect(sub.plan, 'pro');
      expect(sub.billingCycle, 'yearly');
      expect(sub.autoRenew, isTrue);
      expect(sub.cancelAtPeriodEnd, isFalse);
      expect(sub.isRecorded, isTrue);
      expect(sub.isFree, isFalse);
      expect(sub.planLabel, 'Pro Plan');
      // The design's renewal format.
      expect(sub.renewalLabel, 'Sep 02, 2026');
    });
  });

  group('BillingProfile', () {
    test('maps snake_case columns', () {
      final profile = BillingProfile.fromJson(const {
        'company_name': 'Placeholder Pvt Ltd',
        'gst_number': '00XXXXX0000X0X0',
        'postal_code': '000000',
        'country': 'India',
      });

      expect(profile.companyName, 'Placeholder Pvt Ltd');
      expect(profile.gstNumber, '00XXXXX0000X0X0');
      expect(profile.postalCode, '000000');
      expect(profile.country, 'India');
      expect(profile.city, isNull);
    });
  });

  group('PlanFeatures', () {
    test('free unlocks 4 of 10, matching the design\'s KPIs and donut', () {
      expect(PlanFeatures.totalCount('free'), 10);
      expect(PlanFeatures.includedCount('free'), 4);
      expect(PlanFeatures.lockedCount('free'), 6);
    });

    test('paid tiers unlock progressively more', () {
      expect(PlanFeatures.includedCount('pro'), 6);
      expect(PlanFeatures.includedCount('builder'), 10);
      expect(PlanFeatures.includedCount('enterprise'), 10);
    });

    test('an unknown plan falls back to free rather than over-promising', () {
      expect(PlanFeatures.includedCount('some-future-tier'), 4);
      expect(PlanFeatures.forPlan('SOME-FUTURE-TIER').length, 10);
    });

    test('is case-insensitive on the stored value', () {
      expect(PlanFeatures.includedCount('PRO'), 6);
    });
  });

  group('formatRupees', () {
    test('groups the Indian way', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(999), '₹999');
      expect(formatRupees(1999), '₹1,999');
      expect(formatRupees(124500), '₹1,24,500');
      expect(formatRupees(10000000), '₹1,00,00,000');
    });
  });

  group('SubscriptionProvider', () {
    test('starts loading on the free fallback', () {
      final provider = SubscriptionProvider();
      addTearDown(provider.dispose);

      expect(provider.loading, isTrue);
      expect(provider.subscription.plan, 'free');
      expect(provider.history, isEmpty);
      expect(provider.subscriptionFailed, isFalse);
      expect(provider.historyFailed, isFalse);
    });

    test('flags each source independently when the client is unavailable',
        () async {
      final provider = SubscriptionProvider();
      addTearDown(provider.dispose);

      await provider.load('user-1');

      expect(provider.loading, isFalse);
      expect(provider.subscriptionFailed, isTrue);
      expect(provider.historyFailed, isTrue);
      // Never fabricates a plan on failure.
      expect(provider.subscription.plan, 'free');
      expect(provider.completedPayments, isEmpty);
      expect(provider.totalBilled, 0);
    });

    test('refresh before any load is a silent no-op', () async {
      final provider = SubscriptionProvider();
      provider.dispose();
      await provider.refresh();
    });
  });

  group('Subscription & Billing screen', () {
    testWidgets('renders the header, plan card and all ten tabs',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));

      expect(find.text('Subscription & Billing'), findsOneWidget);
      expect(find.text('Free Plan'), findsOneWidget);
      expect(find.text('PRICE'), findsOneWidget);
      expect(find.text('RENEWAL'), findsOneWidget);
      // No expiry on the free fallback.
      expect(find.text('N/A'), findsOneWidget);
      // Twice by design: the plan card's micro-label and the Overview KPI.
      expect(find.text('CURRENT PLAN'), findsNWidgets(2));

      // Ten tabs exist. The strip is a lazy horizontal list, so only the
      // leading pills are in the tree here; each of the rest is opened (and so
      // proven reachable) by its own test below.
      expect(SubscriptionTab.values.length, 10);
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Billing'), findsWidgets);
    });

    testWidgets('Overview shows the four KPIs and the 4/10 donut',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));

      expect(find.text('CURRENT PLAN'), findsNWidgets(2));
      expect(find.text('MONTHLY PRICE'), findsOneWidget);
      expect(find.text('AVAILABLE FEATURES'), findsOneWidget);
      expect(find.text('PREMIUM FEATURES'), findsOneWidget);

      expect(find.text('4'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('of 10 total'), findsOneWidget);

      expect(find.byType(PlanUsageDonut), findsOneWidget);
      expect(find.text('4/10'), findsOneWidget);
      expect(find.text('Unlocked'), findsOneWidget);

      // Free plan is genuinely ₹0 — not an em dash.
      expect(find.text('₹0'), findsOneWidget);
    });

    testWidgets('an empty billing history says so, and does not invent rows',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));

      expect(
        find.text('No payments yet. Your billing history will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed history is distinguished from an empty one',
        (tester) async {
      await tester.pumpWidget(_screen(_data(historyFailed: true)));

      expect(find.textContaining("Couldn't load"), findsOneWidget);
      expect(
        find.text('No payments yet. Your billing history will appear here.'),
        findsNothing,
      );
    });

    testWidgets('a failed subscription read shows em dashes, not "Free"',
        (tester) async {
      await tester.pumpWidget(_screen(_data(subscriptionFailed: true)));

      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('Free Plan'), findsNothing);
      expect(find.text('—/mo'), findsOneWidget);
    });

    testWidgets('Billing tab lists the real subscription facts',
        (tester) async {
      final sub = SubscriptionSummary.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'billing_cycle': 'monthly',
        'expires_at': '2026-09-02T00:00:00Z',
        'auto_renew': true,
        'cancel_at_period_end': false,
      });

      await tester.pumpWidget(_screen(_data(subscription: sub)));
      await _openTab(tester, 'Billing');

      expect(find.text('Billing Information'), findsOneWidget);
      expect(find.text('Renewal Date'), findsOneWidget);
      // Plan card's RENEWAL value plus the tab's Renewal Date row.
      expect(find.text('Sep 02, 2026'), findsNWidgets(2));
      expect(find.text('Auto Renewal'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
      expect(find.text('Upgrade Plan'), findsOneWidget);
      expect(find.text('Cancel Subscription'), findsOneWidget);
    });

    testWidgets('billing details are read-only and show "Not set" when empty',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));
      await _openTab(tester, 'Billing');

      expect(find.text('Billing Details'), findsOneWidget);
      expect(find.text('Company Name'), findsOneWidget);
      expect(find.text('GSTIN'), findsOneWidget);
      // Nine fields, all unset on a profile-less account.
      expect(find.text('Not set'), findsNWidgets(9));
      // No editable field is offered, because nothing writes yet.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Features tab reflects the stored plan', (tester) async {
      await tester.pumpWidget(_screen(_data()));
      await _openTab(tester, 'Features');

      expect(find.text('Feature Access'), findsOneWidget);
      expect(
        find.text('Everything included in your Free plan'),
        findsOneWidget,
      );
      expect(find.text('5 active property listings'), findsOneWidget);
      expect(
        find.text('Upgrade to Unlock All Features'),
        findsOneWidget,
      );
    });

    testWidgets('Features tab drops the upgrade CTA when nothing is locked',
        (tester) async {
      final sub =
          SubscriptionSummary.fromJson(const {'plan': 'builder', 'status': 'active', 'billing_cycle': 'monthly'});

      await tester.pumpWidget(_screen(_data(subscription: sub)));
      await _openTab(tester, 'Features');

      expect(find.text('Upgrade to Unlock All Features'), findsNothing);
      expect(find.text('Unlimited active property listings'), findsOneWidget);
    });

    testWidgets('Payments and Invoices state their own empties',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));

      await _openTab(tester, 'Payments');
      expect(find.text('No transactions available.'), findsOneWidget);

      await _openTab(tester, 'Invoices');
      expect(find.text('No invoices yet.'), findsOneWidget);
    });

    testWidgets('Refunds tab offers pricing rather than a dead end',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));
      await _openTab(tester, 'Refunds');

      expect(find.text('No Refund Requests'), findsOneWidget);
      expect(find.text('View Pricing Plans'), findsOneWidget);
    });

    testWidgets('Security and Usage render', (tester) async {
      await tester.pumpWidget(_screen(_data()));

      await _openTab(tester, 'Usage');
      expect(find.text('Usage Analytics'), findsOneWidget);
      expect(find.text('No spending data yet.'), findsOneWidget);

      await _openTab(tester, 'Security');
      expect(find.text('Security Settings'), findsOneWidget);
      expect(find.text('Razorpay Secure Payments'), findsOneWidget);
      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('Help tab lists support routes and the trust points',
        (tester) async {
      await tester.pumpWidget(_screen(_data()));
      await _openTab(tester, 'Help');

      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('FAQs'), findsOneWidget);
      expect(find.text('Raise a Ticket'), findsOneWidget);
      expect(find.text('Trusted & Transparent Billing'), findsOneWidget);
      expect(find.text('Secure Payments'), findsOneWidget);
      expect(find.text('Cancel Anytime'), findsOneWidget);
    });

    testWidgets('the Upgrade button routes to the Phase 6 upgrade screen',
        (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(_screen(_data(), pushed: pushed));

      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppConstants.upgradeScreen));
    });

    testWidgets('write actions land on the honest placeholder', (tester) async {
      await tester.pumpWidget(_host(
        SubscriptionBillingBody(data: _data(), loading: false),
      ));

      await _openTab(tester, 'Billing');
      await tester.ensureVisible(find.text('Cancel Subscription'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Subscription'));
      await tester.pumpAndSettle();

      expect(find.byType(ComingSoonScreen), findsOneWidget);
    });

    testWidgets('the Billing Policies tab opens its own screen',
        (tester) async {
      await tester.pumpWidget(_host(
        SubscriptionBillingBody(data: _data(), loading: false),
      ));

      await _openTab(tester, 'Billing Policies');

      expect(find.byType(BillingPoliciesScreen), findsOneWidget);
    });

    testWidgets('the hub chrome lays out without overflow on a small screen',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(SubscriptionBillingBody(data: _wideData(), loading: false)),
      );

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('tab bodies at 320 dp', () {
    // Driven directly rather than through the tab strip: at 320x568 the strip
    // sits below the fold, so a synthesised drag on it lands outside the view.
    // The overflow risk is in the bodies, which is what these render.
    Future<void> probe(WidgetTester tester, Widget body, String label) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(overflowingBoxes(tester), isEmpty, reason: label);
    }

    testWidgets('Overview', (tester) async {
      await probe(tester, OverviewTab(data: _wideData()), 'Overview');
    });

    testWidgets('Billing', (tester) async {
      await probe(
        tester,
        BillingTab(
          data: _wideData(),
          onUpgrade: () {},
          onCancel: () {},
          onResume: () {},
          onSaveDetails: () {},
        ),
        'Billing',
      );
    });

    testWidgets('Payments', (tester) async {
      await probe(tester, PaymentsTab(data: _wideData()), 'Payments');
    });

    testWidgets('Features', (tester) async {
      await probe(
        tester,
        FeaturesTab(data: _wideData(), onUpgrade: () {}),
        'Features',
      );
    });

    testWidgets('Invoices', (tester) async {
      await probe(
        tester,
        InvoicesTab(data: _wideData(), onDownload: (_) {}),
        'Invoices',
      );
    });

    testWidgets('Usage', (tester) async {
      await probe(tester, UsageTab(data: _wideData()), 'Usage');
    });

    testWidgets('Security', (tester) async {
      await probe(
        tester,
        SecurityTab(
          data: _wideData(),
          onUpgrade: () {},
          onComparePlans: () {},
          onPolicies: () {},
          onContactSupport: () {},
          onManagePaymentMethod: () {},
        ),
        'Security',
      );
    });

    testWidgets('Refunds', (tester) async {
      await probe(
        tester,
        RefundsTab(data: _wideData(), onViewPlans: () {}),
        'Refunds',
      );
    });

    testWidgets('Help', (tester) async {
      await probe(
        tester,
        HelpTab(
          onPolicies: () {},
          onContactSupport: () {},
          onRaiseTicket: () {},
        ),
        'Help',
      );
    });
  });

  group('Billing Policies screen', () {
    testWidgets('lists the nine policy sections collapsed', (tester) async {
      await tester.pumpWidget(_host(const BillingPoliciesScreen()));

      expect(find.text('Billing Policies'), findsOneWidget);
      for (final title in const [
        'Subscription Policy',
        'Billing Policy',
        'Cancellation Policy',
        'Refund Policy',
        'Upgrade & Downgrade',
        'Auto Renewal',
        'Payment Security',
        'Frequently Asked Questions',
        'Contact Billing Support',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }

      // Collapsed: no body copy on screen yet.
      expect(find.textContaining('Monthly billing runs 30 days'), findsNothing);
    });

    testWidgets('expanding a section reveals its copy', (tester) async {
      await tester.pumpWidget(_host(const BillingPoliciesScreen()));

      await tester.tap(find.text('Billing Policy'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Monthly billing runs 30 days'),
        findsOneWidget,
      );
    });

    testWidgets('the FAQ section reveals question and answer pairs',
        (tester) async {
      await tester.pumpWidget(_host(const BillingPoliciesScreen()));

      await tester.ensureVisible(find.text('Frequently Asked Questions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frequently Asked Questions'));
      await tester.pumpAndSettle();

      expect(find.text('Will I receive a refund?'), findsOneWidget);
      expect(find.text('Can I upgrade later?'), findsOneWidget);
      expect(
        find.textContaining('We retry failed payments 3 times'),
        findsOneWidget,
      );
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(const BillingPoliciesScreen()));
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('DashboardHeaderBar optional subtitle', () {
    testWidgets('renders one line when the subtitle is omitted',
        (tester) async {
      await tester.pumpWidget(
        _host(const Scaffold(body: DashboardHeaderBar(title: 'Only Title'))),
      );

      expect(find.text('Only Title'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('still renders both lines when a subtitle is supplied',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const Scaffold(
            body: DashboardHeaderBar(title: 'Title', subtitle: 'Subtitle'),
          ),
        ),
      );

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Subtitle'), findsOneWidget);
    });
  });
}
