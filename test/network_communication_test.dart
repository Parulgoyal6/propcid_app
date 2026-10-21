import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:propcid_app/models/network_models.dart';
import 'package:propcid_app/providers/network_communication_provider.dart';
import 'package:propcid_app/screens/network/network_communication_screen.dart';
import 'package:propcid_app/screens/network/widgets/bulk_message_sheet.dart';
import 'package:propcid_app/screens/network/widgets/create_network_channel_sheet.dart';
import 'package:propcid_app/services/network_communication_service.dart';
import 'package:propcid_app/widgets/shared/toggle_row.dart';

import 'support/fake_network_communication_service.dart';
import 'support/overflow_detector.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// These sheets are taller than the default 600 dp test viewport and scroll
/// internally, so a button below the fold needs scrolling into view before
/// it can be tapped — the same pattern `phase9_network_test.dart` uses for
/// the hub's own long-scrolling cards.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 3, 568 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

NetworkChannel _channel({
  String id = 'ch1',
  String channelId = 'c1',
  String builderId = 'builder-1',
  String purpose = 'general',
  bool autoJoin = false,
  List<String> memberTypes = const ['broker', 'influencer'],
  String? name,
  String? description,
  int participantCount = 0,
  String? currentUserRole,
  bool isCurrentUserParticipant = false,
}) {
  return NetworkChannel.fromJson({
    'id': id,
    'channel_id': channelId,
    'builder_id': builderId,
    'channel_purpose': purpose,
    'is_auto_join': autoJoin,
    'member_types': memberTypes,
  }).copyWith(
    name: name,
    description: description,
    participantCount: participantCount,
    currentUserRole: currentUserRole,
    isCurrentUserParticipant: isCurrentUserParticipant,
  );
}

NetworkMember _member({
  String id = 'bn1',
  String memberId = 'member-1',
  String memberType = 'broker',
  bool verified = false,
  String? displayName = 'Some Member',
}) {
  return NetworkMember.fromSupabase({
    'id': id,
    'member_id': memberId,
    'member_type': memberType,
    'verified': verified,
  }, displayName: displayName);
}

void main() {
  group('NetworkChannel hydration', () {
    test('a null id never becomes the literal string "null"', () {
      final channel = NetworkChannel.fromJson(const {
        'channel_id': 'c1',
        'channel_purpose': 'general',
      });
      expect(channel.id, '');
      expect(channel.id, isNot('null'));
      expect(channel.builderId, '');
    });

    test(
      'copyWith hydrates channel details, count and role without losing the base row',
      () {
        final base = _channel(purpose: 'leads', autoJoin: true);
        final hydrated = base.copyWith(
          name: 'Downtown Buyers',
          description: 'For hot leads',
          participantCount: 4,
          currentUserRole: 'admin',
          isCurrentUserParticipant: true,
        );

        expect(hydrated.id, base.id);
        expect(hydrated.channelId, base.channelId);
        expect(hydrated.isAutoJoin, isTrue);
        expect(hydrated.name, 'Downtown Buyers');
        expect(hydrated.description, 'For hot leads');
        expect(hydrated.participantCount, 4);
        expect(hydrated.isCurrentUserAdmin, isTrue);
        expect(hydrated.isCurrentUserParticipant, isTrue);
        expect(hydrated.displayName, 'Downtown Buyers');
      },
    );

    test(
      'displayName and initials fall back to the purpose when unhydrated',
      () {
        final channel = _channel(purpose: 'lead_distribution');
        expect(channel.displayName, 'Lead distribution');
        expect(channel.initials, 'LD');
      },
    );

    test('a moderator role is not mistaken for admin', () {
      final channel = _channel().copyWith(currentUserRole: 'moderator');
      expect(channel.isCurrentUserAdmin, isFalse);
    });
  });

  group('NetworkMember', () {
    test(
      'parses the accepted-member fields and resolves a display initial',
      () {
        final member = _member(
          memberType: 'influencer',
          verified: true,
          displayName: 'Amy Rao',
        );
        expect(member.memberType, 'influencer');
        expect(member.verified, isTrue);
        expect(member.resolvedName, 'Amy Rao');
        expect(member.initial, 'A');
      },
    );

    test('an unresolved profile falls back to Unknown', () {
      final member = _member(displayName: null);
      expect(member.resolvedName, 'Unknown');
      expect(member.initial, 'U');
    });
  });

  group('filterBulkMessageRecipients', () {
    final members = [
      _member(memberId: 'broker-1', memberType: 'broker', verified: true),
      _member(memberId: 'broker-2', memberType: 'broker', verified: false),
      _member(
        memberId: 'influencer-1',
        memberType: 'influencer',
        verified: true,
      ),
      _member(
        memberId: 'influencer-2',
        memberType: 'influencer',
        verified: false,
      ),
    ];

    test('all keeps every accepted member', () {
      final result = filterBulkMessageRecipients(
        members: members,
        recipientType: 'all',
        builderId: 'builder-1',
      );
      expect(result.map((m) => m.memberId), members.map((m) => m.memberId));
    });

    test('brokers keeps only broker-type members', () {
      final result = filterBulkMessageRecipients(
        members: members,
        recipientType: 'brokers',
        builderId: 'builder-1',
      );
      expect(result.map((m) => m.memberId), ['broker-1', 'broker-2']);
    });

    test('influencers keeps only influencer-type members', () {
      final result = filterBulkMessageRecipients(
        members: members,
        recipientType: 'influencers',
        builderId: 'builder-1',
      );
      expect(result.map((m) => m.memberId), ['influencer-1', 'influencer-2']);
    });

    test('verified_only keeps only verified members regardless of type', () {
      final result = filterBulkMessageRecipients(
        members: members,
        recipientType: 'verified_only',
        builderId: 'builder-1',
      );
      expect(result.map((m) => m.memberId), ['broker-1', 'influencer-1']);
    });

    test('de-duplicates by member id', () {
      final withDupe = [
        ...members,
        _member(memberId: 'broker-1', memberType: 'broker', verified: true),
      ];
      final result = filterBulkMessageRecipients(
        members: withDupe,
        recipientType: 'all',
        builderId: 'builder-1',
      );
      expect(result.where((m) => m.memberId == 'broker-1').length, 1);
    });

    test('excludes the builder even if present in the member list', () {
      final withBuilder = [
        ...members,
        _member(memberId: 'builder-1', memberType: 'broker'),
      ];
      final result = filterBulkMessageRecipients(
        members: withBuilder,
        recipientType: 'all',
        builderId: 'builder-1',
      );
      expect(result.any((m) => m.memberId == 'builder-1'), isFalse);
    });

    test('an empty member list yields zero recipients for every filter', () {
      for (final type in ['all', 'brokers', 'influencers', 'verified_only']) {
        expect(
          filterBulkMessageRecipients(
            members: const [],
            recipientType: type,
            builderId: 'b',
          ),
          isEmpty,
        );
      }
    });
  });

  group('NetworkCommunicationProvider', () {
    late FakeNetworkCommunicationService service;
    late NetworkCommunicationProvider provider;

    setUp(() {
      service = FakeNetworkCommunicationService();
      provider = NetworkCommunicationProvider(service: service);
    });

    tearDown(() => provider.dispose());

    test('load populates channels and accepted members', () async {
      service.nextLoadResult = (channels: [_channel()], members: [_member()]);

      await provider.load('builder-1', isBuilder: true);

      expect(provider.loading, isFalse);
      expect(provider.failed, isFalse);
      expect(provider.channels.length, 1);
      expect(provider.acceptedMembers.length, 1);
    });

    test('a failed load is distinguished from an empty one', () async {
      service.nextLoadError = Exception('network down');

      await provider.load('builder-1', isBuilder: true);

      expect(provider.failed, isTrue);
      expect(provider.channels, isEmpty);
    });

    test('switching users discards a slow, now-stale response', () async {
      final pause = Completer<void>();
      service.pauseNextLoad = pause;
      service.nextLoadResult = (
        channels: [_channel(id: 'stale')],
        members: const [],
      );

      final firstLoad = provider.load('user-a', isBuilder: false);

      // A second user signs in before the first user's slow load resolves.
      service.nextLoadResult = (
        channels: [_channel(id: 'fresh')],
        members: const [],
      );
      await provider.load('user-b', isBuilder: false);

      expect(provider.channels.single.id, 'fresh');

      pause.complete();
      await firstLoad;

      // The stale response for user-a must never have overwritten user-b's.
      expect(provider.channels.single.id, 'fresh');
    });

    test('createChannel returns true and refreshes on success', () async {
      await provider.load('builder-1', isBuilder: true);
      service.nextLoadResult = (
        channels: [_channel(name: 'New Channel')],
        members: const [],
      );

      final ok = await provider.createChannel(
        name: 'New Channel',
        channelPurpose: 'general',
        isAutoJoin: false,
        memberTypes: const ['broker', 'influencer'],
      );

      expect(ok, isTrue);
      expect(provider.createChannelError, isNull);
      expect(provider.channels.single.name, 'New Channel');
      expect(service.lastCreateArgs?['builderId'], 'builder-1');
    });

    test(
      'a partial failure surfaces an error, refreshes, and reports failure',
      () async {
        await provider.load('builder-1', isBuilder: true);
        service.nextCreateError = const NetworkChannelPartialFailure(
          'The channel was created, but its network settings could not be saved.',
          channelId: 'partial-1',
        );
        service.nextLoadResult = (
          channels: [_channel(id: 'partial-1')],
          members: const [],
        );

        final ok = await provider.createChannel(
          name: 'Partial Channel',
          channelPurpose: 'general',
          isAutoJoin: false,
          memberTypes: const ['broker'],
        );

        expect(ok, isFalse);
        expect(provider.createChannelError, isNotNull);
        // Truthful refresh: whatever landed is still shown.
        expect(provider.channels.single.id, 'partial-1');
      },
    );

    test(
      'a second createChannel call is ignored while one is already in flight',
      () async {
        await provider.load('builder-1', isBuilder: true);
        final pause = Completer<void>();
        service.pauseNextCreate = pause;

        final first = provider.createChannel(
          name: 'A',
          channelPurpose: 'general',
          isAutoJoin: false,
          memberTypes: const ['broker'],
        );
        expect(provider.creatingChannel, isTrue);

        final second = await provider.createChannel(
          name: 'B',
          channelPurpose: 'general',
          isAutoJoin: false,
          memberTypes: const ['broker'],
        );
        expect(second, isFalse);
        expect(service.createCallCount, 1);

        pause.complete();
        await first;
      },
    );

    test(
      'sendBulkMessage with zero eligible recipients never calls the service',
      () async {
        service.nextLoadResult = (channels: const [], members: const []);
        await provider.load('builder-1', isBuilder: true);

        final ok = await provider.sendBulkMessage(
          recipientType: 'all',
          messageType: 'announcement',
          priority: 'medium',
          title: 'Hi',
          message: 'Hello there',
        );

        expect(ok, isFalse);
        expect(provider.bulkMessageError, isNotNull);
        expect(service.sendCallCount, 0);
      },
    );

    test('sendBulkMessage succeeds and records the recipient count', () async {
      service.nextLoadResult = (
        channels: const [],
        members: [
          _member(memberId: 'm1', memberType: 'broker'),
          _member(memberId: 'm2', memberType: 'influencer'),
        ],
      );
      await provider.load('builder-1', isBuilder: true);

      final ok = await provider.sendBulkMessage(
        recipientType: 'all',
        messageType: 'announcement',
        priority: 'medium',
        title: 'Hi',
        message: 'Hello there',
      );

      expect(ok, isTrue);
      expect(provider.lastBulkMessageRecipientCount, 2);
      expect(service.lastSendRecipients?.length, 2);
    });
  });

  group('Create Network Channel sheet', () {
    Future<NetworkCommunicationProvider> pumpSheet(
      WidgetTester tester,
      FakeNetworkCommunicationService service,
    ) async {
      // Taller than the default 600 dp test viewport so `ensureVisible` can
      // bring the submit button on screen without scrolling weirdness — same
      // fix as `_useSmallScreen`, just sized the other way.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = NetworkCommunicationProvider(service: service);
      await provider.load('builder-1', isBuilder: true);

      await tester.pumpWidget(
        _host(
          ChangeNotifierProvider<NetworkCommunicationProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCreateNetworkChannelSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('name is required', (tester) async {
      await pumpSheet(tester, FakeNetworkCommunicationService());

      await _tap(tester, find.text('Create Channel'));

      expect(find.text('Channel name is required.'), findsOneWidget);
    });

    testWidgets('purpose is required once a name is entered', (tester) async {
      await pumpSheet(tester, FakeNetworkCommunicationService());

      await tester.enterText(find.byType(TextField).first, 'My Channel');
      await _tap(tester, find.text('Create Channel'));

      expect(find.text('Channel purpose is required.'), findsOneWidget);
    });

    testWidgets('auto-join requires at least one member type', (tester) async {
      await pumpSheet(tester, FakeNetworkCommunicationService());

      await tester.enterText(find.byType(TextField).first, 'My Channel');
      await _tap(tester, find.byType(DropdownButton<String>).first);
      await _tap(tester, find.text('General Discussion').last);

      // Deselect both default-selected member type chips.
      await _tap(tester, find.widgetWithText(FilterChip, 'Broker'));
      await _tap(tester, find.widgetWithText(FilterChip, 'Influencer'));

      await _tap(tester, find.byType(AppToggle));

      await _tap(tester, find.text('Create Channel'));

      expect(
        find.text('Select at least one member type for auto-join.'),
        findsOneWidget,
      );
    });

    testWidgets('a double tap while creating only submits once', (
      tester,
    ) async {
      final service = FakeNetworkCommunicationService();
      final pause = Completer<void>();
      service.pauseNextCreate = pause;
      await pumpSheet(tester, service);

      await tester.enterText(find.byType(TextField).first, 'My Channel');
      await _tap(tester, find.byType(DropdownButton<String>).first);
      await _tap(tester, find.text('General Discussion').last);

      // Located by key, not by its "Create Channel" label: once tapped, the
      // button swaps its label for a spinner while `creatingChannel` is true.
      final createButton = find.byKey(const Key('createNetworkChannelSubmit'));
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await tester.pump();
      // Button is now disabled (creatingChannel == true); a second tap is a no-op.
      await tester.tap(createButton, warnIfMissed: false);
      await tester.pump();

      expect(service.createCallCount, 1);

      pause.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a failure preserves the entered name and keeps the sheet open',
      (tester) async {
        final service = FakeNetworkCommunicationService();
        service.nextCreateError = Exception('boom');
        await pumpSheet(tester, service);

        await tester.enterText(find.byType(TextField).first, 'Keep Me');
        await _tap(tester, find.byType(DropdownButton<String>).first);
        await _tap(tester, find.text('General Discussion').last);

        await _tap(tester, find.text('Create Channel'));

        expect(find.text('Create Network Channel'), findsOneWidget);
        expect(find.text('Keep Me'), findsOneWidget);
      },
    );

    testWidgets('success closes the sheet', (tester) async {
      final service = FakeNetworkCommunicationService();
      await pumpSheet(tester, service);

      await tester.enterText(find.byType(TextField).first, 'My Channel');
      await _tap(tester, find.byType(DropdownButton<String>).first);
      await _tap(tester, find.text('General Discussion').last);

      await _tap(tester, find.text('Create Channel'));

      expect(find.text('Create Network Channel'), findsNothing);
      expect(service.createCallCount, 1);
    });

    testWidgets(
      'does not render an Add Specific Members section — that feature was '
      'removed from Network Communication; Messaging keeps its own',
      (tester) async {
        await pumpSheet(tester, FakeNetworkCommunicationService());

        expect(find.text('Add Specific Members (optional)'), findsNothing);
        expect(
          find.widgetWithText(TextField, 'Search your network by name...'),
          findsNothing,
        );
        expect(find.text('No eligible network members yet'), findsNothing);
        expect(find.text('No matching network members'), findsNothing);
        // Exactly the 3 remaining text fields (name, description, purpose
        // uses a dropdown, not a TextField) — no fourth, member-search field.
        expect(find.byType(TextField), findsNWidgets(2));
      },
    );

    testWidgets(
      'creating a channel from this sheet always passes an empty manualMemberIds',
      (tester) async {
        final service = FakeNetworkCommunicationService();
        await pumpSheet(tester, service);

        await tester.enterText(find.byType(TextField).first, 'My Channel');
        await tester.enterText(
          find.byType(TextField).last,
          'A channel for my network',
        );
        await _tap(tester, find.byType(DropdownButton<String>).first);
        await _tap(tester, find.text('Lead Updates').last);
        await _tap(tester, find.byType(AppToggle));

        await _tap(tester, find.text('Create Channel'));

        expect(service.createCallCount, 1);
        expect(service.lastCreateArgs!['manualMemberIds'], isEmpty);
        // The rest of the submission is untouched by removing the picker.
        expect(service.lastCreateArgs!['name'], 'My Channel');
        expect(
          service.lastCreateArgs!['description'],
          'A channel for my network',
        );
        expect(service.lastCreateArgs!['channelPurpose'], 'leads');
        expect(service.lastCreateArgs!['isAutoJoin'], isTrue);
        expect(service.lastCreateArgs!['memberTypes'], [
          'broker',
          'influencer',
        ]);
      },
    );
  });

  group('Bulk Message sheet', () {
    Future<NetworkCommunicationProvider> pumpSheet(
      WidgetTester tester,
      FakeNetworkCommunicationService service,
    ) async {
      final provider = NetworkCommunicationProvider(service: service);
      service.nextLoadResult = (
        channels: const [],
        members: [
          _member(memberId: 'm1', memberType: 'broker', verified: true),
          _member(memberId: 'm2', memberType: 'influencer', verified: false),
        ],
      );
      await provider.load('builder-1', isBuilder: true);

      await tester.pumpWidget(
        _host(
          ChangeNotifierProvider<NetworkCommunicationProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showBulkMessageSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('recipient count changes with the filter', (tester) async {
      await pumpSheet(tester, FakeNetworkCommunicationService());

      expect(find.text('2 members'), findsOneWidget);

      await _tap(tester, find.byType(DropdownButton<String>).first);
      await _tap(tester, find.text('Brokers Only').last);

      expect(find.text('1 members'), findsOneWidget);
    });

    testWidgets('title and message are required', (tester) async {
      await pumpSheet(tester, FakeNetworkCommunicationService());

      await _tap(tester, find.text('Send Message'));
      expect(find.text('Message title is required.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'A title');
      await _tap(tester, find.text('Send Message'));
      expect(find.text('Message is required.'), findsOneWidget);
    });

    testWidgets('a double tap while sending only sends once', (tester) async {
      final service = FakeNetworkCommunicationService();
      final pause = Completer<void>();
      service.pauseNextSend = pause;
      await pumpSheet(tester, service);

      await tester.enterText(find.byType(TextField).at(0), 'Title');
      await tester.enterText(find.byType(TextField).at(1), 'Body');
      // Located by key, not by its "Send Message" label: once tapped, the
      // button swaps its label for a spinner while `sendingBulkMessage` is true.
      final sendButton = find.byKey(const Key('sendBulkMessageSubmit'));
      await tester.ensureVisible(sendButton);
      await tester.pumpAndSettle();
      await tester.tap(sendButton);
      await tester.pump();
      await tester.tap(sendButton, warnIfMissed: false);
      await tester.pump();

      expect(service.sendCallCount, 1);

      pause.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('failure preserves entered content', (tester) async {
      final service = FakeNetworkCommunicationService();
      service.nextSendError = Exception('boom');
      await pumpSheet(tester, service);

      await tester.enterText(find.byType(TextField).at(0), 'Keep Title');
      await tester.enterText(find.byType(TextField).at(1), 'Keep Body');
      await _tap(tester, find.text('Send Message'));

      expect(find.text('Send Bulk Message'), findsOneWidget);
      expect(find.text('Keep Title'), findsOneWidget);
      expect(find.text('Keep Body'), findsOneWidget);
    });

    testWidgets('success closes the sheet with the actual recipient count', (
      tester,
    ) async {
      final service = FakeNetworkCommunicationService();
      int? poppedWith;
      final provider = NetworkCommunicationProvider(service: service);
      service.nextLoadResult = (
        channels: const [],
        members: [_member(memberId: 'm1', memberType: 'broker')],
      );
      await provider.load('builder-1', isBuilder: true);

      await tester.pumpWidget(
        _host(
          ChangeNotifierProvider<NetworkCommunicationProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  poppedWith = await showBulkMessageSheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Title');
      await tester.enterText(find.byType(TextField).at(1), 'Body');
      await _tap(tester, find.text('Send Message'));

      expect(find.text('Send Bulk Message'), findsNothing);
      expect(poppedWith, 1);
    });
  });

  group('Channel card + Open Channel', () {
    testWidgets('a participating member can open their channel', (
      tester,
    ) async {
      NetworkChannel? opened;
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: [
              _channel(
                name: 'Downtown Buyers',
                participantCount: 3,
                currentUserRole: 'member',
                isCurrentUserParticipant: true,
              ),
            ],
            loading: false,
            failed: false,
            isBuilder: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
            onOpenChannel: (c) => opened = c,
          ),
        ),
      );

      expect(find.text('Downtown Buyers'), findsOneWidget);
      expect(find.text('Open Channel'), findsOneWidget);

      await tester.tap(find.text('Open Channel'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.channelId, 'c1');
    });

    testWidgets('a non-participant cannot tap Open Channel', (tester) async {
      var openedCount = 0;
      await tester.pumpWidget(
        _host(
          NetworkCommunicationBody(
            channels: [
              _channel(
                name: 'Downtown Buyers',
                isCurrentUserParticipant: false,
              ),
            ],
            loading: false,
            failed: false,
            isBuilder: false,
            onCreateChannel: () {},
            onBulkMessage: () {},
            onOpenChannel: (_) => openedCount++,
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Open Channel'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Open Channel'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(openedCount, 0);
    });

    testWidgets(
      'long names/descriptions/member types lay out without overflow on a small screen',
      (tester) async {
        _useSmallScreen(tester);
        await tester.pumpWidget(
          _host(
            NetworkCommunicationBody(
              channels: [
                _channel(
                  name:
                      'A very long channel name that could push a narrow card past its bounds',
                  description:
                      'An equally long description explaining exactly what this channel is for '
                      'in far more words than a compact card would normally show',
                  memberTypes: const [
                    'broker',
                    'influencer',
                    'a_very_long_member_type_token',
                  ],
                  participantCount: 128,
                  isCurrentUserParticipant: true,
                ),
              ],
              loading: false,
              failed: false,
              isBuilder: true,
              onCreateChannel: () {},
              onBulkMessage: () {},
              onOpenChannel: (_) {},
            ),
          ),
        );

        expect(overflowingBoxes(tester), isEmpty);
      },
    );
  });
}
