import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/social_models.dart';
import 'package:propcid_app/providers/social_provider.dart';
import 'package:propcid_app/screens/social/social_accounts_screen.dart';
import 'package:propcid_app/screens/social/social_activity_screen.dart';
import 'package:propcid_app/screens/social/social_analytics_screen.dart';
import 'package:propcid_app/screens/social/social_campaigns_screen.dart';
import 'package:propcid_app/screens/social/social_hub_screen.dart';
import 'package:propcid_app/screens/social/social_leads_screen.dart';
import 'package:propcid_app/screens/social/social_preferences_screen.dart';
import 'package:propcid_app/widgets/shared/stat_kpi_card.dart';
import 'package:propcid_app/widgets/shared/toggle_row.dart';

import 'support/overflow_detector.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// Small screen used for every overflow probe.
void _useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 3, 568 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Clearly-fake lead data — never real contact details.
AdLead _lead({
  String id = 'lead-1',
  String? name = 'Placeholder Person',
  String? email = 'someone@example.invalid',
  String? phone = '+00 00000 00000',
  String status = 'new',
}) {
  return AdLead.fromJson({
    'id': id,
    'full_name': name,
    'email': email,
    'phone': phone,
    'status': status,
    'created_at': '2026-08-01T10:00:00Z',
  });
}

ShareLog _log({
  String id = 'log-1',
  String platform = 'facebook',
  String status = 'success',
  String contentType = 'property',
  String? contentId = 'c-1',
  String? error,
  String createdAt = '2026-08-03T10:00:00Z',
}) {
  return ShareLog.fromJson({
    'id': id,
    'platform': platform,
    'status': status,
    'content_type': contentType,
    'content_id': contentId,
    'error': error,
    'created_at': createdAt,
  });
}

ShareQueueItem _queueItem({
  String id = 'q-1',
  String platform = 'facebook',
  String status = 'success',
  String contentType = 'property',
  String? contentId = 'c-1',
  List<String> targets = const ['feed'],
  String? error,
  String createdAt = '2026-08-03T10:00:00Z',
}) {
  return ShareQueueItem.fromJson({
    'id': id,
    'user_id': 'u-1',
    'platform': platform,
    'status': status,
    'content_type': contentType,
    'content_id': contentId,
    'targets': targets,
    'error': error,
    'created_at': createdAt,
  });
}

void main() {
  group('formatMinorAmount', () {
    test('converts minor units and picks the currency symbol', () {
      expect(formatMinorAmount(199900), '₹1,999');
      expect(formatMinorAmount(50000, currency: 'USD'), r'$500');
      expect(formatMinorAmount(1234, currency: 'EUR'), '€12.34');
    });

    test('keeps decimals below 100 major units, drops them above', () {
      // React's rule: maximumFractionDigits 0 once the amount reaches 100.
      expect(formatMinorAmount(9999), '₹99.99');
      expect(formatMinorAmount(10000), '₹100');
    });

    test('null is an em dash, not a zero', () {
      expect(formatMinorAmount(null), '—');
    });

    test('groups the Indian way and keeps the sign', () {
      expect(formatMinorAmount(1234567800), '₹1,23,45,678');
      expect(formatMinorAmount(-50000), '-₹500');
    });
  });

  group('SocialAccount', () {
    test('defaults to disconnected', () {
      const account = SocialAccount();
      expect(account.connected, isFalse);
      expect(account.hasFacebookPage, isFalse);
      expect(account.hasInstagram, isFalse);
      expect(account.daysUntilExpiry, isNull);
    });

    test('maps the safe view columns', () {
      final account = SocialAccount.fromJson(const {
        'connected': true,
        'page_name': 'Placeholder Page',
        'instagram_username': 'placeholder_ig',
        'auto_refresh': true,
        'ads_capable': true,
        'ad_account_currency': 'INR',
        'fb_followers_count': 120,
        'ig_followers_count': 340,
      });

      expect(account.connected, isTrue);
      expect(account.hasFacebookPage, isTrue);
      expect(account.hasInstagram, isTrue);
      expect(account.pageName, 'Placeholder Page');
      expect(account.adsCapable, isTrue);
      expect(account.fbFollowersCount, 120);
    });

    test('a connected account with no page is not "has page"', () {
      final account = SocialAccount.fromJson(const {'connected': true});
      expect(account.hasFacebookPage, isFalse);
      expect(account.hasInstagram, isFalse);
    });
  });

  group('SocialPreferences', () {
    test('defaults match React\'s DEFAULT_PREFERENCES', () {
      const prefs = SocialPreferences.defaults;
      // All seven auto-share flags start off.
      expect(prefs.autoShareProperty, isFalse);
      expect(prefs.autoShareOpenHouses, isFalse);
      // Facebook, Instagram and the IG feed start on; the rest off.
      expect(prefs.fbEnabled, isTrue);
      expect(prefs.igEnabled, isTrue);
      expect(prefs.igFeed, isTrue);
      expect(prefs.igReel, isFalse);
      expect(prefs.fbStory, isFalse);
      expect(prefs.igStory, isFalse);
      expect(prefs.autoShareRule, 'all');
      expect(prefs.defaultHashtags, isEmpty);
    });

    test('maps every stored column', () {
      final prefs = SocialPreferences.fromJson(const {
        'auto_share_property': true,
        'auto_share_reels': true,
        'ig_reel': true,
        'fb_enabled': false,
        'default_hashtags': ['RealEstate', 'PropCid'],
        'default_cta': 'Call now',
        'auto_share_rule': 'manual',
      });

      expect(prefs.autoShareProperty, isTrue);
      expect(prefs.autoShareReels, isTrue);
      expect(prefs.igReel, isTrue);
      expect(prefs.fbEnabled, isFalse);
      expect(prefs.defaultHashtags, ['RealEstate', 'PropCid']);
      expect(prefs.defaultCta, 'Call now');
      expect(prefs.autoShareRuleLabel, 'Only when I choose');
    });
  });

  group('SocialAnalytics.fromLogs', () {
    test('counts only successes toward the totals', () {
      final analytics = SocialAnalytics.fromLogs([
        _log(id: '1'),
        _log(id: '2', platform: 'instagram'),
        _log(id: '3', status: 'failed', error: 'nope'),
      ], pending: 4);

      expect(analytics.totalShares, 2);
      expect(analytics.failed, 1);
      expect(analytics.pending, 4);
      expect(analytics.facebook, 1);
      expect(analytics.instagram, 1);
      expect(analytics.hasPublished, isTrue);
    });

    test('windows are relative to now', () {
      // Both timestamps are relative to now, which is the whole point of the
      // test. The recent one used to lean on the fixture's default
      // `2026-08-03`, so this passed on the day it was written and counted zero
      // shares "today" from the next day onward.
      final recent = DateTime.now().subtract(const Duration(hours: 2));
      final old = DateTime.now().subtract(const Duration(days: 45));
      final analytics = SocialAnalytics.fromLogs([
        _log(id: 'recent', createdAt: recent.toIso8601String()),
        _log(id: 'old', createdAt: old.toIso8601String()),
      ], pending: 0);

      expect(analytics.totalShares, 2);
      expect(analytics.today, 1);
      expect(analytics.week, 1);
      expect(analytics.month, 1);
    });

    test('ranks most-shared content and caps at five', () {
      final logs = <ShareLog>[
        for (var i = 0; i < 3; i++) _log(id: 'a$i', contentId: 'a'),
        for (var i = 0; i < 2; i++) _log(id: 'b$i', contentId: 'b'),
        for (var i = 0; i < 6; i++) _log(id: 'c$i', contentId: 'c$i'),
      ];

      final analytics = SocialAnalytics.fromLogs(logs, pending: 0);

      expect(analytics.topContent.length, 5);
      expect(analytics.topContent.first.count, 3);
      expect(analytics.topContent[1].count, 2);
    });

    test('empty logs produce an honest zero state', () {
      final analytics = SocialAnalytics.fromLogs(const [], pending: 0);
      expect(analytics.totalShares, 0);
      expect(analytics.hasPublished, isFalse);
      expect(analytics.topContent, isEmpty);
    });
  });

  group('AdLead', () {
    test('search matches name, email or phone', () {
      final lead = _lead(name: 'Placeholder Person');

      expect(lead.matches(''), isTrue);
      expect(lead.matches('placeholder'), isTrue);
      expect(lead.matches('example.invalid'), isTrue);
      expect(lead.matches('00000'), isTrue);
      expect(lead.matches('nothing-like-this'), isFalse);
    });

    test('falls back through name, email then phone for a display name', () {
      expect(_lead().displayName, 'Placeholder Person');
      expect(_lead(name: null).displayName, 'someone@example.invalid');
      expect(_lead(name: null, email: null).displayName, '+00 00000 00000');
      expect(
        _lead(name: null, email: null, phone: null).displayName,
        'Unnamed lead',
      );
    });
  });

  group('AdCampaign', () {
    test('prefers Meta\'s effective status and formats spend', () {
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Placeholder Campaign',
        'status': 'ACTIVE',
        'effective_status': 'PAUSED',
        'objective': 'LEAD_GENERATION',
        'spend_minor': 250000,
        'currency': 'INR',
        'impressions': 1000,
        'clicks': 25,
        'leads_count': 3,
      });

      expect(campaign.displayStatus, 'PAUSED');
      expect(campaign.spendDisplay, '₹2,500');
      expect(campaign.dailyBudgetDisplay, '—');
      expect(campaign.leadsCount, 3);
    });
  });

  group('SocialSection', () {
    test('starts loading and reports failure without clobbering the value',
        () async {
      final section = SocialAnalyticsSection();
      addTearDown(section.dispose);

      expect(section.loading, isTrue);
      expect(section.failed, isFalse);

      // Supabase is not initialised in a unit test, so the fetch throws.
      await section.loadFor('user-1');

      expect(section.loading, isFalse);
      expect(section.failed, isTrue);
      // Still the empty aggregate — never a fabricated one.
      expect(section.value.totalShares, 0);
    });

    test('holds the previous value when a reload fails', () async {
      final section = SocialLeadsSection();
      addTearDown(section.dispose);

      await section.load(() async => [_lead()]);
      expect(section.value.length, 1);
      expect(section.failed, isFalse);

      await section.load(() async => throw Exception('boom'));
      expect(section.failed, isTrue);
      expect(section.value.length, 1, reason: 'previous value kept');
    });

    test('notifying after dispose does not throw', () async {
      final section = SocialCampaignsSection();
      section.dispose();
      await section.load(() async => const <AdCampaign>[]);
    });
  });

  group('Accounts screen', () {
    testWidgets('reports both platforms as unconnected by default',
        (tester) async {
      await tester.pumpWidget(_host(SocialAccountsBody(
        account: null,
        loading: false,
        failed: false,
        onConnect: () {},
        onReconnect: () {},
        onDisconnect: () {},
        onRefreshStats: () {},
        onToggleAutoRefresh: (_) {},
        onChooseAdAccount: () {},
      )));

      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Facebook Page'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Instagram Business'), findsOneWidget);
      expect(find.text('Not linked'), findsOneWidget);
      expect(find.text('Connect Facebook & Instagram'), findsOneWidget);
    });

    testWidgets('shows the linked page and handle when connected',
        (tester) async {
      final account = SocialAccount.fromJson(const {
        'connected': true,
        'page_name': 'Placeholder Page',
        'instagram_username': 'placeholder_ig',
      });

      await tester.pumpWidget(_host(SocialAccountsBody(
        account: account,
        loading: false,
        failed: false,
        onConnect: () {},
        onReconnect: () {},
        onDisconnect: () {},
        onRefreshStats: () {},
        onToggleAutoRefresh: (_) {},
        onChooseAdAccount: () {},
      )));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Linked'), findsOneWidget);
      expect(find.text('Placeholder Page'), findsOneWidget);
      expect(find.text('@placeholder_ig'), findsOneWidget);
    });

    testWidgets('warns when the Meta token is close to expiring',
        (tester) async {
      final soon = DateTime.now().add(const Duration(days: 3));
      final account = SocialAccount.fromJson({
        'connected': true,
        'page_name': 'Placeholder Page',
        'token_expiry': soon.toIso8601String(),
      });

      await tester.pumpWidget(_host(SocialAccountsBody(
        account: account,
        loading: false,
        failed: false,
        onConnect: () {},
        onReconnect: () {},
        onDisconnect: () {},
        onRefreshStats: () {},
        onToggleAutoRefresh: (_) {},
        onChooseAdAccount: () {},
      )));

      expect(find.textContaining('expires in'), findsOneWidget);
    });

    testWidgets('a failed read never claims "not connected"', (tester) async {
      await tester.pumpWidget(_host(SocialAccountsBody(
        account: null,
        loading: false,
        failed: true,
        onConnect: () {},
        onReconnect: () {},
        onDisconnect: () {},
        onRefreshStats: () {},
        onToggleAutoRefresh: (_) {},
        onChooseAdAccount: () {},
      )));

      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(SocialAccountsBody(
        account: SocialAccount.fromJson(const {
          'connected': true,
          'page_name': 'A Very Long Placeholder Page Name For Layout Testing',
          'instagram_username': 'a_very_long_placeholder_handle_for_testing',
        }),
        loading: false,
        failed: false,
        onConnect: () {},
        onReconnect: () {},
        onDisconnect: () {},
        onRefreshStats: () {},
        onToggleAutoRefresh: (_) {},
        onChooseAdAccount: () {},
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Campaigns screen', () {
    testWidgets('empty state offers to create the first campaign',
        (tester) async {
      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: const [],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
      )));

      expect(find.text('Ad Campaigns'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('New Campaign'), findsOneWidget);
      expect(find.text('Create Your First Campaign'), findsOneWidget);
    });

    testWidgets('renders a campaign with its synced metrics', (tester) async {
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Placeholder Campaign',
        'status': 'ACTIVE',
        'objective': 'LEAD_GENERATION',
        'spend_minor': 250000,
        'currency': 'INR',
        'impressions': 1000,
        'clicks': 25,
        'leads_count': 3,
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
      )));

      expect(find.text('Placeholder Campaign'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('₹2,500'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('Create Your First Campaign'), findsNothing);
    });

    testWidgets('an ACTIVE campaign offers Pause and Archive, not Launch',
        (tester) async {
      String? firedAction;
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Active Campaign',
        'status': 'ACTIVE',
        'objective': 'OUTCOME_TRAFFIC',
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
        onAction: (c, action) => firedAction = action,
      )));

      expect(find.text('Launch'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(firedAction, 'pause');
    });

    testWidgets('a PAUSED campaign offers Launch and Archive, not Pause',
        (tester) async {
      String? firedAction;
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Paused Campaign',
        'status': 'PAUSED',
        'objective': 'OUTCOME_TRAFFIC',
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
        onAction: (c, action) => firedAction = action,
      )));

      expect(find.text('Launch'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Archive'), findsOneWidget);

      await tester.tap(find.text('Launch'));
      await tester.pump();
      expect(firedAction, 'resume');
    });

    testWidgets('an ARCHIVED campaign offers neither Launch, Pause nor Archive',
        (tester) async {
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Archived Campaign',
        'status': 'ARCHIVED',
        'objective': 'OUTCOME_TRAFFIC',
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
        onAction: (c, action) {},
      )));

      expect(find.text('Launch'), findsNothing);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('a busy campaign disables its own lifecycle buttons',
        (tester) async {
      var tapped = 0;
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Busy Campaign',
        'status': 'PAUSED',
        'objective': 'OUTCOME_TRAFFIC',
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        busyCampaignId: 'c1',
        onRefresh: () {},
        onNewCampaign: () {},
        onAction: (c, action) => tapped++,
      )));

      await tester.tap(find.text('Launch'));
      await tester.pump();
      expect(tapped, 0);
    });

    testWidgets('a campaign with last_error surfaces it', (tester) async {
      final campaign = AdCampaign.fromJson(const {
        'id': 'c1',
        'name': 'Broken Campaign',
        'status': 'ACTIVE',
        'objective': 'OUTCOME_TRAFFIC',
        'last_error': 'Your Facebook session expired — reconnect in Social ▸ Accounts.',
      });

      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [campaign],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
      )));

      expect(
        find.textContaining('Your Facebook session expired'),
        findsOneWidget,
      );
    });

    testWidgets('Refresh is relabelled and disabled while syncing',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: const [],
        loading: false,
        failed: false,
        syncing: true,
        onRefresh: () => tapped++,
        onNewCampaign: () {},
      )));

      expect(find.text('Refreshing…'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);

      await tester.tap(find.text('Refreshing…'));
      await tester.pump();
      expect(tapped, 0);
    });

    testWidgets('a failed load is distinguished from an empty one',
        (tester) async {
      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: const [],
        loading: false,
        failed: true,
        onRefresh: () {},
        onNewCampaign: () {},
      )));

      expect(find.textContaining("Couldn't load"), findsOneWidget);
      expect(find.text('Create Your First Campaign'), findsNothing);
    });

    testWidgets('New Campaign is disabled and relabelled while busy',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: const [],
        loading: false,
        failed: false,
        busy: true,
        onRefresh: () {},
        onNewCampaign: () => tapped++,
      )));

      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('New Campaign'), findsNothing);

      await tester.tap(find.text('Loading…'));
      await tester.pump();

      expect(tapped, 0);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(SocialCampaignsBody(
        campaigns: [
          AdCampaign.fromJson(const {
            'id': 'c1',
            'name': 'A Very Long Placeholder Campaign Name For Layout Testing',
            'status': 'ACTIVE',
            'objective': 'OUTCOME_LEADS_WITH_A_LONG_OBJECTIVE_NAME',
            'spend_minor': 1234567800,
            'currency': 'INR',
            'impressions': 9999999,
            'clicks': 123456,
            'leads_count': 4096,
          }),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onNewCampaign: () {},
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Leads screen', () {
    testWidgets('empty state explains how leads arrive', (tester) async {
      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: const [],
        loading: false,
        failed: false,
        onRefresh: () {},
        onExport: (_) {},
      )));

      expect(find.text('Leads'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.textContaining('No leads yet.'), findsOneWidget);
    });

    testWidgets('filters the list as you search', (tester) async {
      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: [
          _lead(id: '1', name: 'Alpha Placeholder'),
          _lead(id: '2', name: 'Beta Placeholder', email: 'beta@example.invalid'),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onExport: (_) {},
      )));

      expect(find.text('Alpha Placeholder'), findsOneWidget);
      expect(find.text('Beta Placeholder'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();

      expect(find.text('Alpha Placeholder'), findsOneWidget);
      expect(find.text('Beta Placeholder'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('No leads match'), findsOneWidget);
    });

    testWidgets('the status filter narrows the list', (tester) async {
      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: [
          _lead(id: '1', name: 'New Lead', status: 'new'),
          _lead(id: '2', name: 'Contacted Lead', status: 'contacted'),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onExport: (_) {},
      )));

      expect(find.text('New Lead'), findsOneWidget);
      expect(find.text('Contacted Lead'), findsOneWidget);

      // Open the status-filter dropdown (the one showing "All statuses") and
      // pick "Contacted".
      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contacted').last);
      await tester.pumpAndSettle();

      expect(find.text('New Lead'), findsNothing);
      expect(find.text('Contacted Lead'), findsOneWidget);
    });

    testWidgets('changing a lead\'s status is wired', (tester) async {
      AdLead? changedLead;
      String? changedStatus;
      final lead = _lead(id: '1', name: 'Alpha Placeholder', status: 'new');

      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: [lead],
        loading: false,
        failed: false,
        onRefresh: () {},
        onExport: (_) {},
        onStatusChange: (l, s) {
          changedLead = l;
          changedStatus = s;
        },
      )));

      // The lead's own status dropdown, currently showing "New".
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualified').last);
      await tester.pumpAndSettle();

      expect(changedLead?.id, '1');
      expect(changedStatus, 'qualified');
    });

    testWidgets('Refresh is relabelled while syncing, Export disabled when empty',
        (tester) async {
      var refreshed = 0;
      var exported = false;
      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: const [],
        loading: false,
        failed: false,
        syncing: true,
        onRefresh: () => refreshed++,
        onExport: (_) => exported = true,
      )));

      expect(find.text('Refreshing…'), findsOneWidget);
      await tester.tap(find.text('Refreshing…'));
      await tester.pump();
      expect(refreshed, 0);

      await tester.tap(find.text('Export CSV'));
      await tester.pump();
      expect(exported, isFalse);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(SocialLeadsBody(
        leads: [
          _lead(
            name: 'A Very Long Placeholder Lead Name For Layout Testing',
            email: 'a.very.long.placeholder.address@example.invalid',
          ),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onExport: (_) {},
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Preferences screen', () {
    testWidgets('renders all thirteen switches across two sections',
        (tester) async {
      await tester.pumpWidget(_host(const SocialPreferencesBody(
        preferences: SocialPreferences.defaults,
        loading: false,
        failed: false,
      )));

      expect(find.text('Auto-share'), findsOneWidget);
      expect(find.text('Default targets'), findsOneWidget);
      // Seven auto-share + six targets.
      expect(find.byType(ToggleRow), findsNWidgets(13));
      expect(find.byType(AppToggle), findsNWidgets(13));
    });

    testWidgets('switches reflect stored values and stay inert with no onChanged',
        (tester) async {
      final prefs = SocialPreferences.fromJson(const {
        'auto_share_property': true,
        'fb_enabled': true,
        'ig_enabled': false,
      });

      await tester.pumpWidget(_host(SocialPreferencesBody(
        preferences: prefs,
        loading: false,
        failed: false,
      )));

      final toggles = tester
          .widgetList<AppToggle>(find.byType(AppToggle))
          .toList();

      // No onChanged/onSave supplied (e.g. still loading) -> every switch
      // stays non-interactive rather than silently discarding a tap.
      expect(toggles.every((t) => t.onChanged == null), isTrue);
      // Properties is on, Projects is off — the stored values, not defaults.
      expect(toggles.first.value, isTrue);
      expect(toggles[1].value, isFalse);
    });

    testWidgets('editing a switch and saving round-trips through the callbacks',
        (tester) async {
      var edited = false;
      var saved = false;

      await tester.pumpWidget(_host(SocialPreferencesBody(
        preferences: SocialPreferences.defaults,
        loading: false,
        failed: false,
        onChanged: (_) => edited = true,
        onSave: () => saved = true,
      )));

      final toggles = tester.widgetList<AppToggle>(find.byType(AppToggle)).toList();
      expect(toggles.every((t) => t.onChanged != null), isTrue);

      await tester.tap(find.byType(AppToggle).first);
      await tester.pump();
      expect(edited, isTrue);

      await tester.ensureVisible(find.text('Save settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save settings'));
      await tester.pump();
      expect(saved, isTrue);
    });

    testWidgets('shows caption defaults, or an honest placeholder',
        (tester) async {
      await tester.pumpWidget(_host(SocialPreferencesBody(
        preferences: SocialPreferences.fromJson(const {
          'default_hashtags': ['RealEstate', 'PropCid'],
          'auto_share_rule': 'all',
        }),
        loading: false,
        failed: false,
      )));

      expect(find.text('Every item'), findsOneWidget);
      final hashtagsField =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(hashtagsField.controller?.text, 'RealEstate, PropCid');
      // No CTA stored.
      final ctaField = tester.widget<TextField>(find.byType(TextField).last);
      expect(ctaField.controller?.text, isEmpty);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(const SocialPreferencesBody(
        preferences: SocialPreferences.defaults,
        loading: false,
        failed: false,
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Activity screen', () {
    testWidgets('empty state points at Publish Everywhere', (tester) async {
      await tester.pumpWidget(_host(SocialActivityBody(
        items: const [],
        loading: false,
        failed: false,
        onRefresh: () {},
        onRetry: (_) {},
      )));

      expect(find.text('Publishing Activity'), findsOneWidget);
      expect(find.textContaining('Nothing published yet.'), findsOneWidget);
    });

    testWidgets('renders a failed publish with its error and status label',
        (tester) async {
      await tester.pumpWidget(_host(SocialActivityBody(
        items: [_queueItem(status: 'failed', error: 'Token expired')],
        loading: false,
        failed: false,
        onRefresh: () {},
        onRetry: (_) {},
      )));

      expect(find.textContaining('Token expired'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('every queue status gets its own label', (tester) async {
      await tester.pumpWidget(_host(SocialActivityBody(
        items: [
          _queueItem(id: 'q1', status: 'queued'),
          _queueItem(id: 'q2', status: 'processing'),
          _queueItem(id: 'q3', status: 'success'),
          _queueItem(id: 'q4', status: 'canceled'),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onRetry: (_) {},
      )));

      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(find.text('Canceled'), findsOneWidget);
      // None of the four above are failed, so no Retry button should appear.
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets('refresh is wired', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(_host(SocialActivityBody(
        items: const [],
        loading: false,
        failed: false,
        onRefresh: () => refreshed++,
        onRetry: (_) {},
      )));

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(refreshed, 1);
    });

    testWidgets('retry is offered only on a failed row, and is wired',
        (tester) async {
      ShareQueueItem? retried;
      final failedItem = _queueItem(status: 'failed', error: 'Token expired');
      await tester.pumpWidget(_host(SocialActivityBody(
        items: [failedItem, _queueItem(status: 'success')],
        loading: false,
        failed: false,
        onRefresh: () {},
        onRetry: (item) => retried = item,
      )));

      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();

      expect(retried, same(failedItem));
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(SocialActivityBody(
        items: [
          _queueItem(
            status: 'failed',
            error: 'A very long placeholder error message that keeps going on',
            contentType: 'a_very_long_content_type_name',
            targets: const ['feed', 'story'],
          ),
        ],
        loading: false,
        failed: false,
        onRefresh: () {},
        onRetry: (_) {},
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Analytics screen', () {
    testWidgets('renders the design\'s six KPIs', (tester) async {
      await tester.pumpWidget(_host(const SocialAnalyticsBody(
        analytics: SocialAnalytics.empty,
        loading: false,
        failed: false,
      )));

      expect(find.text('Analytics'), findsOneWidget);
      for (final label in const [
        'Total published',
        'Today',
        'This week',
        'This month',
        'Pending',
        'Failed',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      expect(find.byType(MetricCard), findsNWidgets(6));
      expect(find.text('No published posts yet.'), findsOneWidget);
      expect(find.text('Nothing yet.'), findsOneWidget);
    });

    testWidgets('shows the platform split once something is published',
        (tester) async {
      final analytics = SocialAnalytics.fromLogs([
        _log(id: '1'),
        _log(id: '2', platform: 'instagram'),
        _log(id: '3', platform: 'instagram'),
      ], pending: 0);

      await tester.pumpWidget(_host(SocialAnalyticsBody(
        analytics: analytics,
        loading: false,
        failed: false,
      )));

      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('No published posts yet.'), findsNothing);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('a failed load shows em dashes, not zeros', (tester) async {
      await tester.pumpWidget(_host(const SocialAnalyticsBody(
        analytics: SocialAnalytics.empty,
        loading: false,
        failed: true,
      )));

      expect(find.text('—'), findsNWidgets(6));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shimmers while loading', (tester) async {
      await tester.pumpWidget(_host(const SocialAnalyticsBody(
        analytics: SocialAnalytics.empty,
        loading: true,
        failed: false,
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MetricCardGridShimmer), findsOneWidget);
      expect(find.text('Total published'), findsNothing);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(_host(SocialAnalyticsBody(
        analytics: SocialAnalytics.fromLogs(
          [for (var i = 0; i < 40; i++) _log(id: '$i', contentId: 'c$i')],
          pending: 999999,
        ),
        loading: false,
        failed: false,
      )));

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Social hub routing', () {
    test('the six leaf routes are distinct', () {
      final routes = {
        AppConstants.socialAccountsScreen,
        AppConstants.socialCampaignsScreen,
        AppConstants.socialLeadsScreen,
        AppConstants.socialPreferencesScreen,
        AppConstants.socialActivityScreen,
        AppConstants.socialAnalyticsScreen,
      };
      expect(routes.length, 6);
      expect(AppConstants.socialAccountsScreen, '/social/accounts');
      expect(AppConstants.socialAnalyticsScreen, '/social/analytics');
    });

    testWidgets('every hub card now pushes its real route, not a placeholder',
        (tester) async {
      final pushed = <String>[];
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const SocialHubScreen(),
        onGenerateRoute: (settings) {
          if (settings.name != null) pushed.add(settings.name!);
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          );
        },
      ));

      for (final label in const [
        'Social Accounts',
        'Social Campaigns',
        'Social Leads',
        'Social Preferences',
        'Social Activity',
        'Social Analytics',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        // The pushed route covers the hub; come back for the next card.
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
      }

      expect(pushed, [
        AppConstants.socialAccountsScreen,
        AppConstants.socialCampaignsScreen,
        AppConstants.socialLeadsScreen,
        AppConstants.socialPreferencesScreen,
        AppConstants.socialActivityScreen,
        AppConstants.socialAnalyticsScreen,
      ]);
    });
  });

  group('ToggleRow bordered variant', () {
    testWidgets('is 46 dp tall and keeps the default switch geometry',
        (tester) async {
      await tester.pumpWidget(_host(
        const Scaffold(
          body: Center(
            child: ToggleRow(label: 'Properties', value: false, bordered: true),
          ),
        ),
      ));

      final row = tester.getSize(find.byType(ToggleRow));
      expect(row.height, 46);

      final track = tester.getSize(
        find.descendant(
          of: find.byType(AppToggle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(track.width, 40);
      expect(track.height, 24);
    });

    testWidgets('the grouped variant is unchanged by Phase 8', (tester) async {
      await tester.pumpWidget(_host(
        const Scaffold(
          body: Center(
            child: ToggleRow(
              label: 'Properties',
              description: 'A description that makes the row taller',
              value: true,
            ),
          ),
        ),
      ));

      // Not pinned to 46: the grouped variant still sizes to its content.
      expect(find.text('A description that makes the row taller'),
          findsOneWidget);
      expect(find.byType(ToggleRow), findsOneWidget);
    });
  });
}
