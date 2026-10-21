// Regression coverage for Issue 4: the reel-share card in DM chat.
//
// Verifies the full chain the Phase 0 investigation traced end-to-end:
// sendReelShare's `reel_id` write -> the SELECT column set (DM and, since
// `20271007060000_channel_messages_reel_share.sql`, channel too) ->
// batched preview hydration in ChatThreadProvider (initial load, pagination,
// and the realtime-fallback refresh path) -> ReelSharePreviewCard rendering
// -> tapping opens the existing Reels route. Also pins that property share,
// plain text, and image messages are all unaffected by this change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/chat_message.dart';
import 'package:propcid_app/models/conversation_summary.dart';
import 'package:propcid_app/models/message_reaction.dart';
import 'package:propcid_app/models/shared_property_preview.dart';
import 'package:propcid_app/models/shared_reel_preview.dart';
import 'package:propcid_app/providers/chat_thread_provider.dart';
import 'package:propcid_app/screens/messaging/widgets/chat_bubble.dart';
import 'package:propcid_app/services/messaging_service.dart';

ChatMessage _reelShareMessage({
  required String id,
  required String reelId,
  String senderId = 'other-1',
  String content = 'Shared reel: Sea View 3BHK',
  String createdAt = '2026-01-01T10:00:00Z',
}) {
  return ChatMessage.fromSupabase({
    'id': id,
    'sender_id': senderId,
    'content': content,
    'message_type': 'reel_share',
    'reel_id': reelId,
    'created_at': createdAt,
  });
}

ChatMessage _textMessage({
  required String id,
  String senderId = 'other-1',
  String content = 'hello there',
  String createdAt = '2026-01-01T10:00:00Z',
}) {
  return ChatMessage.fromSupabase({
    'id': id,
    'sender_id': senderId,
    'content': content,
    'message_type': 'text',
    'created_at': createdAt,
  });
}

ChatMessage _propertyShareMessage({
  required String id,
  required String propertyId,
  String senderId = 'other-1',
  String createdAt = '2026-01-01T10:00:00Z',
}) {
  return ChatMessage.fromSupabase({
    'id': id,
    'sender_id': senderId,
    'content': 'Shared property: Sea View 3BHK',
    'message_type': 'property_share',
    'property_id': propertyId,
    'created_at': createdAt,
  });
}

/// Lets a test script exactly what each page fetch returns (including a
/// distinct older page for pagination) and records every batched
/// `fetchSharedReels` call so a test can assert "one query for N bubbles",
/// never one per bubble.
class _FakeMessagingService extends MessagingService {
  List<ChatMessage> initialPage = const [];
  List<ChatMessage> olderPage = const [];
  Map<String, SharedReelPreview> reelPreviews = const {};
  Map<String, SharedPropertyPreview> propertyPreviews = const {};

  int fetchSharedReelsCallCount = 0;
  final List<Set<String>> fetchSharedReelsCalls = [];
  String? lastSendReelShareSurface;

  @override
  Future<List<ChatMessage>> listMessages(
    String conversationId, {
    DateTime? before,
    DateTime? after,
  }) async => before == null ? initialPage : olderPage;

  @override
  Future<List<ChatMessage>> listChannelMessages(
    String channelId, {
    DateTime? before,
    DateTime? after,
  }) async => before == null ? initialPage : olderPage;

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
  ) async => {
    for (final id in propertyIds)
      if (propertyPreviews.containsKey(id)) id: propertyPreviews[id]!,
  };

  @override
  Future<Map<String, SharedReelPreview>> fetchSharedReels(
    Set<String> reelIds,
  ) async {
    fetchSharedReelsCallCount++;
    fetchSharedReelsCalls.add(reelIds);
    return {
      for (final id in reelIds)
        if (reelPreviews.containsKey(id)) id: reelPreviews[id]!,
    };
  }

  @override
  Future<void> sendReelShare({
    required String threadId,
    required String senderId,
    required String reelId,
    required String content,
    String surface = 'dm',
  }) async {
    lastSendReelShareSurface = surface;
  }

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
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
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

  group('MessagingService SELECT column contract', () {
    test('reel_id is present in the DM column set', () {
      expect(MessagingService.dmMessageColumnsForTest, contains('reel_id'));
    });

    test(
      'reel_id is present in the channel column set too — reel sharing works in channels',
      () {
        expect(MessagingService.messageColumnsForTest, contains('reel_id'));
      },
    );
  });

  group('ChatMessage parsing', () {
    test('a normal DM fetch row retains reel_id', () {
      final message = _reelShareMessage(id: 'm-1', reelId: 'reel-1');
      expect(message.reelId, 'reel-1');
      expect(message.isReelShare, isTrue);
    });

    test('a channel row with no reel_id key parses safely (reelId null)', () {
      final message = _textMessage(id: 'm-1');
      expect(message.reelId, isNull);
    });
  });

  group('ChatThreadProvider reel hydration', () {
    test('multiple reel-share messages resolve in one batched call', () async {
      final service = _FakeMessagingService()
        ..initialPage = [
          _reelShareMessage(id: 'm-1', reelId: 'reel-1'),
          _reelShareMessage(id: 'm-2', reelId: 'reel-2'),
          _reelShareMessage(id: 'm-3', reelId: 'reel-1'), // duplicate id
        ]
        ..reelPreviews = {
          'reel-1': const SharedReelPreview(id: 'reel-1', title: 'Reel One'),
          'reel-2': const SharedReelPreview(id: 'reel-2', title: 'Reel Two'),
        };

      final provider = ChatThreadProvider(
        kind: ChatThreadKind.conversation,
        threadId: 'thread-1',
        userId: 'me-1',
        participantUserId: 'other-1',
        service: service,
      );
      await provider.load();

      expect(service.fetchSharedReelsCallCount, 1);
      expect(service.fetchSharedReelsCalls.single, {'reel-1', 'reel-2'});
      expect(provider.sharedReelFor('reel-1')?.title, 'Reel One');
      expect(provider.sharedReelFor('reel-2')?.title, 'Reel Two');

      provider.dispose();
    });

    test(
      'a reel with no matching row resolves to null (unavailable), not an error',
      () async {
        final service = _FakeMessagingService()
          ..initialPage = [_reelShareMessage(id: 'm-1', reelId: 'reel-gone')];

        final provider = ChatThreadProvider(
          kind: ChatThreadKind.conversation,
          threadId: 'thread-1',
          userId: 'me-1',
          participantUserId: 'other-1',
          service: service,
        );
        await provider.load();

        expect(provider.sharedReelFor('reel-gone'), isNull);
        expect(provider.failed, isFalse);

        provider.dispose();
      },
    );

    test('loadMore hydrates a reel share on the older page', () async {
      // Enough filler messages on the first page that the provider reports
      // "more older messages available" for real
      // (`MessagingService.messagePageSize`), rather than reaching into
      // private state to force it.
      final service = _FakeMessagingService()
        ..initialPage = List.generate(
          MessagingService.messagePageSize,
          (i) => _textMessage(
            id: 'm-recent-$i',
            createdAt: '2026-01-02T10:${i.toString().padLeft(2, '0')}:00Z',
          ),
        )
        ..olderPage = [
          _reelShareMessage(
            id: 'm-old-1',
            reelId: 'reel-old',
            createdAt: '2026-01-01T09:00:00Z',
          ),
        ]
        ..reelPreviews = {
          'reel-old': const SharedReelPreview(
            id: 'reel-old',
            title: 'Old Reel',
          ),
        };

      final provider = ChatThreadProvider(
        kind: ChatThreadKind.conversation,
        threadId: 'thread-1',
        userId: 'me-1',
        participantUserId: 'other-1',
        service: service,
      );
      await provider.load();
      expect(provider.hasMoreOlder, isTrue);
      expect(provider.sharedReelFor('reel-old'), isNull);

      await provider.loadMore();

      expect(provider.sharedReelFor('reel-old')?.title, 'Old Reel');

      provider.dispose();
    });

    test('refresh() hydrates a newly-arrived reel share — the same path a '
        'realtime fallback merge uses when a payload cannot be applied '
        'directly (no live Realtime socket is available under `flutter test`, '
        'so this exercises the shared hydration call the fallback also goes '
        'through, not the socket itself)', () async {
      final service = _FakeMessagingService()
        ..initialPage = [_textMessage(id: 'm-1')]
        ..reelPreviews = {
          'reel-new': const SharedReelPreview(
            id: 'reel-new',
            title: 'New Reel',
          ),
        };

      final provider = ChatThreadProvider(
        kind: ChatThreadKind.conversation,
        threadId: 'thread-1',
        userId: 'me-1',
        participantUserId: 'other-1',
        service: service,
      );
      await provider.load();
      expect(provider.sharedReelFor('reel-new'), isNull);

      service.initialPage = [
        ...service.initialPage,
        _reelShareMessage(id: 'm-2', reelId: 'reel-new'),
      ];
      await provider.refresh();

      expect(provider.sharedReelFor('reel-new')?.title, 'New Reel');

      provider.dispose();
    });
  });

  group('Channel reel sharing', () {
    test(
      'a channel thread with only text messages never calls fetchSharedReels',
      () async {
        final service = _FakeMessagingService()
          ..initialPage = [_textMessage(id: 'c-1')];

        final provider = ChatThreadProvider(
          kind: ChatThreadKind.channel,
          threadId: 'channel-1',
          userId: 'me-1',
          service: service,
        );
        await provider.load();

        expect(service.fetchSharedReelsCallCount, 0);
        expect(provider.messages, hasLength(1));

        provider.dispose();
      },
    );

    test('a channel thread with a reel share hydrates it via fetchSharedReels, '
        'same as a DM', () async {
      final service = _FakeMessagingService()
        ..initialPage = [_reelShareMessage(id: 'c-1', reelId: 'reel-1')]
        ..reelPreviews = {
          'reel-1': const SharedReelPreview(id: 'reel-1', title: 'Reel One'),
        };

      final provider = ChatThreadProvider(
        kind: ChatThreadKind.channel,
        threadId: 'channel-1',
        userId: 'me-1',
        service: service,
      );
      await provider.load();

      expect(service.fetchSharedReelsCallCount, 1);
      expect(provider.sharedReelFor('reel-1')?.title, 'Reel One');

      provider.dispose();
    });

    test('shareReelFromPicker sends with surface "channel"', () async {
      final service = _FakeMessagingService();
      final provider = ChatThreadProvider(
        kind: ChatThreadKind.channel,
        threadId: 'channel-1',
        userId: 'me-1',
        service: service,
      );
      await provider.load();

      final error = await provider.shareReelFromPicker(
        const SharedReelPreview(id: 'reel-9', title: 'Sea View 3BHK'),
      );

      expect(error, isNull);
      expect(service.lastSendReelShareSurface, 'channel');

      provider.dispose();
    });
  });

  group('ChatBubble rendering', () {
    Widget wrapBubble(Widget bubble, {NavigatorObserver? observer}) {
      return MaterialApp(
        navigatorObservers: observer == null ? const [] : [observer],
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route:${settings.name}')),
        ),
        home: Scaffold(body: bubble),
      );
    }

    testWidgets('renders a reel preview card for a resolved reel share', (
      tester,
    ) async {
      final message = _reelShareMessage(
        id: 'm-1',
        reelId: 'reel-1',
        content: '',
      );
      await tester.pumpWidget(
        wrapBubble(
          ChatBubble(
            message: message,
            isMine: false,
            currentUserId: 'me-1',
            sharedReel: const SharedReelPreview(
              id: 'reel-1',
              title: 'Sea View 3BHK',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sea View 3BHK'), findsOneWidget);
      expect(find.text('Shared a reel'), findsNothing);
      expect(find.text('Reel unavailable'), findsNothing);
    });

    testWidgets(
      'tapping a valid reel card opens the existing Reels route with the correct id',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final message = _reelShareMessage(
          id: 'm-1',
          reelId: 'reel-42',
          content: '',
        );
        await tester.pumpWidget(
          wrapBubble(
            ChatBubble(
              message: message,
              isMine: false,
              currentUserId: 'me-1',
              sharedReel: const SharedReelPreview(
                id: 'reel-42',
                title: 'Sea View 3BHK',
              ),
            ),
            observer: observer,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sea View 3BHK'));
        await tester.pumpAndSettle();

        expect(observer.lastPushed?.settings.name, AppConstants.reelsScreen);
        expect(
          (observer.lastPushed?.settings.arguments as Map)['reelId'],
          'reel-42',
        );
      },
    );

    testWidgets(
      'a missing/deleted reel renders a graceful unavailable state, not a crash',
      (tester) async {
        final message = _reelShareMessage(
          id: 'm-1',
          reelId: 'reel-gone',
          content: '',
        );
        await tester.pumpWidget(
          wrapBubble(
            ChatBubble(
              message: message,
              isMine: false,
              currentUserId: 'me-1',
              sharedReel: null, // batched lookup found nothing
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reel unavailable'), findsOneWidget);
        expect(find.textContaining('reel-gone'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('existing property share still renders correctly', (
      tester,
    ) async {
      final message = _propertyShareMessage(id: 'm-1', propertyId: 'p-1');
      await tester.pumpWidget(
        wrapBubble(
          ChatBubble(
            message: message,
            isMine: false,
            currentUserId: 'me-1',
            sharedProperty: const SharedPropertyPreview(
              id: 'p-1',
              title: 'Sea View 3BHK',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sea View 3BHK'), findsOneWidget);
      expect(find.text('Reel unavailable'), findsNothing);
    });

    testWidgets('existing text message still renders correctly', (
      tester,
    ) async {
      final message = _textMessage(id: 'm-1', content: 'hello there');
      await tester.pumpWidget(
        wrapBubble(
          ChatBubble(message: message, isMine: false, currentUserId: 'me-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hello there'), findsOneWidget);
    });

    testWidgets(
      'an image message still renders via the media branch, not the reel/property branch',
      (tester) async {
        final message = ChatMessage.fromSupabase({
          'id': 'm-1',
          'sender_id': 'other-1',
          'content': '',
          'message_type': 'image',
          'media_urls': ['some/path.jpg'],
          // 'pending' avoids ChatMediaView issuing a real signed-URL
          // network call, which isn't available under `flutter test`.
          'media_status': 'pending',
          'created_at': '2026-01-01T10:00:00Z',
        });
        await tester.pumpWidget(
          wrapBubble(
            ChatBubble(message: message, isMine: false, currentUserId: 'me-1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reel unavailable'), findsNothing);
        expect(find.text('Shared a reel'), findsNothing);
        expect(find.text('Property unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
