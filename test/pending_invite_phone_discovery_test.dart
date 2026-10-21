// Regression guard for the phone-aware pending-invite discovery fix (item
// 44's "integrate phone-aware discovery through team-my-pending-invite" and
// "preserve invitation context across sign-in" requirements):
//
//   * PendingInviteLinkStore — the save/consume round trip
//     InviteDeepLinkHandler/PendingInvitationGate use to carry a tapped
//     invite link's `invitation`/`token` across a sign-in that wasn't
//     complete yet when the link arrived.
//   * BuilderTeamService.myPendingPhoneInvitation — the `team-my-pending-
//     invite` caller, against a bare, never-connected client (no backend
//     reachable); confirms it fails closed (`null`), never throws, so a
//     network hiccup never breaks the existing email-based discovery it
//     runs alongside.
//   * AuthProvider._checkTeamStatus's merge of the email-based list with
//     the phone-based single result — present, deduplicated by id, and
//     never dropped when the phone lookup finds nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/core/navigation/pending_invite_link_store.dart';
import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/services/builder_sections_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_service.dart';

SupabaseClient _testClient() => SupabaseClient(
  'http://localhost:54321',
  'test-anon-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

/// Controllable stand-in for the two discovery paths
/// `AuthProvider._checkTeamStatus` merges — unlike the shared
/// `FakeTeamService` (which hardcodes both to empty/null), this lets a test
/// choose what each path returns.
class _ControllableTeamService extends BuilderTeamService {
  _ControllableTeamService({this.emailInvitations = const [], this.phoneInvite})
    : super(client: _testClient());

  List<BuilderTeamInvitation> emailInvitations;
  BuilderTeamInvitation? phoneInvite;

  @override
  Future<List<BuilderTeamMember>> myActiveMemberships(String userId) async =>
      const [];

  @override
  Future<List<BuilderTeamInvitation>> myPendingInvitations(
    String email,
  ) async => emailInvitations;

  @override
  Future<BuilderTeamInvitation?> myPendingPhoneInvitation() async =>
      phoneInvite;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingInviteLinkStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('consume returns null when nothing was ever saved', () async {
      expect(await PendingInviteLinkStore.consume(), isNull);
    });

    test('save then consume round-trips the id and token', () async {
      await PendingInviteLinkStore.save(invitationId: 'inv-1', token: 'tok-1');
      final result = await PendingInviteLinkStore.consume();
      expect(result!.invitationId, 'inv-1');
      expect(result.token, 'tok-1');
    });

    test(
      'consume clears the stored value — a second read finds nothing',
      () async {
        await PendingInviteLinkStore.save(
          invitationId: 'inv-1',
          token: 'tok-1',
        );
        await PendingInviteLinkStore.consume();
        expect(await PendingInviteLinkStore.consume(), isNull);
      },
    );

    test('token is optional', () async {
      await PendingInviteLinkStore.save(invitationId: 'inv-2');
      final result = await PendingInviteLinkStore.consume();
      expect(result!.invitationId, 'inv-2');
      expect(result.token, isNull);
    });
  });

  group('BuilderTeamService.myPendingPhoneInvitation', () {
    test(
      'fails closed (null), never throws, when the function is unreachable',
      () async {
        final service = BuilderTeamService(client: _testClient());
        await expectLater(
          service.myPendingPhoneInvitation(),
          completion(isNull),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('AuthProvider._checkTeamStatus — email/phone merge', () {
    late FakeAuthService authService;

    setUp(() => SharedPreferences.setMockInitialValues({}));

    tearDown(() async => authService.dispose());

    Future<AuthProvider> signIn(_ControllableTeamService teamService) async {
      authService = FakeAuthService();
      final provider = AuthProvider(
        authService: authService,
        teamService: teamService,
      );
      final user = fakeUser('u-1', email: 'invitee@example.com');
      authService.currentUserOverride = user;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      // _checkTeamStatus runs after profile resolution; a couple of pumps
      // via a microtask flush is enough since nothing here is a real timer.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return provider;
    }

    test(
      'a phone invite is added when the email-based list found nothing',
      () async {
        const phoneInvite = BuilderTeamInvitation(
          id: 'inv-phone',
          token: 'tok-1',
          verificationMethod: 'phone_otp',
        );
        final provider = await signIn(
          _ControllableTeamService(phoneInvite: phoneInvite),
        );
        addTearDown(provider.dispose);

        expect(provider.pendingTeamInvitations, hasLength(1));
        expect(provider.pendingTeamInvitations.single.id, 'inv-phone');
        expect(provider.pendingTeamInvitations.single.isPhoneInvite, isTrue);
      },
    );

    test(
      'the same invite found both ways is listed once, not duplicated',
      () async {
        const emailInvite = BuilderTeamInvitation(
          id: 'inv-1',
          email: 'invitee@example.com',
        );
        const phoneInviteSameId = BuilderTeamInvitation(
          id: 'inv-1',
          verificationMethod: 'phone_otp',
        );
        final provider = await signIn(
          _ControllableTeamService(
            emailInvitations: const [emailInvite],
            phoneInvite: phoneInviteSameId,
          ),
        );
        addTearDown(provider.dispose);

        expect(provider.pendingTeamInvitations, hasLength(1));
        // The email-based (fuller) row wins — it was added first and the
        // phone one is only appended when its id isn't already present.
        expect(
          provider.pendingTeamInvitations.single.email,
          'invitee@example.com',
        );
      },
    );

    test(
      'no phone invite found changes nothing about the email list',
      () async {
        const emailInvite = BuilderTeamInvitation(
          id: 'inv-1',
          email: 'invitee@example.com',
        );
        final provider = await signIn(
          _ControllableTeamService(emailInvitations: const [emailInvite]),
        );
        addTearDown(provider.dispose);

        expect(provider.pendingTeamInvitations, hasLength(1));
        expect(provider.pendingTeamInvitations.single.id, 'inv-1');
      },
    );
  });
}
