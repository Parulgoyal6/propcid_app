import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/network_relationship.dart';
import 'package:propcid_app/models/network_stats.dart';
import 'package:propcid_app/providers/network_hub_provider.dart';
import 'package:propcid_app/providers/network_relationships_provider.dart';
import 'package:propcid_app/services/network_relationship_service.dart';
import 'package:propcid_app/services/network_service.dart';
import 'package:propcid_app/services/profile_connection_service.dart';

const _viewer = 'viewer-1';

void main() {
  // `_FakeNetworkService`/`_FakeRelationshipService` extend the real services
  // (overriding every method that touches `_supabase`), but their base
  // constructors still touch `Supabase.instance` on construction for the
  // non-lazy one (`NetworkService`) — which asserts `_isInitialized` even
  // before any query runs. Same pattern `network_invitations_test.dart` uses.
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

  group('classifyRelationship', () {
    test(
      'builder_id == viewer, accepted, counterpart is a real broker -> ownedNetworkMember',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other',
          status: 'accepted',
          counterpartRealUserType: 'broker',
        );
        expect(kind, NetworkRelationshipKind.ownedNetworkMember);
      },
    );

    test(
      'builder_id == viewer, accepted, counterpart is a real influencer -> ownedNetworkMember',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other',
          status: 'accepted',
          counterpartRealUserType: 'influencer',
        );
        expect(kind, NetworkRelationshipKind.ownedNetworkMember);
      },
    );

    test('the exact corrupted-direction case: builder is stored as member_id, '
        'so this row never counts as this builder\'s owned member', () {
      // A builder visited a broker's profile and clicked Connect. The
      // generic connect flow stores the recipient (the broker) as
      // builder_id and the sender (the builder) as member_id — see
      // ProfileConnectionService.sendRequest. From the BUILDER's own
      // perspective (viewerId = the builder), they are on the member_id
      // side of this row, not builder_id.
      final kind = classifyRelationship(
        viewerId: _viewer, // the builder
        builderId: 'broker-x', // the broker, per the inverted write
        memberId: _viewer, // the builder, per the inverted write
        status: 'accepted',
        counterpartRealUserType: 'broker', // the actual counterpart IS a broker
      );
      // The builder is on the member side here, and the counterpart
      // (builder_id) is a broker, not a real builder — so this must not
      // read as "a network the builder joined", and it certainly must
      // never be counted as an owned member (that requires the builder to
      // be builder_id, which they are not on this row).
      expect(kind, isNot(NetworkRelationshipKind.ownedNetworkMember));
      expect(kind, NetworkRelationshipKind.peerConnection);
    });

    test(
      'builder_id == viewer, accepted, but counterpart is another builder -> peerConnection, not owned',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other-builder',
          status: 'accepted',
          counterpartRealUserType: 'builder',
        );
        expect(kind, NetworkRelationshipKind.peerConnection);
      },
    );

    test(
      'builder_id == viewer, accepted, but counterpart is an individual -> peerConnection, not owned',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'random-individual',
          status: 'accepted',
          counterpartRealUserType: 'individual',
        );
        expect(kind, NetworkRelationshipKind.peerConnection);
      },
    );

    test(
      'member_id == viewer, accepted, counterpart is a real builder -> joinedBuilderNetwork',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: 'builder-x',
          memberId: _viewer,
          status: 'accepted',
          counterpartRealUserType: 'builder',
        );
        expect(kind, NetworkRelationshipKind.joinedBuilderNetwork);
      },
    );

    test(
      'member_id == viewer, accepted, but counterpart is a broker (peer-to-peer) -> peerConnection',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: 'broker-x',
          memberId: _viewer,
          status: 'accepted',
          counterpartRealUserType: 'broker',
        );
        expect(kind, NetworkRelationshipKind.peerConnection);
      },
    );

    test(
      'pending, viewer is builder_id -> incomingPeerRequest (recipient)',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'sender',
          status: 'pending',
        );
        expect(kind, NetworkRelationshipKind.incomingPeerRequest);
      },
    );

    test('pending, viewer is member_id -> outgoingPeerRequest (sender)', () {
      final kind = classifyRelationship(
        viewerId: _viewer,
        builderId: 'recipient',
        memberId: _viewer,
        status: 'pending',
      );
      expect(kind, NetworkRelationshipKind.outgoingPeerRequest);
    });

    test('rejected/removed never read as active, regardless of direction', () {
      for (final status in ['rejected', 'removed']) {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other',
          status: status,
          counterpartRealUserType: 'broker',
        );
        expect(kind, NetworkRelationshipKind.rejectedOrRemoved, reason: status);
      }
    });

    test(
      'accepted but the counterpart profile could not be resolved -> unknownLegacyRelationship, never promoted',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other',
          status: 'accepted',
          counterpartRealUserType: null,
        );
        expect(kind, NetworkRelationshipKind.unknownLegacyRelationship);
      },
    );

    test(
      'an unrecognised status is never mistaken for an active membership',
      () {
        final kind = classifyRelationship(
          viewerId: _viewer,
          builderId: _viewer,
          memberId: 'other',
          status: 'something_else',
          counterpartRealUserType: 'broker',
        );
        expect(kind, NetworkRelationshipKind.unknownLegacyRelationship);
        expect(isActiveMembershipKind(kind), isFalse);
      },
    );
  });

  group('NetworkRelationship.classify', () {
    NetworkRelationship build({
      String builderId = _viewer,
      String memberId = 'other',
      String? counterpartUserType = 'broker',
      String? counterpartDisplayName,
      String? counterpartCompanyName,
    }) {
      return NetworkRelationship.classify(
        {
          'id': 'r1',
          'builder_id': builderId,
          'member_id': memberId,
          'member_type': 'broker',
          'status': 'accepted',
          'verified': true,
          'commission_rate': 2.5,
          'auto_convert_leads': true,
        },
        viewerId: _viewer,
        counterpartUserType: counterpartUserType,
        counterpartDisplayName: counterpartDisplayName,
        counterpartCompanyName: counterpartCompanyName,
      );
    }

    test('prefers the person\'s own name over their company name', () {
      // Matches the portal's My Networks row: a person's name first, with
      // their company folded into the subtitle — not the other way round.
      final r = build(
        counterpartDisplayName: 'Amy Rao',
        counterpartCompanyName: 'Rao Realty',
      );
      expect(r.counterpartDisplayLabel, 'Amy Rao');
      expect(r.counterpartSubtitle, 'Rao Realty');
    });

    test('falls back to company name, then an honest "Unknown user"', () {
      expect(
        build(
          counterpartDisplayName: null,
          counterpartCompanyName: 'Rao Realty',
        ).counterpartDisplayLabel,
        'Rao Realty',
      );
      expect(build().counterpartDisplayLabel, 'Unknown user');
    });

    test(
      'roleLabel prefers the real counterpart type over the stored member_type',
      () {
        final r = build(counterpartUserType: 'influencer');
        expect(r.roleLabel, 'Influencer');
      },
    );

    test(
      'roleLabel falls back to the stored member_type when the real type is unresolved',
      () {
        final r = build(counterpartUserType: null);
        expect(r.roleLabel, 'Broker');
      },
    );

    test('a null id never becomes the literal string "null"', () {
      final r = NetworkRelationship.classify(
        {'builder_id': _viewer, 'member_id': 'other', 'status': 'accepted'},
        viewerId: _viewer,
        counterpartUserType: 'broker',
      );
      expect(r.id, '');
      expect(r.id, isNot('null'));
    });
  });

  group('NetworkHubProvider', () {
    late _FakeNetworkService networkService;
    late _FakeRelationshipService relationshipService;
    late NetworkHubProvider provider;

    setUp(() {
      networkService = _FakeNetworkService();
      relationshipService = _FakeRelationshipService();
      provider = NetworkHubProvider(
        service: networkService,
        relationshipService: relationshipService,
      );
    });

    tearDown(() => provider.dispose());

    test(
      'the "networks" count includes every active-membership kind, not just '
      'one — My Networks renders owned/joined/peer as three equally-real '
      'sections, so the hub tile must total all three or it under-reports '
      'against what that screen actually shows',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(kind: NetworkRelationshipKind.ownedNetworkMember),
          _fakeRelationship(kind: NetworkRelationshipKind.ownedNetworkMember),
          // A peer connection is still a real, accepted relationship — My
          // Networks shows it under its own "Peer Connections" section, so
          // it must count here too, not be excluded.
          _fakeRelationship(kind: NetworkRelationshipKind.peerConnection),
          _fakeRelationship(kind: NetworkRelationshipKind.joinedBuilderNetwork),
        ];
        relationshipService.nextReferralCount = 7;

        await provider.load('builder-1', isBuilder: true);

        expect(provider.stats.totalNetworks, 4);
        expect(provider.stats.totalReferrals, 7);
        expect(provider.isBuilder, isTrue);
        // Leads/commissions still come straight from NetworkService, unchanged.
        expect(provider.stats.activeLeads, networkService.canned.activeLeads);
      },
    );

    test(
      'a member\'s "networks" count includes joined AND peer rows alike',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(kind: NetworkRelationshipKind.joinedBuilderNetwork),
          _fakeRelationship(kind: NetworkRelationshipKind.peerConnection),
        ];
        relationshipService.nextReferralCount = 0;

        await provider.load('member-1', isBuilder: false);

        expect(provider.stats.totalNetworks, 2);
      },
    );

    test(
      'a failed relationship read fails the whole stats load, not silently zeros',
      () async {
        relationshipService.nextError = Exception('down');

        await provider.load('builder-1', isBuilder: true);

        expect(provider.failed, isTrue);
      },
    );
  });

  group('NetworkRelationshipsProvider', () {
    late _FakeRelationshipService relationshipService;
    late _FakeProfileConnectionService connections;
    late NetworkRelationshipsProvider provider;

    setUp(() {
      relationshipService = _FakeRelationshipService();
      connections = _FakeProfileConnectionService();
      provider = NetworkRelationshipsProvider(
        service: relationshipService,
        connectionService: connections,
      );
    });

    tearDown(() => provider.dispose());

    test('leaveNetwork succeeds and refreshes the list', () async {
      relationshipService.nextRelationships = [
        _fakeRelationship(kind: NetworkRelationshipKind.ownedNetworkMember),
      ];
      await provider.load(_viewer);

      // The row is gone after the (fake) leave — as it would be once the row
      // is 'removed' server-side.
      relationshipService.nextRelationships = const [];

      final ok = await provider.leaveNetwork('r');

      expect(ok, isTrue);
      expect(connections.leftIds, ['r']);
      expect(provider.relationships, isEmpty);
    });

    test('a failed leave surfaces an error and keeps the row', () async {
      relationshipService.nextRelationships = [
        _fakeRelationship(kind: NetworkRelationshipKind.peerConnection),
      ];
      await provider.load(_viewer);
      connections.nextLeaveError = ConnectionWriteError.failed;

      final ok = await provider.leaveNetwork('r');

      expect(ok, isFalse);
      expect(provider.leaveError, isNotNull);
      expect(provider.relationships, isNotEmpty);
    });

    test(
      'a second leaveNetwork call is ignored while one is in flight',
      () async {
        final pause = Completer<void>();
        connections.pauseNextLeave = pause;

        final first = provider.leaveNetwork('r');
        expect(provider.leavingId, 'r');

        final second = await provider.leaveNetwork('other');
        expect(second, isFalse);

        pause.complete();
        await first;
      },
    );

    test(
      'sentRequests/receivedRequests expose only the matching pending kind',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(
            kind: NetworkRelationshipKind.outgoingPeerRequest,
            id: 'sent-1',
          ),
          _fakeRelationship(
            kind: NetworkRelationshipKind.incomingPeerRequest,
            id: 'received-1',
          ),
          _fakeRelationship(kind: NetworkRelationshipKind.peerConnection),
        ];
        await provider.load(_viewer);

        expect(provider.sentRequests.map((r) => r.id), ['sent-1']);
        expect(provider.receivedRequests.map((r) => r.id), ['received-1']);
      },
    );

    test(
      'cancelSentRequest calls cancelRequest keyed by viewer/counterpart and refreshes',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(
            kind: NetworkRelationshipKind.outgoingPeerRequest,
            id: 'sent-1',
            counterpartUserId: 'them',
          ),
        ];
        await provider.load(_viewer);
        final relationship = provider.sentRequests.single;

        relationshipService.nextRelationships = const [];
        final ok = await provider.cancelSentRequest(relationship);

        expect(ok, isTrue);
        expect(connections.cancelled, [
          (viewerId: _viewer, profileUserId: 'them'),
        ]);
        expect(provider.relationships, isEmpty);
      },
    );

    test(
      'acceptReceivedRequest calls acceptRequest keyed by viewer/counterpart and refreshes',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(
            kind: NetworkRelationshipKind.incomingPeerRequest,
            id: 'received-1',
            counterpartUserId: 'them',
          ),
        ];
        await provider.load(_viewer);
        final relationship = provider.receivedRequests.single;

        final ok = await provider.acceptReceivedRequest(relationship);

        expect(ok, isTrue);
        expect(connections.accepted, [
          (viewerId: _viewer, profileUserId: 'them'),
        ]);
      },
    );

    test(
      'declineReceivedRequest calls declineRequest keyed by viewer/counterpart',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(
            kind: NetworkRelationshipKind.incomingPeerRequest,
            id: 'received-1',
            counterpartUserId: 'them',
          ),
        ];
        await provider.load(_viewer);
        final relationship = provider.receivedRequests.single;

        final ok = await provider.declineReceivedRequest(relationship);

        expect(ok, isTrue);
        expect(connections.declined, [
          (viewerId: _viewer, profileUserId: 'them'),
        ]);
      },
    );

    test('a failed accept surfaces an error and keeps the row', () async {
      relationshipService.nextRelationships = [
        _fakeRelationship(
          kind: NetworkRelationshipKind.incomingPeerRequest,
          id: 'received-1',
          counterpartUserId: 'them',
        ),
      ];
      await provider.load(_viewer);
      final relationship = provider.receivedRequests.single;
      connections.nextAcceptError = ConnectionWriteError.failed;

      final ok = await provider.acceptReceivedRequest(relationship);

      expect(ok, isFalse);
      expect(provider.actionError, isNotNull);
      expect(provider.receivedRequests, isNotEmpty);
    });

    test(
      'a second request-action call is ignored while one is in flight',
      () async {
        relationshipService.nextRelationships = [
          _fakeRelationship(
            kind: NetworkRelationshipKind.incomingPeerRequest,
            id: 'received-1',
            counterpartUserId: 'them',
          ),
          _fakeRelationship(
            kind: NetworkRelationshipKind.outgoingPeerRequest,
            id: 'sent-1',
            counterpartUserId: 'someone-else',
          ),
        ];
        await provider.load(_viewer);
        final received = provider.receivedRequests.single;
        final sent = provider.sentRequests.single;

        final pause = Completer<void>();
        connections.pauseNextAction = pause;

        final first = provider.acceptReceivedRequest(received);
        expect(provider.actingId, 'received-1');

        final second = await provider.cancelSentRequest(sent);
        expect(second, isFalse);

        pause.complete();
        await first;
      },
    );
  });
}

NetworkRelationship _fakeRelationship({
  required NetworkRelationshipKind kind,
  String id = 'r',
  String counterpartUserId = 'counterpart-1',
}) {
  // Kind is asserted directly via the constructor here (not re-derived via
  // classifyRelationship) since NetworkHubProvider only ever reads `.kind` —
  // it never re-classifies.
  return NetworkRelationship(
    id: id,
    builderId: 'b',
    memberId: 'm',
    memberType: 'broker',
    status: 'accepted',
    viewerId: 'v',
    kind: kind,
    counterpartUserId: counterpartUserId,
  );
}

class _FakeNetworkService extends NetworkService {
  final canned = const NetworkStats(
    // totalNetworks/totalReferrals are the two fields NetworkHubProvider
    // deliberately overrides with the corrected values — nonzero here so a
    // test failure to override them would be visible.
    totalNetworks: 999,
    totalReferrals: 999,
    activeLeads: 3,
    monthlyCommissions: 1000,
  );

  @override
  Future<NetworkStats> getNetworkStats(
    String userId, {
    required bool isBuilder,
  }) async {
    return canned;
  }
}

class _FakeRelationshipService extends NetworkRelationshipService {
  List<NetworkRelationship> nextRelationships = const [];
  int nextReferralCount = 0;
  Object? nextError;

  @override
  Future<List<NetworkRelationship>> listRelationships(String viewerId) async {
    final error = nextError;
    if (error != null) throw error;
    return nextRelationships;
  }

  @override
  Future<int> countReferralsMade(String userId) async {
    final error = nextError;
    if (error != null) throw error;
    return nextReferralCount;
  }
}

class _FakeProfileConnectionService extends ProfileConnectionService {
  ConnectionWriteError? nextLeaveError;
  Completer<void>? pauseNextLeave;
  final List<String> leftIds = [];

  ConnectionWriteError? nextCancelError;
  ConnectionWriteError? nextAcceptError;
  ConnectionWriteError? nextDeclineError;
  Completer<void>? pauseNextAction;
  final List<({String viewerId, String profileUserId})> cancelled = [];
  final List<({String viewerId, String profileUserId})> accepted = [];
  final List<({String viewerId, String profileUserId})> declined = [];

  @override
  Future<ConnectionWriteError?> leaveNetwork(String relationshipId) async {
    leftIds.add(relationshipId);
    final pause = pauseNextLeave;
    if (pause != null) {
      pauseNextLeave = null;
      await pause.future;
    }
    final error = nextLeaveError;
    if (error != null) {
      nextLeaveError = null;
      return error;
    }
    return null;
  }

  Future<void> _pauseIfAsked() async {
    final pause = pauseNextAction;
    if (pause != null) {
      pauseNextAction = null;
      await pause.future;
    }
  }

  @override
  Future<ConnectionWriteError?> cancelRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    cancelled.add((viewerId: viewerId!, profileUserId: profileUserId));
    await _pauseIfAsked();
    final error = nextCancelError;
    if (error != null) {
      nextCancelError = null;
      return error;
    }
    return null;
  }

  @override
  Future<ConnectionWriteError?> acceptRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    accepted.add((viewerId: viewerId!, profileUserId: profileUserId));
    await _pauseIfAsked();
    final error = nextAcceptError;
    if (error != null) {
      nextAcceptError = null;
      return error;
    }
    return null;
  }

  @override
  Future<ConnectionWriteError?> declineRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    declined.add((viewerId: viewerId!, profileUserId: profileUserId));
    await _pauseIfAsked();
    final error = nextDeclineError;
    if (error != null) {
      nextDeclineError = null;
      return error;
    }
    return null;
  }
}
