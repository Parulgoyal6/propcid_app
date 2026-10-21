// Spec F — Network Invitations + Collaboration Hub.
//
// What is pinned:
//
//   * `member_type` is CHECK-constrained to ('broker','influencer') — a builder
//     does not invite builders, and `individual` is not accepted even though
//     `builder_networks.member_type` carries it;
//   * an expired invitation is NOT actionable, which is the contract's explicit
//     requirement. `expires_at` defaults to +7 days and nothing flips `status` to
//     `'expired'`, so a row can read `pending` while being unusable;
//   * accept is the two-step the portal does — mark the invitation, then write
//     `builder_networks` — and the write is an UPSERT, not the portal's insert,
//     because a prior rejected row still holds the unique pair;
//   * decline marks rather than deletes, so the sender sees the outcome;
//   * an invitation with no `invited_user_id` cannot be accepted in-app;
//   * `network_service.dart` is untouched — the boundary this whole file exists to
//     respect.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/network_models.dart';
import 'package:propcid_app/screens/network/widgets/network_invitations_section.dart';
import 'package:propcid_app/services/profile_connection_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

// ── Fixtures ────────────────────────────────────────────────────────────────

NetworkInvitation _invitation({
  String id = 'inv-1',
  String builderId = 'b-1',
  String memberType = 'broker',
  String status = 'pending',
  Object? invitedUserId = 'u-1',
  String? email,
  String? phone,
  String? message = 'Come and market our new launch.',
  String? expiresAt = '2099-01-01T00:00:00Z',
  String? counterpartName = 'Prestige Estates',
}) => NetworkInvitation.fromSupabase({
  'id': id,
  'builder_id': builderId,
  'invited_user_id': invitedUserId,
  'email': email,
  'phone': phone,
  'member_type': memberType,
  'invitation_message': message,
  'status': status,
  'expires_at': expiresAt,
  'created_at': '2026-05-01T10:00:00Z',
}, counterpartName: counterpartName);

// ── Fake ────────────────────────────────────────────────────────────────────

class _FakeConnections extends ProfileConnectionService {
  _FakeConnections({this.inbox = NetworkInvitationInbox.empty});

  NetworkInvitationInbox inbox;

  ConnectionWriteError? acceptError;
  ConnectionWriteError? declineError;
  ConnectionWriteError? inviteError;

  final List<String> accepted = [];
  final List<String> declined = [];
  final List<
    ({
      String memberType,
      String? userId,
      String? email,
      String? phone,
      String? message,
    })
  >
  invites = [];
  final List<String> searches = [];
  int loads = 0;

  List<InviteeSuggestion> results = const [];

  @override
  Future<NetworkInvitationInbox> listInvitations(String? viewerId) async {
    loads++;
    if (viewerId == null || viewerId.isEmpty) {
      return NetworkInvitationInbox.empty;
    }
    return inbox;
  }

  @override
  Future<ConnectionWriteError?> acceptInvitation({
    required String? viewerId,
    required NetworkInvitation invitation,
  }) async {
    accepted.add(invitation.id);
    final error = acceptError;
    acceptError = null;
    return error;
  }

  @override
  Future<ConnectionWriteError?> declineInvitation({
    required String? viewerId,
    required NetworkInvitation invitation,
  }) async {
    declined.add(invitation.id);
    final error = declineError;
    declineError = null;
    return error;
  }

  @override
  Future<ConnectionWriteError?> sendBuilderInvite({
    required String? viewerId,
    required String memberType,
    String? invitedUserId,
    String? email,
    String? phone,
    String? message,
  }) async {
    invites.add((
      memberType: memberType,
      userId: invitedUserId,
      email: email,
      phone: phone,
      message: message,
    ));
    final error = inviteError;
    inviteError = null;
    return error;
  }

  @override
  Future<List<InviteeSuggestion>> searchInvitees(String term) async {
    searches.add(term);
    return results;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
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

  // ── 1. The member_type vocabulary ───────────────────────────────────────
  group('member types', () {
    test('is exactly the CHECK constraint', () {
      // member_type TEXT NOT NULL CHECK (member_type IN ('broker','influencer'))
      // — 20250905144708:51, and the portal's TS union matches.
      expect(kNetworkMemberTypes.map((t) => t.value).toList(), [
        'broker',
        'influencer',
      ]);
    });

    test(
      'individual is not invitable, even though builder_networks carries it',
      () {
        // `builder_networks.member_type` does hold 'individual' — sendRequest writes
        // it from the sender's own user_type — but an *invitation* cannot.
        expect(isValidNetworkMemberType('broker'), isTrue);
        expect(isValidNetworkMemberType('influencer'), isTrue);
        expect(isValidNetworkMemberType('individual'), isFalse);
        expect(isValidNetworkMemberType('builder'), isFalse);
        expect(isValidNetworkMemberType(null), isFalse);
      },
    );

    test('a stored value outside the picker still reads', () {
      expect(networkMemberTypeLabel('broker'), 'Broker');
      expect(networkMemberTypeLabel('individual'), 'Individual');
      expect(networkMemberTypeLabel(null), 'Member');
      expect(networkMemberTypeLabel(''), 'Member');
    });
  });

  // ── 2. Expiry — the contract's explicit requirement ─────────────────────
  group('expiry', () {
    test('a lapsed pending invitation is not actionable', () {
      // Nothing sets status to 'expired' synchronously, so the row still reads
      // 'pending'. Acting on it must still be refused.
      final lapsed = _invitation(expiresAt: '2020-01-01T00:00:00Z');
      expect(lapsed.status, 'pending');
      expect(lapsed.hasLapsed, isTrue);
      expect(lapsed.isActionable, isFalse);
    });

    test('a live pending invitation is actionable', () {
      expect(_invitation().isActionable, isTrue);
    });

    test('a null expiry never lapses', () {
      // The column is nullable despite its default.
      final noExpiry = _invitation(expiresAt: null);
      expect(noExpiry.hasLapsed, isFalse);
      expect(noExpiry.isActionable, isTrue);
    });

    test('an already-answered invitation is not actionable', () {
      expect(_invitation(status: 'accepted').isActionable, isFalse);
      expect(_invitation(status: 'rejected').isActionable, isFalse);
      expect(_invitation(status: 'expired').isActionable, isFalse);
    });
  });

  // ── 3. The model ────────────────────────────────────────────────────────
  group('NetworkInvitation', () {
    test('the recipient label prefers a name, then email, then phone', () {
      expect(_invitation().recipientLabel, 'Prestige Estates');
      expect(
        _invitation(counterpartName: null, email: 'a@b.com').recipientLabel,
        'a@b.com',
      );
      expect(
        _invitation(counterpartName: null, phone: '9876543210').recipientLabel,
        '9876543210',
      );
    });

    test('no invited_user_id means off-platform', () {
      // Those cannot be accepted in-app — no session id to match.
      expect(_invitation(invitedUserId: null).isOffPlatform, isTrue);
      expect(_invitation().isOffPlatform, isFalse);
    });

    test('the inbox counts only actionable received invitations', () {
      final inbox = NetworkInvitationInbox(
        received: [
          _invitation(id: 'a'),
          _invitation(id: 'b', status: 'accepted'),
          _invitation(id: 'c', expiresAt: '2020-01-01T00:00:00Z'),
        ],
        sent: [_invitation(id: 'd')],
      );
      expect(inbox.received, hasLength(3));
      expect(inbox.actionable, hasLength(1));
      expect(inbox.actionable.single.id, 'a');
      expect(inbox.isEmpty, isFalse);
    });
  });

  // ── 4. The section ──────────────────────────────────────────────────────
  group('NetworkInvitationsSection', () {
    testWidgets('renders a received invitation with accept and decline', (
      tester,
    ) async {
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          service: _FakeConnections(
            inbox: NetworkInvitationInbox(received: [_invitation()]),
          ),
        ),
        size: const Size(320, 1000),
      );

      expect(find.text('RECEIVED'), findsOneWidget);
      expect(find.text('Prestige Estates'), findsOneWidget);
      expect(find.text('Broker'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Come and market our new launch.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('1 awaiting your reply'), findsOneWidget);
    });

    testWidgets('a sent invitation has no accept or decline', (tester) async {
      // The recipient decides; withdrawing is cancelRequest on the profile screen.
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          service: _FakeConnections(
            inbox: NetworkInvitationInbox(sent: [_invitation()]),
          ),
        ),
        size: const Size(320, 1000),
      );

      expect(find.text('SENT'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
    });

    testWidgets('an expired invitation lists but cannot be acted on', (
      tester,
    ) async {
      final service = _FakeConnections(
        inbox: NetworkInvitationInbox(
          received: [_invitation(expiresAt: '2020-01-01T00:00:00Z')],
        ),
      );
      await _pump(
        tester,
        NetworkInvitationsSection(userId: 'u-1', service: service),
        size: const Size(320, 1000),
      );

      // Reads as Expired even though the stored status is still 'pending' —
      // telling a user it is pending when no button works would be wrong.
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(service.accepted, isEmpty);
    });

    testWidgets('an answered invitation shows its outcome', (tester) async {
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          service: _FakeConnections(
            inbox: NetworkInvitationInbox(
              received: [_invitation(status: 'rejected')],
            ),
          ),
        ),
        size: const Size(320, 1000),
      );
      // 'Declined', not 'Rejected' — the word the user chose.
      expect(find.text('Declined'), findsOneWidget);
    });

    testWidgets('accepting writes and refreshes the hub', (tester) async {
      final service = _FakeConnections(
        inbox: NetworkInvitationInbox(received: [_invitation()]),
      );
      var refreshed = 0;
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          service: service,
          onChanged: () => refreshed++,
        ),
        size: const Size(320, 1000),
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(service.accepted, ['inv-1']);
      expect(find.text('Invitation accepted.'), findsOneWidget);
      // An accepted invitation becomes a builder_networks row, which is what the
      // hub's stats grid counts.
      expect(refreshed, 1);
    });

    testWidgets('declining confirms first and says the sender will see it', (
      tester,
    ) async {
      final service = _FakeConnections(
        inbox: NetworkInvitationInbox(received: [_invitation()]),
      );
      await _pump(
        tester,
        NetworkInvitationsSection(userId: 'u-1', service: service),
        size: const Size(320, 1000),
      );

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('will see that it was declined'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();
      expect(service.declined, isEmpty);

      await tester.tap(find.text('Decline').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(service.declined, ['inv-1']);
    });

    testWidgets('a stale row is reported and triggers a reload', (
      tester,
    ) async {
      final service = _FakeConnections(
        inbox: NetworkInvitationInbox(received: [_invitation()]),
      )..acceptError = ConnectionWriteError.nothingToAccept;
      await _pump(
        tester,
        NetworkInvitationsSection(userId: 'u-1', service: service),
        size: const Size(320, 1000),
      );
      final loadsBefore = service.loads;

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(
        find.text('That invitation is no longer pending.'),
        findsOneWidget,
      );
      expect(service.loads, greaterThan(loadsBefore));
    });

    testWidgets('an off-platform invite explains why it is inert', (
      tester,
    ) async {
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          service: _FakeConnections(
            inbox: NetworkInvitationInbox(
              sent: [
                _invitation(
                  invitedUserId: null,
                  email: 'new@example.com',
                  counterpartName: null,
                ),
              ],
            ),
          ),
        ),
        size: const Size(320, 1000),
      );

      expect(find.text('new@example.com'), findsOneWidget);
      expect(
        find.text('Waiting for them to create an account.'),
        findsOneWidget,
      );
    });

    testWidgets('an empty inbox says so and still offers Invite to a builder', (
      tester,
    ) async {
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          isBuilder: true,
          service: _FakeConnections(),
        ),
      );
      expect(find.text('No invitations yet.'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
    });

    testWidgets('a non-builder never sees the Invite control', (tester) async {
      await _pump(
        tester,
        NetworkInvitationsSection(userId: 'u-1', service: _FakeConnections()),
      );
      expect(find.text('No invitations yet.'), findsOneWidget);
      expect(find.text('Invite'), findsNothing);
    });

    testWidgets('a signed-out viewer loads nothing and cannot invite', (
      tester,
    ) async {
      final service = _FakeConnections(
        inbox: NetworkInvitationInbox(received: [_invitation()]),
      );
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: null,
          isBuilder: true,
          service: service,
        ),
      );

      expect(find.text('Prestige Estates'), findsNothing);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Invite'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          isBuilder: true,
          service: _FakeConnections(
            inbox: NetworkInvitationInbox(
              received: [_invitation()],
              sent: [_invitation(id: 'inv-2', memberType: 'influencer')],
            ),
          ),
        ),
        textScale: 1.3,
        size: const Size(320, 1800),
      );

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 5. The invite form ──────────────────────────────────────────────────
  group('invite form', () {
    Future<_FakeConnections> openSheet(
      WidgetTester tester, {
      List<InviteeSuggestion> results = const [],
    }) async {
      final service = _FakeConnections()..results = results;
      await _pump(
        tester,
        NetworkInvitationsSection(
          userId: 'u-1',
          isBuilder: true,
          service: service,
        ),
        size: const Size(360, 2600),
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('no member type is refused', (tester) async {
      // The portal's own rule (`:179-181`) and a NOT NULL CHECK column.
      final service = await openSheet(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose whether they are a broker or influencer.'),
        findsOneWidget,
      );
      expect(service.invites, isEmpty);
    });

    testWidgets('no recipient at all is refused', (tester) async {
      // All three recipient columns are nullable, so the database would take it.
      final service = await openSheet(tester);
      await tester.tap(find.text('Broker'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pick someone, or enter an email or phone number.'),
        findsOneWidget,
      );
      expect(service.invites, isEmpty);
    });

    testWidgets('an email invite sends no user id', (tester) async {
      final service = await openSheet(tester);
      await tester.tap(find.text('Influencer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'name@example.com'),
        'new@example.com',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      final invite = service.invites.single;
      expect(invite.memberType, 'influencer');
      expect(invite.email, 'new@example.com');
      expect(invite.userId, isNull);
    });

    testWidgets('picking someone sends their id and drops the email', (
      tester,
    ) async {
      // The portal keeps its two insert paths separate; the payload must not carry
      // both a user id and an email.
      final service = await openSheet(
        tester,
        results: const [
          InviteeSuggestion(
            userId: 'u-9',
            name: 'Asha Menon',
            userType: 'broker',
          ),
        ],
      );

      await tester.tap(find.text('Broker'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'name@example.com'),
        'typed@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        'asha',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asha Menon'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      final invite = service.invites.single;
      expect(invite.userId, 'u-9');
      expect(invite.email, isNull, reason: 'the typed email was cleared');
    });

    testWidgets('a short search term is not sent', (tester) async {
      final service = await openSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        'a',
      );
      await tester.pumpAndSettle();
      expect(service.searches, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        'as',
      );
      await tester.pumpAndSettle();
      expect(service.searches, ['as']);
    });

    testWidgets('the note is optional and trimmed to null when blank', (
      tester,
    ) async {
      final service = await openSheet(tester);
      await tester.tap(find.text('Broker'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'name@example.com'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Optional note'),
        '   ',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(service.invites.single.message, isNull);
    });
  });

  // ── 6. Service guards ───────────────────────────────────────────────────
  group('service guards', () {
    test('an anonymous viewer gets an empty inbox, not a query', () async {
      expect(
        (await ProfileConnectionService().listInvitations(null)).isEmpty,
        isTrue,
      );
      expect(
        (await ProfileConnectionService().listInvitations('')).isEmpty,
        isTrue,
      );
    });

    test(
      'an expired invitation is refused at the service, not just the UI',
      () async {
        // The UI hiding a button is not a guarantee.
        final error = await ProfileConnectionService().acceptInvitation(
          viewerId: 'u-1',
          invitation: _invitation(expiresAt: '2020-01-01T00:00:00Z'),
        );
        expect(error, ConnectionWriteError.nothingToAccept);

        final declineError = await ProfileConnectionService().declineInvitation(
          viewerId: 'u-1',
          invitation: _invitation(expiresAt: '2020-01-01T00:00:00Z'),
        );
        expect(declineError, ConnectionWriteError.nothingToAccept);
      },
    );

    test('an anonymous viewer cannot accept or decline', () async {
      expect(
        await ProfileConnectionService().acceptInvitation(
          viewerId: null,
          invitation: _invitation(),
        ),
        ConnectionWriteError.notAllowed,
      );
      expect(
        await ProfileConnectionService().declineInvitation(
          viewerId: '',
          invitation: _invitation(),
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('an invalid member_type is refused before the round trip', () async {
      expect(
        await ProfileConnectionService().sendBuilderInvite(
          viewerId: 'u-1',
          memberType: 'individual',
          invitedUserId: 'u-2',
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('an invite with no recipient is refused', () async {
      expect(
        await ProfileConnectionService().sendBuilderInvite(
          viewerId: 'u-1',
          memberType: 'broker',
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('a builder cannot invite themselves', () async {
      expect(
        await ProfileConnectionService().sendBuilderInvite(
          viewerId: 'u-1',
          memberType: 'broker',
          invitedUserId: 'u-1',
        ),
        ConnectionWriteError.notAllowed,
      );
    });

    test('a short search term never reaches the database', () async {
      expect(await ProfileConnectionService().searchInvitees(''), isEmpty);
      expect(await ProfileConnectionService().searchInvitees('a'), isEmpty);
      expect(await ProfileConnectionService().searchInvitees('  a '), isEmpty);
    });
  });
}
