// test/collaboration_marketplace_test.dart
//
// The Collaboration Marketplace port — focused coverage for the parts that
// don't require a live Supabase backend or a device video codec:
//
//   * model parsing, including unknown-safe statuses/kinds;
//   * the profile CTA's influencer-XOR eligibility matrix;
//   * request direction (incoming/outgoing) and who may accept/decline;
//   * the 6-step stepper's status->index folding and per-status action
//     visibility sets;
//   * `MessagingProvider`'s Collabs-tab loading, accept/decline and the
//     incoming-request badge, via a fake `CollaborationService` subclass —
//     the same "extend the real service, override methods" convention
//     `notification_centre_test.dart`'s `_FakeService` already uses (no
//     mockito/mocktail in this repo);
//   * collaboration message-type detection and the `location` content
//     format (`"<label>\n<mapsUrl>"`);
//   * client-side upload validation that doesn't need a video codec (mp4
//     extension, byte-size ceilings) — duration probing needs `video_player`
//     platform channels, which aren't available under `flutter test`, and is
//     therefore a documented gap, not silently skipped;
//   * every `collab_*` notification type has a style and sits in a known
//     filter bucket.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/app_notification.dart';
import 'package:propcid_app/models/channel_summary.dart';
import 'package:propcid_app/models/chat_message.dart';
import 'package:propcid_app/models/collaboration.dart';
import 'package:propcid_app/models/conversation_summary.dart';
import 'package:propcid_app/providers/messaging_provider.dart';
import 'package:propcid_app/screens/messaging/widgets/collab_action_panel.dart';
import 'package:propcid_app/services/collab_functions_client.dart';
import 'package:propcid_app/services/collaboration_exceptions.dart';
import 'package:propcid_app/services/collaboration_service.dart';
import 'package:propcid_app/services/messaging_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // ── 1. Model parsing, unknown-safe ────────────────────────────────────

  group('Collaboration.fromSupabase', () {
    test('parses a full row', () {
      final collab = Collaboration.fromSupabase({
        'id': 'c-1',
        'initiated_by': 'influencer',
        'client_id': 'client-1',
        'influencer_id': 'inf-1',
        'conversation_id': 'conv-1',
        'status': 'agreement_pending',
        'currency': 'INR',
        'agreed_amount_minor': 100000,
        'advance_amount_minor': 25000,
        'final_amount_minor': 75000,
        'agreement_url': 'c-1/agreement.pdf',
        'request_message': 'Let\'s work together',
        'attached_reel_ids': ['r-1', 'r-2'],
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(collab.id, 'c-1');
      expect(collab.initiatedBy, 'influencer');
      expect(collab.status, CollabStatuses.agreementPending);
      expect(collab.agreedAmountMinor, 100000);
      expect(collab.attachedReelIds, ['r-1', 'r-2']);
      expect(collab.hasConversation, isTrue);
    });

    test(
      'an unrecognised status string does not throw and is not terminal',
      () {
        final collab = Collaboration.fromSupabase({
          'id': 'c-2',
          'client_id': 'client-1',
          'influencer_id': 'inf-1',
          'status': 'some_future_status',
        });
        expect(collab.status, 'some_future_status');
        expect(collab.isTerminal, isFalse);
        expect(() => collab.roleFor('client-1'), returnsNormally);
      },
    );

    test('parses the three pending-offer fields', () {
      final collab = Collaboration.fromSupabase({
        'id': 'c-1',
        'client_id': 'client-1',
        'influencer_id': 'inf-1',
        'status': 'accepted',
        'pending_offer_amount_minor': 500000,
        'pending_offer_by': 'influencer',
        'pending_offer_is_final': true,
      });
      expect(collab.pendingOfferAmountMinor, 500000);
      expect(collab.pendingOfferBy, 'influencer');
      expect(collab.pendingOfferIsFinal, isTrue);
      expect(collab.hasPendingOffer, isTrue);
      expect(collab.proposedPendingOfferBy('inf-1'), isTrue);
      expect(collab.proposedPendingOfferBy('client-1'), isFalse);
    });

    test('no pending offer when the amount/by fields are absent', () {
      final collab = Collaboration.fromSupabase({
        'id': 'c-2',
        'client_id': 'client-1',
        'influencer_id': 'inf-1',
        'status': 'accepted',
      });
      expect(collab.hasPendingOffer, isFalse);
      expect(collab.pendingOfferIsFinal, isFalse);
    });

    test(
      'a stray pending-offer value on a non-accepted status is not live',
      () {
        // The RPC clears pending_offer_* on accept_offer/cancel; a lingering
        // non-null value on any other status must not drive UI as if an
        // offer were actually on the table.
        final collab = Collaboration.fromSupabase({
          'id': 'c-3',
          'client_id': 'client-1',
          'influencer_id': 'inf-1',
          'status': 'agreement_pending',
          'pending_offer_amount_minor': 100000,
          'pending_offer_by': 'client',
        });
        expect(collab.hasPendingOffer, isFalse);
      },
    );

    test('copyWith preserves the pending-offer fields', () {
      const collab = Collaboration(
        id: 'c-4',
        initiatedBy: CollabRoles.client,
        clientId: 'client-1',
        influencerId: 'inf-1',
        status: CollabStatuses.accepted,
        pendingOfferAmountMinor: 250000,
        pendingOfferBy: CollabRoles.client,
        pendingOfferIsFinal: true,
      );
      final copied = collab.copyWith(status: CollabStatuses.accepted);
      expect(copied.pendingOfferAmountMinor, 250000);
      expect(copied.pendingOfferBy, CollabRoles.client);
      expect(copied.pendingOfferIsFinal, isTrue);
    });

    test('roleFor / counterpartyIdFor / involves', () {
      const collab = Collaboration(
        id: 'c-1',
        initiatedBy: CollabRoles.client,
        clientId: 'client-1',
        influencerId: 'inf-1',
        status: CollabStatuses.accepted,
      );
      expect(collab.roleFor('client-1'), CollabRoles.client);
      expect(collab.roleFor('inf-1'), CollabRoles.influencer);
      expect(collab.roleFor('someone-else'), isNull);
      expect(collab.counterpartyIdFor('client-1'), 'inf-1');
      expect(collab.counterpartyIdFor('inf-1'), 'client-1');
      expect(collab.involves('client-1'), isTrue);
      expect(collab.involves('someone-else'), isFalse);
    });
  });

  group('CollabAsset', () {
    test('an unknown status parses safely and is not consumed/expired', () {
      final asset = CollabAsset.fromSupabase({
        'id': 'a-1',
        'kind': 'sample_onetime',
        'status': 'some_future_status',
        'uploaded_by': 'inf-1',
      });
      expect(asset.isConsumed, isFalse);
      expect(asset.isExpiredOrPurged, isFalse);
    });

    test('isConsumed is true once viewed_at is set even if status lags', () {
      final asset = CollabAsset.fromSupabase({
        'id': 'a-1',
        'kind': 'sample_onetime',
        'status': 'approved',
        'uploaded_by': 'inf-1',
        'viewed_at': '2026-01-01T00:00:00Z',
      });
      expect(asset.isConsumed, isTrue);
    });

    test('a deliverable past its download_deadline is not downloadable', () {
      final asset = CollabAsset.fromSupabase({
        'id': 'a-2',
        'kind': 'deliverable',
        'status': 'approved',
        'uploaded_by': 'inf-1',
        'download_deadline': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      expect(asset.deadlinePassed, isTrue);
      expect(asset.isDownloadable, isFalse);
    });

    test('a deliverable within its window is downloadable', () {
      final asset = CollabAsset.fromSupabase({
        'id': 'a-3',
        'kind': 'deliverable',
        'status': 'approved',
        'uploaded_by': 'inf-1',
        'download_deadline': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });
      expect(asset.isDownloadable, isTrue);
    });
  });

  test('formatCollabAmount renders whole rupees with thousands separators', () {
    expect(formatCollabAmount(250000), '₹2,500');
    expect(formatCollabAmount(10000000), '₹1,00,000');
    expect(formatCollabAmount(null), '—');
    expect(formatCollabAmount(0), '₹0');
  });

  test('every applied collab status has a short badge label', () {
    for (final status in [
      CollabStatuses.requested,
      CollabStatuses.declined,
      CollabStatuses.accepted,
      CollabStatuses.agreementPending,
      CollabStatuses.advancePaid,
      CollabStatuses.inProgress,
      CollabStatuses.finalPaid,
      CollabStatuses.deliverablePending,
      CollabStatuses.delivered,
      CollabStatuses.completed,
      CollabStatuses.disputed,
      CollabStatuses.cancelled,
    ]) {
      expect(collabStatusLabel(status), isNot('Collaboration'), reason: status);
    }
    // Unknown status falls back rather than throwing.
    expect(collabStatusLabel('made_up'), 'Collaboration');
  });

  // ── 2. Profile CTA — influencer/non-influencer matrix ─────────────────

  group('isCollabEligible', () {
    test('signed-out viewer never sees the CTA', () {
      expect(
        isCollabEligible(
          viewerId: null,
          viewedUserId: 'u-2',
          viewedIsInfluencer: true,
          viewerIsInfluencer: false,
        ),
        isFalse,
      );
    });

    test('viewing your own profile never shows the CTA', () {
      expect(
        isCollabEligible(
          viewerId: 'u-1',
          viewedUserId: 'u-1',
          viewedIsInfluencer: true,
          viewerIsInfluencer: true,
        ),
        isFalse,
      );
    });

    test('influencer viewer + non-influencer profile: eligible', () {
      expect(
        isCollabEligible(
          viewerId: 'u-1',
          viewedUserId: 'u-2',
          viewedIsInfluencer: false,
          viewerIsInfluencer: true,
        ),
        isTrue,
      );
    });

    test('non-influencer viewer + influencer profile: eligible', () {
      expect(
        isCollabEligible(
          viewerId: 'u-1',
          viewedUserId: 'u-2',
          viewedIsInfluencer: true,
          viewerIsInfluencer: false,
        ),
        isTrue,
      );
    });

    test('two influencers: not eligible (XOR fails)', () {
      expect(
        isCollabEligible(
          viewerId: 'u-1',
          viewedUserId: 'u-2',
          viewedIsInfluencer: true,
          viewerIsInfluencer: true,
        ),
        isFalse,
      );
    });

    test('two non-influencers: not eligible (XOR fails)', () {
      expect(
        isCollabEligible(
          viewerId: 'u-1',
          viewedUserId: 'u-2',
          viewedIsInfluencer: false,
          viewerIsInfluencer: false,
        ),
        isFalse,
      );
    });
  });

  // ── 3. Request direction + accept/decline permission ──────────────────

  group('CollabInboxEntry.isIncomingFor', () {
    test('influencer-initiated request is incoming for the client', () {
      const collab = Collaboration(
        id: 'c-1',
        initiatedBy: CollabRoles.influencer,
        clientId: 'client-1',
        influencerId: 'inf-1',
        status: CollabStatuses.requested,
      );
      const entry = CollabInboxEntry(collaboration: collab);
      expect(entry.isIncomingFor('client-1'), isTrue);
      expect(entry.isIncomingFor('inf-1'), isFalse);
    });

    test('client-initiated request is incoming for the influencer', () {
      const collab = Collaboration(
        id: 'c-2',
        initiatedBy: CollabRoles.client,
        clientId: 'client-1',
        influencerId: 'inf-1',
        status: CollabStatuses.requested,
      );
      const entry = CollabInboxEntry(collaboration: collab);
      expect(entry.isIncomingFor('inf-1'), isTrue);
      expect(entry.isIncomingFor('client-1'), isFalse);
    });
  });

  group('MessagingProvider collab section (fake service)', () {
    test(
      'accept/decline are only offered to the recipient, and the badge reflects it',
      () async {
        final incoming = Collaboration(
          id: 'c-1',
          initiatedBy: CollabRoles.influencer,
          clientId: 'me',
          influencerId: 'inf-1',
          status: CollabStatuses.requested,
          createdAt: DateTime.now(),
        );
        final outgoing = Collaboration(
          id: 'c-2',
          initiatedBy: CollabRoles.client,
          clientId: 'me',
          influencerId: 'inf-2',
          status: CollabStatuses.requested,
          createdAt: DateTime.now(),
        );
        final fake = _FakeCollabService(rows: [incoming, outgoing]);
        final provider = MessagingProvider(
          service: _NoopMessagingService(),
          collabService: fake,
          // The launch-flags pass defaults collaboration loading off; this
          // test is exercising that loading logic itself, unaffected by
          // that pass's own scope.
          loadCollabs: true,
        );

        // load() also awaits conversations/channels via the noop messaging
        // service, which return empty lists harmlessly.
        await provider.load('me');

        expect(provider.collabs.length, 2);
        expect(provider.hasIncomingCollabRequest, isTrue);

        final incomingEntry = provider.collabs.firstWhere(
          (e) => e.collaboration.id == 'c-1',
        );
        final outgoingEntry = provider.collabs.firstWhere(
          (e) => e.collaboration.id == 'c-2',
        );
        expect(incomingEntry.isIncomingFor('me'), isTrue);
        expect(outgoingEntry.isIncomingFor('me'), isFalse);

        final (updated, error) = await provider.acceptCollab('c-1');
        expect(error, isNull);
        expect(updated?.status, CollabStatuses.accepted);
        expect(updated?.conversationId, 'conv-c-1');
        expect(fake.acceptedIds, ['c-1']);

        final declineError = await provider.declineCollab('c-2');
        expect(declineError, isNull);
        expect(fake.declinedIds, ['c-2']);
      },
    );

    test('a decline failure surfaces the backend message', () async {
      final collab = Collaboration(
        id: 'c-3',
        initiatedBy: CollabRoles.influencer,
        clientId: 'me',
        influencerId: 'inf-1',
        status: CollabStatuses.requested,
        createdAt: DateTime.now(),
      );
      final fake = _FakeCollabService(rows: [collab])..failDecline = true;
      final provider = MessagingProvider(
        service: _NoopMessagingService(),
        collabService: fake,
        loadCollabs: true,
      );
      await provider.load('me');

      final error = await provider.declineCollab('c-3');
      expect(error, "This collaboration can no longer be declined.");
    });

    test('Chats excludes collaboration conversations; Collabs excludes '
        'declined-without-conversation and carries unread counts', () async {
      final requested = Collaboration(
        id: 'c-req',
        initiatedBy: CollabRoles.influencer,
        clientId: 'me',
        influencerId: 'inf-1',
        status: CollabStatuses.requested,
        createdAt: DateTime.now(),
      );
      final declinedNoConversation = Collaboration(
        id: 'c-declined',
        initiatedBy: CollabRoles.client,
        clientId: 'me',
        influencerId: 'inf-2',
        status: CollabStatuses.declined,
        createdAt: DateTime.now(),
      );
      final active = Collaboration(
        id: 'c-active',
        initiatedBy: CollabRoles.client,
        clientId: 'me',
        influencerId: 'inf-3',
        conversationId: 'conv-active',
        status: CollabStatuses.inProgress,
        createdAt: DateTime.now(),
      );

      final fakeCollab = _FakeCollabService(
        rows: [requested, declinedNoConversation, active],
      );
      final fakeMessaging = _ConversationsFakeMessagingService(
        conversations: [
          const ConversationSummary(
            id: 'conv-plain',
            lastMessage: 'hey',
            unreadCount: 2,
          ),
          const ConversationSummary(
            id: 'conv-active',
            collaborationId: 'c-active',
            unreadCount: 5,
          ),
        ],
      );
      final provider = MessagingProvider(
        service: fakeMessaging,
        collabService: fakeCollab,
        loadCollabs: true,
      );

      await provider.load('me');

      // Chats: only the plain conversation, never the collaboration one.
      expect(provider.conversations.length, 1);
      expect(provider.conversations.single.id, 'conv-plain');
      expect(provider.conversations.any((c) => c.isCollaboration), isFalse);

      // Collabs: the pending request and the active collaboration, but
      // NOT the declined-with-no-conversation row — it must not linger
      // as an inert card.
      expect(provider.collabs.length, 2);
      expect(
        provider.collabs.map((e) => e.collaboration.id),
        containsAll(['c-req', 'c-active']),
      );
      expect(
        provider.collabs.any((e) => e.collaboration.id == 'c-declined'),
        isFalse,
      );

      // The active collaboration's unread count is cross-referenced from
      // its own conversation row; the still-pending request has none.
      final activeEntry = provider.collabs.firstWhere(
        (e) => e.collaboration.id == 'c-active',
      );
      expect(activeEntry.unreadCount, 5);
      expect(provider.totalCollabUnread, 5);
    });
  });

  // ── 4. Status -> action -> role matrix (the 6-step stepper) ───────────

  group('collabStepIndex', () {
    test('maps every declared step status to its own index', () {
      expect(collabStepIndex(CollabStatuses.accepted), 0);
      expect(collabStepIndex(CollabStatuses.agreementPending), 1);
      expect(collabStepIndex(CollabStatuses.inProgress), 2);
      expect(collabStepIndex(CollabStatuses.deliverablePending), 3);
      expect(collabStepIndex(CollabStatuses.delivered), 4);
      expect(collabStepIndex(CollabStatuses.completed), 5);
    });

    test('folds the two statuses that are never actually stored', () {
      expect(collabStepIndex(CollabStatuses.advancePaid), 2);
      expect(collabStepIndex(CollabStatuses.finalPaid), 3);
    });

    test(
      'an unknown status falls back to the first step rather than throwing',
      () {
        expect(collabStepIndex('requested'), 0);
        expect(collabStepIndex('anything_else'), 0);
      },
    );
  });

  test('kCollabSteps has exactly the 6 portal-parity steps in order', () {
    expect(kCollabSteps.map((s) => s.status).toList(), [
      CollabStatuses.accepted,
      CollabStatuses.agreementPending,
      CollabStatuses.inProgress,
      CollabStatuses.deliverablePending,
      CollabStatuses.delivered,
      CollabStatuses.completed,
    ]);
  });

  // ── 5. Message-type detection + location content format ───────────────

  group('ChatMessage collaboration fields', () {
    test('parses collab_asset_id and dispatches message-type getters', () {
      final message = ChatMessage.fromSupabase({
        'id': 'm-1',
        'sender_id': 's-1',
        'content': 'Sample video (view once)',
        'message_type': 'sample_onetime',
        'collab_asset_id': 'asset-1',
      });
      expect(message.collabAssetId, 'asset-1');
      expect(message.isCollabSample, isTrue);
      expect(message.isCollabMessage, isTrue);
      expect(message.isPropertyShare, isFalse);
    });

    test(
      'location content is "<label>\\n<mapsUrl>", url is always the last line',
      () {
        final message = ChatMessage.fromSupabase({
          'id': 'm-2',
          'sender_id': 's-1',
          'content':
              'Current location\nhttps://www.google.com/maps/search/?api=1&query=12.9,77.6',
          'message_type': 'location',
        });
        expect(message.isLocation, isTrue);
        expect(message.locationLabel, 'Current location');
        expect(
          message.locationMapsUrl,
          'https://www.google.com/maps/search/?api=1&query=12.9,77.6',
        );
      },
    );

    test('an unrecognised message_type is not treated as a collab message', () {
      final message = ChatMessage.fromSupabase({
        'id': 'm-3',
        'sender_id': 's-1',
        'content': 'hi',
        'message_type': 'text',
      });
      expect(message.isCollabMessage, isFalse);
    });
  });

  test('ConversationSummary carries collaboration_id and isCollaboration', () {
    const withCollab = ConversationSummary(
      id: 'conv-1',
      collaborationId: 'c-1',
    );
    const withoutCollab = ConversationSummary(id: 'conv-2');
    expect(withCollab.isCollaboration, isTrue);
    expect(withoutCollab.isCollaboration, isFalse);
  });

  // ── 6. Client-side upload validation (no video codec required) ────────

  group('CollaborationService upload validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('collab_upload_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('rejects a non-mp4 extension before any network call', () async {
      final file = File('${tempDir.path}/sample.mov')
        ..writeAsBytesSync([1, 2, 3]);
      final service = CollaborationService();
      await expectLater(
        service.uploadSample(collaborationId: 'c-1', file: file),
        throwsA(isA<CollabMediaValidationError>()),
      );
    });

    test(
      'rejects a sample over the 60MB ceiling before any network call',
      () async {
        final file = File('${tempDir.path}/big.mp4');
        final raf = await file.open(mode: FileMode.write);
        await raf.setPosition(CollaborationService.maxSampleBytes + 1);
        await raf.writeFrom([0]);
        await raf.close();

        final service = CollaborationService();
        await expectLater(
          service.uploadSample(collaborationId: 'c-1', file: file),
          throwsA(
            isA<CollabMediaValidationError>().having(
              (e) => e.message,
              'message',
              'Sample must be 60MB or smaller.',
            ),
          ),
        );
      },
    );

    test(
      'rejects a deliverable over the 300MB ceiling before any network call',
      () async {
        final file = File('${tempDir.path}/big_deliverable.mp4');
        final raf = await file.open(mode: FileMode.write);
        await raf.setPosition(CollaborationService.maxDeliverableBytes + 1);
        await raf.writeFrom([0]);
        await raf.close();

        final service = CollaborationService();
        await expectLater(
          service.uploadDeliverable(collaborationId: 'c-1', file: file),
          throwsA(
            isA<CollabMediaValidationError>().having(
              (e) => e.message,
              'message',
              'Deliverable must be 300MB or smaller.',
            ),
          ),
        );
      },
    );

    test('rejects an empty file', () async {
      final file = File('${tempDir.path}/empty.mp4')..writeAsBytesSync([]);
      final service = CollaborationService();
      await expectLater(
        service.uploadDeliverable(collaborationId: 'c-1', file: file),
        throwsA(isA<CollabMediaValidationError>()),
      );
    });
  }, skip: false);

  // ── 6b. Auth helper — fails closed before any network call ────────────

  group('CollabFunctionsClient', () {
    test(
      'no signed-in user -> "session expired" without touching the network',
      () async {
        final client = CollabFunctionsClient();
        await expectLater(
          client.invoke('collab-agreement', body: {'collaborationId': 'c-1'}),
          throwsA(
            isA<CollabAuthException>().having(
              (e) => e.message,
              'message',
              'Your session expired. Please sign in again.',
            ),
          ),
        );
      },
    );
  });

  // ── 7. Notifications — every collab type has a style and a filter bucket ─

  test('every collab_* notification type has a style outside the fallback', () {
    for (final type in NotificationTypes.collabTypes) {
      final style = notificationStyleFor(type);
      expect(style, isNot(same(kFallbackNotificationStyle)), reason: type);
      expect(
        kNotificationFilters.contains(style.filter) || style.filter == 'System',
        isTrue,
        reason: type,
      );
    }
    expect(NotificationTypes.collabTypes.length, 10);
  });

  test('dispute reason cap matches the server-side 1000-char limit', () {
    expect(CollaborationService.maxDisputeReasonLength, 1000);
  });
}

/// Extends the real service and overrides only the collab-list/accept/
/// decline paths this test drives — the constructor still runs
/// `CollaborationService`'s field initializer, which is why `setUpAll` above
/// initializes a (fake-URL) Supabase client first, exactly like
/// `notification_centre_test.dart`'s `_FakeService` already does for
/// `NotificationService`.
class _FakeCollabService extends CollaborationService {
  _FakeCollabService({required this.rows});

  final List<Collaboration> rows;
  final List<String> acceptedIds = [];
  final List<String> declinedIds = [];
  bool failDecline = false;

  @override
  Future<List<Collaboration>> listMyCollaborations(String userId) async => rows;

  @override
  Future<Map<String, ConversationParticipant>> resolveProfiles(
    Set<String> userIds,
  ) async => const {};

  @override
  Future<Map<String, CollabReelPreview>> resolveReels(
    Set<String> reelIds,
  ) async => const {};

  @override
  Future<Collaboration> accept(String collaborationId) async {
    acceptedIds.add(collaborationId);
    final existing = rows.firstWhere((c) => c.id == collaborationId);
    return existing.copyWith(
      status: CollabStatuses.accepted,
      conversationId: 'conv-$collaborationId',
    );
  }

  @override
  Future<Collaboration> decline(String collaborationId) async {
    if (failDecline) {
      throw const CollaborationException(
        'This collaboration can no longer be declined.',
      );
    }
    declinedIds.add(collaborationId);
    final existing = rows.firstWhere((c) => c.id == collaborationId);
    return existing.copyWith(status: CollabStatuses.declined);
  }
}

/// A `MessagingService` stand-in that returns empty results instead of
/// touching the network — `MessagingProvider.load()` fans out to
/// conversations/channels/collabs together, and this test only cares about
/// the collabs leg.
class _NoopMessagingService extends MessagingService {
  @override
  Future<List<ConversationSummary>> listConversations(String userId) async =>
      const [];

  @override
  Future<List<ChannelSummary>> listChannels(String userId) async => const [];
}

/// A `MessagingService` stand-in that returns a fixed conversation list —
/// for exercising the Chats/Collabs separation and unread cross-reference,
/// which `_NoopMessagingService`'s always-empty list can't.
class _ConversationsFakeMessagingService extends MessagingService {
  _ConversationsFakeMessagingService({required this.conversations});

  final List<ConversationSummary> conversations;

  @override
  Future<List<ConversationSummary>> listConversations(String userId) async =>
      conversations;

  @override
  Future<List<ChannelSummary>> listChannels(String userId) async => const [];
}
