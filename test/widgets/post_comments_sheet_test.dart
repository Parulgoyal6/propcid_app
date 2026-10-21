// Focused tests for PostCommentsSheet — extracted from a Feed-only
// `_FeedCommentsSheet` specifically so the project detail page could reuse
// it (see project_detail_screen.dart's header comment). Drives it with a
// fake CommentService; no real Supabase network call is exercised.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/reel_comment.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/services/comment_service.dart';
import 'package:propcid_app/widgets/post_comments_sheet.dart';

class _FakeAuth extends AuthProvider {
  _FakeAuth({this.id});
  final String? id;

  @override
  String? get userId => id;

  @override
  bool get isLoggedIn => id != null;
}

class _FakeCommentService implements CommentService {
  List<ReelComment> comments = const [];
  Object? fetchError;
  Object? submitError;
  Object? deleteError;
  final List<String> deletedIds = [];

  @override
  Future<List<ReelComment>> fetchComments(
    String postId,
    String postType,
  ) async {
    if (fetchError != null) throw fetchError!;
    return comments;
  }

  @override
  Future<ReelComment> submitComment({
    required String postId,
    required String postType,
    required String userId,
    required String content,
  }) async {
    if (submitError != null) throw submitError!;
    return ReelComment(
      id: 'new-${comments.length}',
      userId: userId,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {
    if (deleteError != null) throw deleteError!;
    deletedIds.add(commentId);
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required _FakeCommentService service,
  String? userId = 'me-1',
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuth(id: userId),
      child: MaterialApp(
        home: Scaffold(
          body: PostCommentsSheet(
            postId: 'post-1',
            postType: 'project',
            service: service,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  testWidgets('loads and shows existing comments', (tester) async {
    final service = _FakeCommentService()
      ..comments = [
        ReelComment(
          id: 'c-1',
          userId: 'other-user',
          content: 'Looks great!',
          createdAt: DateTime(2026, 1, 1),
          authorName: 'Asha',
        ),
      ];

    await _pumpSheet(tester, service: service);

    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Looks great!'), findsOneWidget);
  });

  testWidgets('an empty thread shows the empty state, not a spinner', (
    tester,
  ) async {
    await _pumpSheet(tester, service: _FakeCommentService());

    expect(find.text('No comments yet. Be the first!'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final service = _FakeCommentService()..fetchError = Exception('offline');
    await _pumpSheet(tester, service: service);

    expect(find.text('Could not load comments'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    service.fetchError = null;
    service.comments = [
      ReelComment(
        id: 'c-1',
        userId: 'u-1',
        content: 'Back online',
        createdAt: DateTime.now(),
      ),
    ];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Back online'), findsOneWidget);
  });

  testWidgets('submitting adds the new comment to the top of the list', (
    tester,
  ) async {
    final service = _FakeCommentService();
    await _pumpSheet(tester, service: service);
    expect(find.text('No comments yet. Be the first!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'First comment');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('First comment'), findsOneWidget);
    // The input clears after a successful post.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a signed-out viewer is told to sign in, and nothing is posted', (
    tester,
  ) async {
    final service = _FakeCommentService();
    await _pumpSheet(tester, service: service, userId: null);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(find.text('Sign in to comment'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget); // never cleared/submitted
  });

  testWidgets(
    'only the comment author sees a delete button',
    (tester) async {
      final service = _FakeCommentService()
        ..comments = [
          ReelComment(
            id: 'mine',
            userId: 'me-1',
            content: 'My comment',
            createdAt: DateTime.now(),
          ),
          ReelComment(
            id: 'theirs',
            userId: 'other-user',
            content: 'Their comment',
            createdAt: DateTime.now(),
          ),
        ];
      await _pumpSheet(tester, service: service, userId: 'me-1');

      expect(find.byTooltip('Delete comment'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting asks for confirmation, then removes the row optimistically',
    (tester) async {
      final service = _FakeCommentService()
        ..comments = [
          ReelComment(
            id: 'mine',
            userId: 'me-1',
            content: 'Delete me',
            createdAt: DateTime.now(),
          ),
        ];
      await _pumpSheet(tester, service: service, userId: 'me-1');
      expect(find.text('Delete me'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete comment'));
      await tester.pumpAndSettle();
      expect(find.text('Delete comment?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete me'), findsNothing);
      expect(service.deletedIds, ['mine']);

      // A successful delete shows `showOverlayToast`, which schedules its
      // own auto-dismiss timer — drained here so it isn't still pending
      // when the test ends (flutter_test asserts against that).
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('a failed delete restores the comment', (tester) async {
    final service = _FakeCommentService()
      ..comments = [
        ReelComment(
          id: 'mine',
          userId: 'me-1',
          content: 'Stays visible',
          createdAt: DateTime.now(),
        ),
      ]
      ..deleteError = 'You cannot delete this.';
    await _pumpSheet(tester, service: service, userId: 'me-1');

    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Stays visible'), findsOneWidget);
  });
}
