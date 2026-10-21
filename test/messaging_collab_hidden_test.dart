// Messages screen — the Collabs tab, and MessagingProvider's collaboration
// loading, with paid collaborations disabled (the default).
//
// What this pins:
//   * the screen shows only Chats and Channels — no third tab at all;
//   * MessagingProvider never queries collaborations, on the initial load
//     or a refresh — not just "the tab is hidden while a query still runs
//     behind it".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/channel_summary.dart';
import 'package:propcid_app/models/collaboration.dart';
import 'package:propcid_app/models/conversation_summary.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/messaging/messages_list_screen.dart';
import 'package:propcid_app/services/collaboration_service.dart';
import 'package:propcid_app/services/messaging_service.dart';

class _FakeAuth extends AuthProvider {
  @override
  String? get userId => 'u-1';
}

/// Enough of `MessagingService` for `MessagingProvider.load`/`refresh` to
/// succeed without touching Supabase.
class _FakeMessagingService extends MessagingService {
  @override
  Future<List<ConversationSummary>> listConversations(String userId) async =>
      const [];

  @override
  Future<List<ChannelSummary>> listChannels(String userId) async => const [];
}

/// Records whether `listMyCollaborations` is ever called — the query that
/// backs the Collabs tab.
class _CountingCollabService extends CollaborationService {
  int calls = 0;

  @override
  Future<List<Collaboration>> listMyCollaborations(String userId) async {
    calls++;
    return const [];
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

  testWidgets(
    'shows only Chats and Channels, and never queries collaborations',
    (tester) async {
      final collabService = _CountingCollabService();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => _FakeAuth(),
          child: MaterialApp(
            home: MessagesListScreen(
              service: _FakeMessagingService(),
              collabService: collabService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.textContaining('Collabs'), findsNothing);
      expect(collabService.calls, 0);

      // A pull-to-refresh must not start querying collaborations either.
      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();
      expect(collabService.calls, 0);
    },
  );
}
