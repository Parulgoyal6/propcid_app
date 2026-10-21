import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/widgets/segmented_tab_pill.dart';
import 'package:propcid_app/models/network_models.dart';
import 'package:propcid_app/models/network_relationship.dart';
import 'package:propcid_app/models/network_stats.dart';
import 'package:propcid_app/providers/async_section.dart';
import 'package:propcid_app/providers/network_section_provider.dart';
import 'package:propcid_app/screens/network/my_leads_screen.dart';
import 'package:propcid_app/screens/network/my_networks_screen.dart';
import 'package:propcid_app/screens/network/my_referrals_screen.dart';
import 'package:propcid_app/screens/network/network_communication_screen.dart';
import 'package:propcid_app/screens/network/network_hub_screen.dart';
import 'package:propcid_app/widgets/shared/app_chart_wrapper.dart';
import 'package:propcid_app/widgets/shared/stat_kpi_card.dart';
import 'package:propcid_app/widgets/shared/toggle_row.dart';

// Both paths onto the promoted section base, to prove the Phase 9 shim resolves
// to the same class.
import 'package:propcid_app/providers/social_provider.dart' as social;

import 'support/overflow_detector.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void _useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 3, 568 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const _viewer = 'viewer-1';

NetworkMembership _membership({
  String id = 'm-1',
  String builderId = 'builder-1',
  String memberId = _viewer,
  String memberType = 'broker',
  String? status = 'accepted',
  bool verified = true,
  num? rate = 2.5,
}) {
  return NetworkMembership.fromJson({
    'id': id,
    'builder_id': builderId,
    'member_id': memberId,
    'member_type': memberType,
    'status': status,
    'verified': verified,
    'commission_rate': rate,
    'auto_convert_leads': true,
    'created_at': '2026-08-01T10:00:00Z',
  }, viewerId: _viewer);
}

NetworkRelationship _relationship({
  String id = 'r-1',
  String builderId = 'builder-1',
  String memberId = _viewer,
  String memberType = 'broker',
  String? status = 'accepted',
  bool verified = true,
  num? rate = 2.5,
  String? counterpartUserType,
  String? counterpartName,
  String? counterpartCompanyName,
}) {
  return NetworkRelationship.classify(
    {
      'id': id,
      'builder_id': builderId,
      'member_id': memberId,
      'member_type': memberType,
      'status': status,
      'verified': verified,
      'commission_rate': rate,
      'auto_convert_leads': true,
      'created_at': '2026-08-01T10:00:00Z',
    },
    viewerId: _viewer,
    counterpartUserType: counterpartUserType,
    counterpartDisplayName: counterpartName,
    counterpartCompanyName: counterpartCompanyName,
  );
}

NetworkLead _lead({String id = 'l-1', String status = 'pending'}) {
  return NetworkLead.fromJson({
    'id': id,
    'lead_type': 'property_inquiry',
    'priority': 'high',
    'status': status,
    'assignment_method': 'manual',
    'auto_assigned': false,
    'created_at': '2026-08-01T10:00:00Z',
  });
}

void main() {
  group('formatRupeeAmount', () {
    test('groups whole rupees the Indian way', () {
      // These tables store numeric rupees, not minor units — no division.
      expect(formatRupeeAmount(0), '₹0');
      expect(formatRupeeAmount(24500), '₹24,500');
      expect(formatRupeeAmount(124500), '₹1,24,500');
      expect(formatRupeeAmount(10000000), '₹1,00,00,000');
      expect(formatRupeeAmount(-2500), '-₹2,500');
    });
  });

  group('NetworkMembership', () {
    test('records which side of the relationship the viewer is on', () {
      final asMember = _membership();
      expect(asMember.isBuilderSide, isFalse);

      final asBuilder = _membership(builderId: _viewer, memberId: 'other');
      expect(asBuilder.isBuilderSide, isTrue);
    });

    test('a null status reads as pending, matching React', () {
      final row = _membership(status: null);
      expect(row.status, 'pending');
      expect(row.isAccepted, isFalse);
    });

    test('labels the member type and trims the commission rate', () {
      expect(_membership().memberTypeLabel, 'Broker');
      expect(_membership(rate: 2.5).commissionRateLabel, '2.5%');
      expect(_membership(rate: 3).commissionRateLabel, '3%');
      expect(_membership(rate: null).commissionRateLabel, isNull);
    });
  });

  group('LeadStatusCounts', () {
    test('counts the four design statuses', () {
      final counts = LeadStatusCounts.fromLeads([
        _lead(id: '1'),
        _lead(id: '2'),
        _lead(id: '3', status: 'assigned'),
        _lead(id: '4', status: 'contacted'),
        _lead(id: '5', status: 'converted'),
        // An unrecognised status is counted in none of the four buckets.
        _lead(id: '6', status: 'archived'),
      ]);

      expect(counts.pending, 2);
      expect(counts.assigned, 1);
      expect(counts.contacted, 1);
      expect(counts.converted, 1);
      expect(counts.total, 5);
    });

    test('empty is all zeros', () {
      expect(LeadStatusCounts.fromLeads(const []).total, 0);
      expect(LeadStatusCounts.empty.pending, 0);
    });
  });

  group('ReferralSummary', () {
    test('derives all four KPIs from the two lists', () {
      final referrals = [
        NetworkReferral.fromJson(const {
          'id': 'r1',
          'referral_type': 'property',
          'status': 'converted',
          'commission_status': 'paid',
          'commission_amount': 5000,
        }),
        NetworkReferral.fromJson(const {
          'id': 'r2',
          'referral_type': 'property',
          'status': 'pending',
          'commission_status': 'pending',
        }),
      ];

      final commissions = [
        NetworkCommission.fromJson(const {
          'id': 'c1',
          'commission_type': 'referral',
          'amount': 5000,
          'status': 'paid',
        }),
        NetworkCommission.fromJson(const {
          'id': 'c2',
          'commission_type': 'referral',
          'amount': 2500,
          'status': 'pending',
        }),
      ];

      final summary = ReferralSummary.from(
        referrals: referrals,
        commissions: commissions,
      );

      expect(summary.totalReferrals, 2);
      expect(summary.converted, 1);
      // Total is every commission; paid out is only the settled ones.
      expect(summary.totalCommissions, 7500);
      expect(summary.paidOut, 5000);
      expect(summary.totalCommissionsDisplay, '₹7,500');
      expect(summary.paidOutDisplay, '₹5,000');
    });

    test('an empty bundle summarises to zeros', () {
      const bundle = ReferralBundle.empty;
      expect(bundle.summary.totalReferrals, 0);
      expect(bundle.summary.totalCommissionsDisplay, '₹0');
    });
  });

  group('NetworkChannel', () {
    test('humanises the stored purpose token', () {
      final channel = NetworkChannel.fromJson(const {
        'id': 'ch1',
        'channel_id': 'c1',
        'channel_purpose': 'lead_distribution',
        'is_auto_join': true,
        'member_types': ['broker', 'influencer'],
      });

      expect(channel.purposeLabel, 'Lead distribution');
      expect(channel.isAutoJoin, isTrue);
      expect(channel.memberTypes, ['broker', 'influencer']);
    });

    test('tolerates a missing member_types array', () {
      final channel = NetworkChannel.fromJson(const {
        'id': 'ch1',
        'channel_id': 'c1',
        'channel_purpose': '',
      });
      expect(channel.memberTypes, isEmpty);
      expect(channel.purposeLabel, 'Channel');
    });
  });

  group('NetworkSection', () {
    test('starts loading and flags failure without fabricating data', () async {
      final section = NetworkMembershipsSection();
      addTearDown(section.dispose);

      expect(section.loading, isTrue);
      expect(section.failed, isFalse);

      // Supabase is not initialised in a unit test, so the fetch throws.
      await section.loadFor(_viewer);

      expect(section.loading, isFalse);
      expect(section.failed, isTrue);
      expect(section.value, isEmpty);
    });

    test('derives lead counts from the loaded list', () async {
      final section = NetworkLeadsSection();
      addTearDown(section.dispose);

      await section.load(
        () async => [_lead(), _lead(id: '2', status: 'converted')],
      );

      expect(section.counts.pending, 1);
      expect(section.counts.converted, 1);
    });

    test('keeps the previous value when a reload fails', () async {
      final section = NetworkChannelsSection();
      addTearDown(section.dispose);

      await section.load(
        () async => [
          NetworkChannel.fromJson(const {
            'id': 'ch1',
            'channel_id': 'c1',
            'channel_purpose': 'general',
          }),
        ],
      );
      expect(section.value.length, 1);

      await section.load(() async => throw Exception('boom'));
      expect(section.failed, isTrue);
      expect(section.value.length, 1, reason: 'previous value kept');
    });

    test('is the same promoted base the Social sections use', () {
      // Phase 9 promoted AsyncSection out of the Social module; both families
      // must resolve to that one implementation, not two copies.
      expect(NetworkMembershipsSection(), isA<AsyncSection<dynamic>>());
      expect(social.SocialLeadsSection(), isA<AsyncSection<dynamic>>());
    });
  });

  group('My Networks screen', () {
    testWidgets('empty state matches the design copy', (tester) async {
      await tester.pumpWidget(
        _host(
          const MyNetworksBody(
            relationships: [],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('My Networks'), findsOneWidget);
      expect(find.text('Current Networks'), findsOneWidget);
      expect(find.text('No Network Memberships'), findsOneWidget);
      expect(
        find.textContaining("haven't joined any networks"),
        findsOneWidget,
      );
    });

    testWidgets('renders an owned network member by real profile name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MyNetworksBody(
            relationships: [
              _relationship(
                builderId: _viewer,
                memberId: 'other-1',
                counterpartUserType: 'broker',
                counterpartName: 'Amy Rao',
              ),
            ],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Current Network Members'), findsOneWidget);
      expect(find.text('Amy Rao'), findsOneWidget);
      expect(find.text('accepted'), findsOneWidget);
      expect(find.text('Broker'), findsOneWidget);
      expect(find.text('2.5%'), findsOneWidget);
      expect(find.text('No Network Memberships'), findsNothing);
      // A role-only placeholder must never stand in for a resolved name.
      expect(find.text('Member of a builder network'), findsNothing);
    });

    testWidgets(
      "shows the person's own name first, with their company as a subtitle",
      (tester) async {
        await tester.pumpWidget(
          _host(
            MyNetworksBody(
              relationships: [
                _relationship(
                  builderId: _viewer,
                  memberId: 'other-1',
                  counterpartUserType: 'broker',
                  counterpartName: 'sneha',
                  counterpartCompanyName: 'new world',
                ),
              ],
              loading: false,
              failed: false,
            ),
          ),
        );

        // The name is the primary label; the company is a secondary line,
        // never a replacement for it.
        expect(find.text('sneha'), findsOneWidget);
        expect(find.text('new world'), findsOneWidget);
      },
    );

    testWidgets('Leave Network calls onLeave with the tapped relationship', (
      tester,
    ) async {
      // MyNetworksBody itself is the dumb, provider-free presentation layer —
      // the confirm dialog lives in `_MyNetworksViewState._confirmAndLeave`,
      // which wraps this exact callback when the real screen is reached
      // through `MyNetworksScreen`. This only verifies the button reaches
      // the right callback with the right row.
      NetworkRelationship? left;
      final relationship = _relationship(
        builderId: _viewer,
        memberId: 'other-1',
        counterpartUserType: 'broker',
        counterpartName: 'Amy Rao',
      );
      await tester.pumpWidget(
        _host(
          MyNetworksBody(
            relationships: [relationship],
            loading: false,
            failed: false,
            onLeave: (r) => left = r,
          ),
        ),
      );

      await tester.tap(find.text('Leave Network'));
      await tester.pumpAndSettle();

      expect(left, isNotNull);
      expect(left!.id, relationship.id);
    });

    testWidgets('no onLeave callback means no Leave Network button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MyNetworksBody(
            relationships: [
              _relationship(
                builderId: _viewer,
                memberId: 'other-1',
                counterpartUserType: 'broker',
              ),
            ],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Leave Network'), findsNothing);
    });

    testWidgets(
      'a row mid-leave shows a busy state and cannot be tapped again',
      (tester) async {
        final relationship = _relationship(
          builderId: _viewer,
          memberId: 'other-1',
          counterpartUserType: 'broker',
        );
        var tapCount = 0;
        await tester.pumpWidget(
          _host(
            MyNetworksBody(
              relationships: [relationship],
              loading: false,
              failed: false,
              leavingRelationshipId: relationship.id,
              onLeave: (_) => tapCount++,
            ),
          ),
        );

        expect(find.text('Leaving…'), findsOneWidget);
        await tester.tap(find.text('Leaving…'), warnIfMissed: false);
        expect(tapCount, 0);
      },
    );

    testWidgets('renders a joined builder network by real profile name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MyNetworksBody(
            relationships: [
              _relationship(
                builderId: 'builder-x',
                memberId: _viewer,
                counterpartUserType: 'builder',
                counterpartName: 'Big Builder Co',
              ),
            ],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Networks Joined'), findsOneWidget);
      expect(find.text('Big Builder Co'), findsOneWidget);
      expect(find.text('Builder'), findsOneWidget);
    });

    testWidgets(
      'a peer connection is visible but never shows commission details',
      (tester) async {
        await tester.pumpWidget(
          _host(
            MyNetworksBody(
              relationships: [
                _relationship(
                  builderId: _viewer,
                  memberId: 'other-2',
                  counterpartUserType: 'individual',
                  counterpartName: 'Casual Contact',
                ),
              ],
              loading: false,
              failed: false,
            ),
          ),
        );

        expect(find.text('Peer Connections'), findsOneWidget);
        expect(find.text('Casual Contact'), findsOneWidget);
        // Commission details are only meaningful for an owned network member.
        expect(find.text('2.5%'), findsNothing);
        expect(find.text('Commission rate'), findsNothing);
      },
    );

    testWidgets('a failed load is distinguished from an empty one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const MyNetworksBody(relationships: [], loading: false, failed: true),
        ),
      );

      expect(find.text("Couldn't load your networks"), findsOneWidget);
      expect(find.text('No Network Memberships'), findsNothing);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(
        _host(
          MyNetworksBody(
            relationships: [
              _relationship(
                builderId: _viewer,
                memberId: 'other-3',
                counterpartUserType: 'broker',
                counterpartName:
                    'A Very Long Counterpart Display Name For Layout Testing',
              ),
            ],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('My Leads screen', () {
    testWidgets('renders the four status KPIs and the design copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MyLeadsBody(
            leads: const [],
            loading: false,
            failed: false,
            onSettings: () {},
          ),
        ),
      );

      expect(find.text('My Leads'), findsOneWidget);
      expect(find.text('Lead Distribution System'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      for (final label in const [
        'Pending',
        'Assigned',
        'Contacted',
        'Converted',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      expect(find.byType(MetricCard), findsNWidgets(4));
      expect(find.text('No Leads Available'), findsOneWidget);
    });

    testWidgets('counts drive the KPI values', (tester) async {
      await tester.pumpWidget(
        _host(
          MyLeadsBody(
            leads: [
              _lead(id: '1'),
              _lead(id: '2'),
              _lead(id: '3', status: 'converted'),
            ],
            loading: false,
            failed: false,
            onSettings: () {},
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('property_inquiry'), findsNWidgets(3));
      expect(find.text('No Leads Available'), findsNothing);
    });

    testWidgets('a failed load shows em dashes, not zeros', (tester) async {
      await tester.pumpWidget(
        _host(
          MyLeadsBody(
            leads: const [],
            loading: false,
            failed: true,
            onSettings: () {},
          ),
        ),
      );

      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('Settings is wired', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _host(
          MyLeadsBody(
            leads: const [],
            loading: false,
            failed: false,
            onSettings: () => tapped++,
          ),
        ),
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(
        _host(
          MyLeadsBody(
            leads: [_lead()],
            loading: false,
            failed: false,
            onSettings: () {},
          ),
        ),
      );

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('My Referrals screen', () {
    testWidgets('opens on Overview with four KPIs', (tester) async {
      await tester.pumpWidget(
        _host(
          MyReferralsBody(
            bundle: ReferralBundle.empty,
            loading: false,
            failed: false,
            onCreateReferral: () {},
          ),
        ),
      );

      expect(find.text('My Referrals'), findsOneWidget);
      expect(find.text('Referral & Commission System'), findsOneWidget);
      expect(find.text('Create Referral'), findsOneWidget);

      expect(find.byType(SegmentedTabPill), findsOneWidget);
      for (final label in const [
        'Total Referrals',
        'Converted',
        'Total Commissions',
        'Paid Out',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('No referral activity yet'), findsOneWidget);
    });

    testWidgets('each sub-tab renders its own empty state', (tester) async {
      await tester.pumpWidget(
        _host(
          MyReferralsBody(
            bundle: ReferralBundle.empty,
            loading: false,
            failed: false,
            onCreateReferral: () {},
          ),
        ),
      );

      await tester.tap(find.text('Referrals'));
      await tester.pumpAndSettle();
      expect(find.text('No referrals yet'), findsOneWidget);

      await tester.tap(find.text('Commissions'));
      await tester.pumpAndSettle();
      expect(find.text('No commissions yet'), findsOneWidget);

      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('Referral Performance'), findsOneWidget);
      // Reuses the dashboard chart rather than a second painter.
      expect(find.byType(DashboardLineChart), findsOneWidget);
      expect(find.text('No performance data yet'), findsOneWidget);
    });

    testWidgets('Performance plots one point per scored period', (
      tester,
    ) async {
      final bundle = ReferralBundle(
        performance: [
          NetworkPerformance.fromJson(const {
            'id': 'p1',
            'period_start': '2026-06-01',
            'performance_score': 40,
          }),
          NetworkPerformance.fromJson(const {
            'id': 'p2',
            'period_start': '2026-07-01',
            'performance_score': 80,
          }),
        ],
      );

      await tester.pumpWidget(
        _host(
          MyReferralsBody(
            bundle: bundle,
            loading: false,
            failed: false,
            onCreateReferral: () {},
          ),
        ),
      );

      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      final chart = tester.widget<DashboardLineChart>(
        find.byType(DashboardLineChart),
      );
      expect(chart.points.length, 2);
      expect(find.text('No performance data yet'), findsNothing);
    });

    testWidgets('a failed load shows em dashes on the Overview KPIs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MyReferralsBody(
            bundle: ReferralBundle.empty,
            loading: false,
            failed: true,
            onCreateReferral: () {},
          ),
        ),
      );

      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('₹0'), findsNothing);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      final bundle = ReferralBundle(
        referrals: [
          NetworkReferral.fromJson(const {
            'id': 'r1',
            'referral_type': 'a_very_long_referral_type_token_for_layout',
            'status': 'converted',
            'commission_status': 'pending_review_with_long_token',
            'commission_amount': 12345678,
          }),
        ],
        commissions: [
          NetworkCommission.fromJson(const {
            'id': 'c1',
            'commission_type': 'a_very_long_commission_type_token',
            'amount': 12345678,
            'status': 'paid',
          }),
        ],
      );

      await tester.pumpWidget(
        _host(
          MyReferralsBody(
            bundle: bundle,
            loading: false,
            failed: false,
            onCreateReferral: () {},
          ),
        ),
      );
      expect(overflowingBoxes(tester), isEmpty, reason: 'Overview');

      await tester.tap(find.text('Commissions'));
      await tester.pumpAndSettle();
      expect(overflowingBoxes(tester), isEmpty, reason: 'Commissions');
    });
  });

  group('Communication screen', () {
    testWidgets('opens on Channels with the design copy', (tester) async {
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: const [],
            loading: false,
            failed: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      expect(find.text('Network Communication'), findsOneWidget);
      expect(find.text('Network Communication Hub'), findsOneWidget);
      expect(find.text('Create Channel'), findsOneWidget);
      expect(find.text('Bulk Message'), findsOneWidget);
      expect(find.text('Network Channels'), findsOneWidget);
      expect(find.text('No Channels Created'), findsOneWidget);
      expect(find.text('Create First Channel'), findsOneWidget);
    });

    testWidgets(
      'a broker/influencer/individual sees the exact same Create Channel and '
      'Bulk Message controls a builder does — the portal has no role check here',
      (tester) async {
        await tester.pumpWidget(
          _host(
            NetworkCommunicationBody(
              channels: const [],
              loading: false,
              failed: false,
              isBuilder: false,
              onCreateChannel: () {},
              onBulkMessage: () {},
            ),
          ),
        );

        expect(find.text('Network Channels'), findsOneWidget);
        expect(find.text('Create Channel'), findsOneWidget);
        expect(find.text('Bulk Message'), findsOneWidget);
        expect(find.text('Create First Channel'), findsOneWidget);
      },
    );

    testWidgets('renders a channel with its purpose and auto-join flag', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: [
              NetworkChannel.fromJson(const {
                'id': 'ch1',
                'channel_id': 'c1',
                'channel_purpose': 'lead_distribution',
                'is_auto_join': true,
                'member_types': ['broker'],
              }),
            ],
            loading: false,
            failed: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      expect(find.text('Lead distribution'), findsOneWidget);
      expect(find.text('Auto-join'), findsOneWidget);
      expect(find.text('No Channels Created'), findsNothing);
    });

    testWidgets('Messaging and Settings sub-tabs render', (tester) async {
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: const [],
            loading: false,
            failed: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      await tester.tap(find.text('Messaging'));
      await tester.pumpAndSettle();
      // Same card for every role — see `_MessagingTab`'s own note.
      expect(find.text('Send Messages to Your Network'), findsOneWidget);
      expect(find.text('Compose Message'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Channel notifications'), findsOneWidget);
      expect(find.text('Allow member invites'), findsOneWidget);
      expect(find.byType(ToggleRow), findsNWidgets(2));
    });

    testWidgets('the two Settings switches report, and are inert', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: [
              NetworkChannel.fromJson(const {
                'id': 'ch1',
                'channel_id': 'c1',
                'channel_purpose': 'general',
                'is_auto_join': true,
              }),
            ],
            loading: false,
            failed: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final toggles = tester
          .widgetList<AppToggle>(find.byType(AppToggle))
          .toList();
      expect(toggles.length, 2);
      // Read-only: neither can be changed.
      expect(toggles.every((t) => t.onChanged == null), isTrue);
      // A channel exists and it is auto-join, so both read as on.
      expect(toggles[0].value, isTrue);
      expect(toggles[1].value, isTrue);

      expect(find.textContaining('reflect your channel setup'), findsOneWidget);
    });

    testWidgets('a failed load never reports the switches as on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: const [],
            loading: false,
            failed: true,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      expect(find.text("Couldn't load channels"), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final toggles = tester
          .widgetList<AppToggle>(find.byType(AppToggle))
          .toList();
      expect(toggles.every((t) => t.value == false), isTrue);
    });

    testWidgets('lays out without overflow on a small screen', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: [
              NetworkChannel.fromJson(const {
                'id': 'ch1',
                'channel_id': 'c1',
                'channel_purpose': 'a_very_long_channel_purpose_token_here',
                'is_auto_join': true,
                'member_types': ['broker', 'influencer', 'agent'],
              }),
            ],
            loading: false,
            failed: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
          ),
        ),
      );

      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('Network hub routing', () {
    test('the four leaf routes are distinct', () {
      final routes = {
        AppConstants.myNetworksScreen,
        AppConstants.myLeadsScreen,
        AppConstants.myReferralsScreen,
        AppConstants.networkCommunicationScreen,
      };
      expect(routes.length, 4);
      expect(AppConstants.myNetworksScreen, '/network/memberships');
      expect(AppConstants.networkCommunicationScreen, '/network/communication');
    });

    testWidgets('every hub card now pushes its real route', (tester) async {
      final pushed = <String>[];
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
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

      for (final label in const [
        'My Networks',
        'My Referrals',
        'Communication',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
      }

      expect(pushed, [
        AppConstants.myNetworksScreen,
        AppConstants.myReferralsScreen,
        AppConstants.networkCommunicationScreen,
      ]);
    });

    testWidgets(
      'a builder additionally gets an Analytics card pushing the real route',
      (tester) async {
        final pushed = <String>[];
        final navigatorKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: const NetworkHubBody(
              stats: NetworkStats.empty,
              loading: false,
              failed: false,
              isBuilder: true,
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

        await tester.ensureVisible(find.text('Analytics'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Analytics'));
        await tester.pumpAndSettle();

        expect(pushed, contains(AppConstants.networkAnalyticsScreen));
      },
    );

    testWidgets('a non-builder never sees the Analytics card', (tester) async {
      await tester.pumpWidget(
        _host(
          const NetworkHubBody(
            stats: NetworkStats.empty,
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Analytics'), findsNothing);
    });
  });
}
