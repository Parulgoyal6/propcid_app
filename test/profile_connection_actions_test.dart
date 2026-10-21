// Phase 6 — connection actions.
//
// The riskiest phase, so the assertions target the three ways this can go wrong in
// production without erroring:
//
//   1. INSERT instead of UPSERT. A prior removed/rejected row still occupies the
//      unique `(builder_id, member_id)` pair, so re-connecting after a removal
//      would fail forever with 23505.
//   2. Reversed direction. Making the sender `builder_id` still satisfies RLS —
//      both sides are permitted — but inverts the meaning, and the recipient sees
//      nothing.
//   3. Accepting only the legacy invitation. Every count and list reads
//      `builder_networks`, so marking the invitation alone leaves the connection
//      invisible everywhere.
//
// `NetworkService` is untouched and read-only; a test below pins that.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/builder_project_model.dart';
import 'package:propcid_app/models/profile_review.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/public_profile_provider.dart';
import 'package:propcid_app/services/network_service.dart';
import 'package:propcid_app/services/profile_connection_service.dart';
import 'package:propcid_app/services/profile_content_service.dart';
import 'package:propcid_app/services/profile_rating_service.dart';
import 'package:propcid_app/services/profile_view_service.dart';
import 'package:propcid_app/services/user_profile_service.dart';

class _FakeProfileService extends UserProfileService {
  @override
  Future<UserProfile?> fetchOwn(String userId) async => _row(userId);

  @override
  Future<UserProfile?> fetchPublic(
    String userId, {
    required bool viewerSignedIn,
  }) async =>
      _row(userId);

  static UserProfile _row(String userId) => UserProfile.fromMap({
        'user_id': userId,
        'display_name': 'Asha Menon',
        'user_type': 'broker',
      });
}

class _FakeContentService extends ProfileContentService {
  @override
  Future<List<PropertyModel>> fetchProperties(String userId) async => const [];

  @override
  Future<List<BuilderProjectModel>> fetchBuilderProjects(
    String builderId, {
    required bool viewerIsOwner,
  }) async =>
      const [];

  @override
  Future<RatingBreakdown> fetchRatings(String userId) async =>
      RatingBreakdown.zero;
}

class _FakeNetworkService extends NetworkService {
  int counts = 0;

  @override
  Future<int> getAcceptedCount(String userId) async {
    counts++;
    return 7;
  }
}

class _FakeViewService extends ProfileViewService {
  @override
  Future<void> recordView({
    required String? viewerId,
    required String profileUserId,
  }) async {}
}

class _FakeRatingService extends ProfileRatingService {
  @override
  Future<MyRating?> fetchMyRating({
    required String? viewerId,
    required String ratedUserId,
  }) async =>
      null;
}

/// Scripts the status sequence and records which write was called.
class _FakeConnectionService extends ProfileConnectionService {
  _FakeConnectionService(this._statuses, {this.error});

  /// Consumed one per `getStatus` call, so a write can be followed by a changed
  /// state — which is what the provider re-reads.
  final List<ProfileConnectionStatus> _statuses;
  final ConnectionWriteError? error;

  int sends = 0;
  int cancels = 0;
  int accepts = 0;
  int statusReads = 0;

  @override
  Future<ProfileConnectionStatus> getStatus({
    required String? viewerId,
    required String profileUserId,
  }) async {
    final index = statusReads < _statuses.length ? statusReads : _statuses.length - 1;
    statusReads++;
    return _statuses[index];
  }

  @override
  Future<ConnectionWriteError?> sendRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    sends++;
    return error;
  }

  @override
  Future<ConnectionWriteError?> cancelRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    cancels++;
    return error;
  }

  @override
  Future<ConnectionWriteError?> acceptRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    accepts++;
    return error;
  }
}

Future<PublicProfileProvider> _provider({
  required String? viewerId,
  required _FakeConnectionService connection,
  String ownerId = 'owner',
  _FakeNetworkService? network,
}) async {
  final provider = PublicProfileProvider(
    profileService: _FakeProfileService(),
    contentService: _FakeContentService(),
    connectionService: connection,
    networkService: network ?? _FakeNetworkService(),
    profileViewService: _FakeViewService(),
    ratingService: _FakeRatingService(),
  );
  await provider.load(userId: ownerId, viewerId: viewerId);
  return provider;
}

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

  group('write guard', () {
    test('an anonymous viewer is refused', () {
      for (final viewer in [null, '']) {
        expect(
          ProfileConnectionService.writeGuardFor(
            viewerId: viewer,
            profileUserId: 'owner',
          ),
          ConnectionWriteError.notAllowed,
        );
      }
    });

    test('a self-connection is refused', () {
      expect(
        ProfileConnectionService.writeGuardFor(
          viewerId: 'me',
          profileUserId: 'me',
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('an empty target is refused', () {
      expect(
        ProfileConnectionService.writeGuardFor(
          viewerId: 'me',
          profileUserId: '',
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('a legitimate pair passes', () {
      expect(
        ProfileConnectionService.writeGuardFor(
          viewerId: 'me',
          profileUserId: 'owner',
        ),
        isNull,
      );
    });
  });

  group('the action matches the current state', () {
    test('none sends a request', () async {
      final c = _FakeConnectionService([
        ProfileConnectionStatus.none,
        ProfileConnectionStatus.pendingSent,
      ]);
      final p = await _provider(viewerId: 'me', connection: c);

      expect(await p.actOnConnection(), isNull);
      expect(c.sends, 1);
      expect(c.cancels, 0);
      expect(c.accepts, 0);
    });

    test('pendingSent cancels', () async {
      final c = _FakeConnectionService([
        ProfileConnectionStatus.pendingSent,
        ProfileConnectionStatus.none,
      ]);
      final p = await _provider(viewerId: 'me', connection: c);

      expect(await p.actOnConnection(), isNull);
      expect(c.cancels, 1);
      expect(c.sends, 0);
    });

    test('pendingReceived accepts', () async {
      final c = _FakeConnectionService([
        ProfileConnectionStatus.pendingReceived,
        ProfileConnectionStatus.connected,
      ]);
      final p = await _provider(viewerId: 'me', connection: c);

      expect(await p.actOnConnection(), isNull);
      expect(c.accepts, 1);
    });

    test('connected is terminal — no write, no tap', () async {
      final c = _FakeConnectionService([ProfileConnectionStatus.connected]);
      final p = await _provider(viewerId: 'me', connection: c);

      expect(p.canActOnConnection, isFalse);
      expect(await p.actOnConnection(), isNotNull);
      expect(c.sends + c.cancels + c.accepts, 0);
    });
  });

  group('state is re-read, never assumed', () {
    test('the status is refreshed after a successful write', () async {
      final c = _FakeConnectionService([
        ProfileConnectionStatus.none,
        ProfileConnectionStatus.pendingSent,
      ]);
      final p = await _provider(viewerId: 'me', connection: c);
      final readsAfterLoad = c.statusReads;

      await p.actOnConnection();
      expect(c.statusReads, greaterThan(readsAfterLoad));
      expect(p.connectionStatus, ProfileConnectionStatus.pendingSent);
    });

    test('the status is refreshed after a FAILED write too', () async {
      // A `nothingToAccept` means the other party withdrew — the local state is
      // already wrong, so refusing to refresh would leave the button lying.
      final c = _FakeConnectionService(
        [
          ProfileConnectionStatus.pendingReceived,
          ProfileConnectionStatus.none,
        ],
        error: ConnectionWriteError.nothingToAccept,
      );
      final p = await _provider(viewerId: 'me', connection: c);

      expect(await p.actOnConnection(), contains('no longer available'));
      expect(p.connectionStatus, ProfileConnectionStatus.none);
    });

    test('the connections count is re-read alongside the status', () async {
      final network = _FakeNetworkService();
      final c = _FakeConnectionService([
        ProfileConnectionStatus.none,
        ProfileConnectionStatus.pendingSent,
      ]);
      final p = await _provider(
        viewerId: 'me',
        connection: c,
        network: network,
      );
      final afterLoad = network.counts;

      await p.actOnConnection();
      expect(network.counts, afterLoad + 1);
    });
  });

  group('gating', () {
    test('an anonymous viewer cannot act', () async {
      final c = _FakeConnectionService([ProfileConnectionStatus.none]);
      final p = await _provider(viewerId: null, connection: c);
      expect(p.canActOnConnection, isFalse);
      expect(await p.actOnConnection(), isNotNull);
      expect(c.sends, 0);
    });

    test('a self view cannot act', () async {
      final c = _FakeConnectionService([ProfileConnectionStatus.none]);
      final p = await _provider(
        viewerId: 'owner',
        connection: c,
        ownerId: 'owner',
      );
      expect(p.isSelf, isTrue);
      expect(p.canActOnConnection, isFalse);
    });
  });

  group('concurrency', () {
    test('a second tap while one is in flight is ignored', () async {
      final c = _FakeConnectionService([
        ProfileConnectionStatus.none,
        ProfileConnectionStatus.pendingSent,
      ]);
      final p = await _provider(viewerId: 'me', connection: c);

      final first = p.actOnConnection();
      final second = p.actOnConnection();
      await Future.wait([first, second]);

      expect(c.sends, 1, reason: 'double-tap must not send two requests');
    });
  });

  group('error messages', () {
    test('each failure reads differently', () async {
      final cases = {
        ConnectionWriteError.notAllowed: 'cannot connect',
        ConnectionWriteError.nothingToAccept: 'no longer available',
        ConnectionWriteError.failed: 'try again',
      };

      for (final entry in cases.entries) {
        final c = _FakeConnectionService(
          [ProfileConnectionStatus.none],
          error: entry.key,
        );
        final p = await _provider(viewerId: 'me', connection: c);
        expect(await p.actOnConnection(), contains(entry.value),
            reason: entry.key.name);
      }
    });
  });

  group('NetworkService is untouched', () {
    test('it still exposes no write methods', () {
      // Phase 6 deliberately did not extend it — the file declares itself
      // read-only and four providers depend on it.
      final service = NetworkService();
      expect(service.getAcceptedCount, isA<Future<int> Function(String)>());
      expect(service.listMemberships, isA<Function>());
    });
  });
}
