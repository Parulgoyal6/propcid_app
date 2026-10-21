// Article editor — debounced autosave.
//
// The web form autosaves 30s after a meaningful change; Flutter previously
// had only a manual "Save Draft" button. This pins the debounce itself
// (restart-on-change, fires once per settled burst), the safety gates (never
// on an empty title/body, never finalizes, never duplicates a row, never
// overlaps a manual save), that autosave still runs for an already-approved
// article (the editor never locks editing — only an explicit submit demotes
// approval status), and that a failed autosave leaves the user's typed
// content untouched.
//
// The 30-second production delay is overridden via
// `ArticleEditorProvider`'s `@visibleForTesting autosaveDelay` constructor
// param — every test below uses a few milliseconds instead of waiting for
// real time to pass.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/article_model.dart';
import 'package:propcid_app/providers/article_editor_provider.dart';
import 'package:propcid_app/services/article_service.dart';

const _shortDelay = Duration(milliseconds: 20);

ArticleModel _article({
  String id = 'a-1',
  String approvalStatus = 'pending',
  String slug = 'existing-slug',
}) {
  return ArticleModel.fromSupabase({
    'id': id,
    'title': 'Existing title',
    'slug': slug,
    'content': '<p>Existing body</p>',
    'content_html': '<p>Existing body</p>',
    'excerpt': 'Existing brief',
    'brief': 'Existing brief',
    'category': 'news',
    'tags': <String>[],
    'featured_image_url': null,
    'author_name': 'Author',
    'read_time': 5,
    'approval_status': approvalStatus,
    'status': 'draft',
    'submitted_by': 'u-1',
    'submitted_by_type': 'influencer',
    'content_type': 'article',
    'created_at': DateTime.now().toIso8601String(),
  });
}

class _FakeArticleService extends ArticleService {
  _FakeArticleService({this.existing, this.shouldFail = false});

  final ArticleModel? existing;
  bool shouldFail;

  int createCalls = 0;
  int updateCalls = 0;
  final List<bool> createSubmitForReview = [];
  final List<bool> updateSubmitForReview = [];
  String createdId = 'new-id';

  @override
  Future<ArticleModel> getById(String id) async {
    return existing ?? _article(id: id);
  }

  @override
  Future<String> create({
    required String title,
    required String slug,
    required String contentHtml,
    required String brief,
    required String? category,
    required List<String> tags,
    required String? imageUrl,
    required String authorName,
    required String? authorImageUrl,
    required int readTime,
    required String userId,
    required String? userType,
    required bool isAdmin,
    required bool submitForReview,
  }) async {
    createCalls++;
    createSubmitForReview.add(submitForReview);
    if (shouldFail) throw StateError('forced failure');
    return createdId;
  }

  @override
  Future<void> update({
    required String id,
    required String title,
    required String slug,
    required String contentHtml,
    required String brief,
    required String? category,
    required List<String> tags,
    required String? imageUrl,
    required String authorName,
    required String? authorImageUrl,
    required int readTime,
    required String userId,
    required String? userType,
    required bool isAdmin,
    required bool submitForReview,
  }) async {
    updateCalls++;
    updateSubmitForReview.add(submitForReview);
    if (shouldFail) throw StateError('forced failure');
  }
}

ArticleEditorProvider _newProvider(
  _FakeArticleService service, {
  String? articleId,
  Duration delay = _shortDelay,
}) {
  return ArticleEditorProvider(
    articleId: articleId,
    userId: 'u-1',
    userType: 'influencer',
    authorName: 'Author',
    authorImageUrl: null,
    service: service,
    autosaveDelay: delay,
  );
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

  group('debounce', () {
    test(
      'fires once after the delay settles, not once per keystroke',
      () async {
        final service = _FakeArticleService();
        final provider = _newProvider(service);
        addTearDown(provider.dispose);

        provider.setTitle('T');
        provider.setTitle('Ti');
        provider.setTitle('Tit');
        provider.setBody('<p>content</p>', 'content');

        // Still well inside the debounce window — nothing has fired yet.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(service.createCalls, 0);

        await Future<void>.delayed(
          _shortDelay + const Duration(milliseconds: 20),
        );
        expect(service.createCalls, 1);
      },
    );

    test('a change restarts the timer', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('T');
      await Future<void>.delayed(const Duration(milliseconds: 12));
      provider.setBody('<p>content</p>', 'content'); // restarts the timer
      await Future<void>.delayed(const Duration(milliseconds: 12));

      // 24ms of wall time have passed but the timer was restarted at 12ms,
      // so a 20ms delay has not yet elapsed since the restart.
      expect(service.createCalls, 0);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.createCalls, 1);
    });
  });

  group('safety gates', () {
    test('never autosaves with an empty title or body', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('Only a title');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.createCalls, 0);
      expect(service.updateCalls, 0);
    });

    test('never finalizes — always submitForReview: false', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('T');
      provider.setBody('<p>content</p>', 'content');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.createSubmitForReview, [false]);
    });

    test('still autosaves an already-approved article — matching the portal, '
        'which never locks editing; only an explicit submit demotes approval '
        'status, never autosave', () async {
      final service = _FakeArticleService(
        existing: _article(approvalStatus: 'approved'),
      );
      final provider = _newProvider(service, articleId: 'a-1');
      await provider.load();
      addTearDown(provider.dispose);

      provider.setBrief('an edit to a live article');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.updateCalls, 1);
      expect(service.updateSubmitForReview, [false]);
    });

    test('never overlaps a manual save already in flight', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('T');
      provider.setBody('<p>content</p>', 'content');
      provider.setBrief('A brief.'); // required for submit() to pass validation
      provider.setCategory('news'); // required for submit() to pass validation

      // Start a manual submit-for-review and let the autosave timer elapse
      // while it's still in flight (the fake service's Future resolves on
      // the next microtask, so there's a real window where `_saving` is
      // true and the timer can fire inside it).
      final submitFuture = provider.submit();
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );
      await submitFuture;

      // Only the manual submit actually persisted; the autosave that tried
      // to fire while `_saving` was true was a no-op.
      expect(service.createCalls, 1);
      expect(service.createSubmitForReview, [true]);
    });
  });

  group('create-vs-update / no duplicates', () {
    test('creates a draft only once, then updates the same id', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('T');
      provider.setBody('<p>content</p>', 'content');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );
      expect(service.createCalls, 1);
      expect(provider.persistedId, service.createdId);

      provider.setTitle('T2');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.createCalls, 1, reason: 'no duplicate row');
      expect(
        service.updateCalls,
        1,
        reason: 'second autosave updates in place',
      );
    });

    test('reuses the existing article id when editing', () async {
      final service = _FakeArticleService(existing: _article());
      final provider = _newProvider(service, articleId: 'a-1');
      await provider.load();
      addTearDown(provider.dispose);

      provider.setBrief('An updated brief');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.createCalls, 0);
      expect(service.updateCalls, 1);
    });
  });

  group('lifecycle', () {
    test('dispose cancels the pending timer', () async {
      final service = _FakeArticleService();
      final provider = _newProvider(service);

      provider.setTitle('T');
      provider.setBody('<p>content</p>', 'content');
      provider.dispose();

      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 30),
      );

      expect(service.createCalls, 0);
    });

    test('a failed autosave leaves the typed content in place', () async {
      final service = _FakeArticleService(shouldFail: true);
      final provider = _newProvider(service);
      addTearDown(provider.dispose);

      provider.setTitle('My title');
      provider.setBody('<p>my body</p>', 'my body');
      await Future<void>.delayed(
        _shortDelay + const Duration(milliseconds: 20),
      );

      expect(service.createCalls, 1);
      expect(provider.autosaveStatus, AutosaveStatus.failed);
      expect(provider.title, 'My title');
      expect(provider.bodyPlainText, 'my body');
    });
  });
}
