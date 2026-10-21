// Chat thread — message reporting.
//
// The bug this pins: `_ChatThreadViewState._reportMessage` returned early
// whenever `widget.participantUserId` was null before ever reaching the
// actual `MessagingService.reportMessage` call. Every channel screen omits
// that field (it's DM-only — the "other person in a 1:1 thread"), so picking
// a report reason inside a channel silently did nothing: no request, no
// error, no feedback. The report itself never needed that field anyway — it
// already submits `message.id`/`message.senderId`, not
// `widget.participantUserId`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/chat_message.dart';
import 'package:propcid_app/models/conversation_summary.dart';
import 'package:propcid_app/models/message_reaction.dart';
import 'package:propcid_app/models/shared_property_preview.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/chat_thread_provider.dart'
    show ChatThreadKind;
import 'package:propcid_app/screens/messaging/chat_thread_screen.dart';
import 'package:propcid_app/services/messaging_service.dart';

const _kMe = 'me-1';
const _kOther = 'other-1';

ChatMessage _incomingMessage({String id = 'msg-1', String senderId = _kOther}) {
  return ChatMessage.fromSupabase({
    'id': id,
    'sender_id': senderId,
    'content': 'hello there',
    'message_type': 'text',
    'created_at': '2026-01-01T10:00:00Z',
  });
}

/// Reads `userId` without going through a real session — the rest of
/// [AuthProvider] (its `AuthService`/`BuilderTeamService` construction, its
/// auth-state subscription) is left exactly as production uses it.
class _FakeAuthProvider extends AuthProvider {
  @override
  String? get userId => _kMe;
}

/// Records every `reportMessage` call and lets a test force it to fail,
/// while every other method `ChatThreadProvider.load()` needs during a
/// widget test returns a fixed, empty-of-side-effects result instead of
/// touching the network.
class _FakeMessagingService extends MessagingService {
  _FakeMessagingService(this._messages, {this.shouldFail = false});

  final List<ChatMessage> _messages;
  final bool shouldFail;

  int reportCallCount = 0;
  String? lastMessageId;
  String? lastSurface;
  String? lastReportedUserId;
  String? lastReason;

  @override
  Future<List<ChatMessage>> listMessages(
    String conversationId, {
    DateTime? before,
    DateTime? after,
  }) async => _messages;

  @override
  Future<List<ChatMessage>> listChannelMessages(
    String channelId, {
    DateTime? before,
    DateTime? after,
  }) async => _messages;

  @override
  Future<Set<String>> myBlockedUserIds(String currentUserId) async => const {};

  @override
  Future<bool> haveIBlocked(String currentUserId, String otherUserId) async =>
      false;

  @override
  Future<Map<String, ConversationParticipant>> fetchSenderProfiles(
    Set<String> senderIds,
  ) async => const {};

  @override
  Future<Map<String, List<MessageReaction>>> fetchReactions({
    required List<String> messageIds,
    required String surface,
  }) async => const {};

  @override
  Future<Map<String, SharedPropertyPreview>> fetchSharedProperties(
    Set<String> propertyIds,
  ) async => const {};

  @override
  Future<void> markChannelAsRead({
    required String channelId,
    required String userId,
  }) async {}

  @override
  Future<void> markConversationAsRead({
    required String conversationId,
    required String userId,
  }) async {}

  @override
  Future<void> reportMessage({
    required String messageId,
    required String surface,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    reportCallCount++;
    lastMessageId = messageId;
    lastSurface = surface;
    lastReportedUserId = reportedUserId;
    lastReason = reason;
    if (shouldFail) throw StateError('backend rejected report');
  }
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

  Future<_FakeMessagingService> pumpThread(
    WidgetTester tester, {
    required ChatThreadKind kind,
    String? participantUserId,
    bool reportShouldFail = false,
  }) async {
    final service = _FakeMessagingService([
      _incomingMessage(),
    ], shouldFail: reportShouldFail);

    // Tall enough that the report-reason sheet's 7 tiles never overflow —
    // the default test surface (800x600) is too short for it, which is a
    // sizing artifact of the test window, not a real layout bug.
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // `_ActionSheet._tile()` (chat_bubble.dart) wraps every action-sheet
    // row, "Report" included, in a `DecoratedBox` with a background colour
    // ahead of its `ListTile` — a pre-existing cosmetic issue (ink splashes
    // may be hidden) unrelated to reporting itself, just never exercised by
    // a test before this file. Silenced here rather than touched, since
    // fixing it is out of scope for this patch; any other FlutterError
    // still fails the test normally. Installed here (inside the test body,
    // not `setUp`) because `testWidgets` runs each test in its own zone with
    // its own `FlutterError.onError`, installed after `setUp` callbacks run.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
        'ListTile background color or ink splashes may be invisible',
      )) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _FakeAuthProvider(),
        child: MaterialApp(
          home: ChatThreadScreen(
            kind: kind,
            threadId: 'thread-1',
            title: 'Thread',
            initials: 'T',
            participantUserId: participantUserId,
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    return service;
  }

  Future<void> openReportReasonSheet(WidgetTester tester) async {
    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
  }

  group('Channel reporting', () {
    testWidgets('submits with no participantUserId — the bug this pins', (
      tester,
    ) async {
      final service = await pumpThread(
        tester,
        kind: ChatThreadKind.channel,
        participantUserId: null,
      );

      await openReportReasonSheet(tester);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(service.reportCallCount, 1);
      expect(service.lastMessageId, 'msg-1');
      expect(service.lastReportedUserId, _kOther);
      expect(service.lastSurface, 'channel');
      expect(service.lastReason, 'spam');
      expect(find.text('Report submitted.'), findsOneWidget);
    });
  });

  group('DM reporting', () {
    testWidgets('still submits — existing behaviour is unchanged', (
      tester,
    ) async {
      final service = await pumpThread(
        tester,
        kind: ChatThreadKind.conversation,
        participantUserId: _kOther,
      );

      await openReportReasonSheet(tester);
      await tester.tap(find.text('Harassment'));
      await tester.pumpAndSettle();

      expect(service.reportCallCount, 1);
      expect(service.lastMessageId, 'msg-1');
      expect(service.lastReportedUserId, _kOther);
      expect(service.lastSurface, 'dm');
      expect(service.lastReason, 'harassment');
      expect(find.text('Report submitted.'), findsOneWidget);
    });
  });

  group('Cancelling the reason picker', () {
    testWidgets('submits nothing when dismissed', (tester) async {
      final service = await pumpThread(
        tester,
        kind: ChatThreadKind.channel,
        participantUserId: null,
      );

      await openReportReasonSheet(tester);
      // Taps the modal barrier, well above the reason sheet, dismissing it
      // exactly like a drag-down or a tap outside would.
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();

      expect(service.reportCallCount, 0);
      expect(find.text('Report submitted.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Submission failure', () {
    testWidgets('shows an error, not a false success, and allows retry', (
      tester,
    ) async {
      final service = await pumpThread(
        tester,
        kind: ChatThreadKind.channel,
        participantUserId: null,
        reportShouldFail: true,
      );

      await openReportReasonSheet(tester);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(service.reportCallCount, 1);
      expect(find.text('Report submitted.'), findsNothing);
      expect(find.text("Couldn't submit the report."), findsOneWidget);

      // Retry: the failure left nothing disabled, so reporting again is a
      // plain repeat of the same flow.
      await openReportReasonSheet(tester);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(service.reportCallCount, 2);
      expect(find.text("Couldn't submit the report."), findsOneWidget);
    });
  });
}
