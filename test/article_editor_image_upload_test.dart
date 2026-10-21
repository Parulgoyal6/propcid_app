// Feature 2 — article featured-image device upload.
//
// `ArticleMediaService`'s own pure logic (bucket/path/MIME) is pinned in
// `article_media_service_test.dart`. This file pins the provider flow around
// it: `ArticleEditorProvider.pickAndUploadImage` picks, uploads, and writes
// the result through the existing `setImageUrl` (so it participates in
// autosave exactly like a pasted URL), a cancellation is a silent no-op, a
// failure leaves the previous image in place and returns a message,
// `removeImage` clears it, and the upload's `entityId` is the article's own
// id once persisted or a stable per-session draft id before that — mirroring
// the portal's `draftEntityIdRef`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/article_model.dart';
import 'package:propcid_app/providers/article_editor_provider.dart';
import 'package:propcid_app/services/article_media_service.dart';
import 'package:propcid_app/services/article_service.dart';

ArticleModel _article({
  String id = 'a-1',
  String approvalStatus = 'pending',
  String? featuredImageUrl,
}) {
  return ArticleModel.fromSupabase({
    'id': id,
    'title': 'Existing title',
    'slug': 'existing-slug',
    'content': '<p>Existing body</p>',
    'content_html': '<p>Existing body</p>',
    'excerpt': 'Existing brief',
    'brief': 'Existing brief',
    'category': 'news',
    'tags': <String>[],
    'featured_image_url': featuredImageUrl,
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
  _FakeArticleService({this.existing});
  final ArticleModel? existing;

  @override
  Future<ArticleModel> getById(String id) async => existing ?? _article(id: id);
}

class _FakeArticleMediaService extends ArticleMediaService {
  Object? throwOnPick;
  Object? throwOnUpload;
  bool cancelPick = false;
  String uploadResult = 'https://cdn.example.com/media-library/large.jpg';

  int pickCalls = 0;
  int uploadCalls = 0;
  int contentUploadCalls = 0;
  final List<String> uploadEntityIds = [];
  final List<String> contentUploadEntityIds = [];

  @override
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    pickCalls++;
    final toThrow = throwOnPick;
    if (toThrow != null) throw toThrow;
    if (cancelPick) return null;
    return XFile.fromData(
      Uint8List.fromList(const [1, 2, 3]),
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
    );
  }

  @override
  Future<String> uploadImage({
    required String ownerId,
    required String entityId,
    required XFile file,
  }) async {
    uploadCalls++;
    uploadEntityIds.add(entityId);
    final toThrow = throwOnUpload;
    if (toThrow != null) throw toThrow;
    return uploadResult;
  }

  @override
  Future<String> uploadContentImage({
    required String ownerId,
    required String entityId,
    required XFile file,
  }) async {
    contentUploadCalls++;
    contentUploadEntityIds.add(entityId);
    final toThrow = throwOnUpload;
    if (toThrow != null) throw toThrow;
    return uploadResult;
  }
}

ArticleEditorProvider _newProvider(
  _FakeArticleService service,
  _FakeArticleMediaService media, {
  String? articleId,
}) {
  return ArticleEditorProvider(
    articleId: articleId,
    userId: 'u-1',
    userType: 'influencer',
    authorName: 'Author',
    authorImageUrl: null,
    service: service,
    mediaService: media,
    // Long enough that no autosave fires mid-test and confuses call counts.
    autosaveDelay: const Duration(seconds: 30),
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

  test('a successful upload sets imageUrl via the existing setter', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(_FakeArticleService(), media);
    addTearDown(provider.dispose);

    final error = await provider.pickAndUploadImage();

    expect(error, isNull);
    expect(provider.imageUrl, media.uploadResult);
    expect(provider.imageUploading, isFalse);
  });

  test('cancelling the picker is a no-op, not an error', () async {
    final media = _FakeArticleMediaService()..cancelPick = true;
    final provider = _newProvider(_FakeArticleService(), media);
    addTearDown(provider.dispose);

    final error = await provider.pickAndUploadImage();

    expect(error, isNull);
    expect(provider.imageUrl, isEmpty);
    expect(media.uploadCalls, 0, reason: 'a cancelled pick never uploads');
  });

  test(
    'a pick failure returns a message and leaves the image untouched',
    () async {
      final media = _FakeArticleMediaService()
        ..throwOnPick = StateError('denied');
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);
      provider.setImageUrl('https://old.example.com/a.jpg');

      final error = await provider.pickAndUploadImage();

      expect(error, isNotNull);
      expect(provider.imageUrl, 'https://old.example.com/a.jpg');
    },
  );

  test(
    'an upload failure returns a message and leaves the image untouched',
    () async {
      final media = _FakeArticleMediaService()
        ..throwOnUpload = StateError('network blip');
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);
      provider.setImageUrl('https://old.example.com/a.jpg');

      final error = await provider.pickAndUploadImage();

      expect(error, isNotNull);
      expect(provider.imageUrl, 'https://old.example.com/a.jpg');
    },
  );

  test('retrying after a failure can still succeed', () async {
    final media = _FakeArticleMediaService()
      ..throwOnUpload = StateError('network blip');
    final provider = _newProvider(_FakeArticleService(), media);
    addTearDown(provider.dispose);

    expect(await provider.pickAndUploadImage(), isNotNull);

    media.throwOnUpload = null;
    final secondAttempt = await provider.pickAndUploadImage();

    expect(secondAttempt, isNull);
    expect(provider.imageUrl, media.uploadResult);
  });

  test('a new pick replaces the previous image', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(_FakeArticleService(), media);
    addTearDown(provider.dispose);

    await provider.pickAndUploadImage();
    final first = provider.imageUrl;

    media.uploadResult = 'https://cdn.example.com/media-library/second.jpg';
    await provider.pickAndUploadImage();

    expect(provider.imageUrl, isNot(first));
    expect(provider.imageUrl, media.uploadResult);
    expect(media.uploadCalls, 2);
  });

  test('removeImage clears the featured image', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(_FakeArticleService(), media);
    addTearDown(provider.dispose);
    await provider.pickAndUploadImage();
    expect(provider.imageUrl, isNotEmpty);

    provider.removeImage();

    expect(provider.imageUrl, isEmpty);
  });

  test(
    'loading an existing article preserves its image until changed',
    () async {
      final media = _FakeArticleMediaService();
      final provider = _newProvider(
        _FakeArticleService(
          existing: _article(
            featuredImageUrl: 'https://legacy.example.com/x.png',
          ),
        ),
        media,
        articleId: 'a-1',
      );
      addTearDown(provider.dispose);

      await provider.load();

      expect(provider.imageUrl, 'https://legacy.example.com/x.png');
      expect(
        media.uploadCalls,
        0,
        reason: 'loading must never trigger an upload',
      );
    },
  );

  test(
    'a new (unsaved) article uploads under a stable draft entity id',
    () async {
      final media = _FakeArticleMediaService();
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);

      await provider.pickAndUploadImage();
      await provider.pickAndUploadImage();

      expect(media.uploadEntityIds, hasLength(2));
      expect(
        media.uploadEntityIds[0],
        media.uploadEntityIds[1],
        reason: 'both uploads belong to the same not-yet-saved article',
      );
    },
  );

  test('once the article is persisted, uploads use its real id', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(
      _FakeArticleService(existing: _article(id: 'real-article-id')),
      media,
      articleId: 'real-article-id',
    );
    addTearDown(provider.dispose);
    await provider.load();

    await provider.pickAndUploadImage();

    expect(media.uploadEntityIds.single, 'real-article-id');
  });

  test('still picks and uploads for an already-approved article — the editor '
      'never locks editing, matching the portal', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(
      _FakeArticleService(existing: _article(approvalStatus: 'approved')),
      media,
      articleId: 'a-1',
    );
    addTearDown(provider.dispose);
    await provider.load();

    final error = await provider.pickAndUploadImage();

    expect(error, isNull);
    expect(media.pickCalls, 1);
    expect(provider.imageUrl, media.uploadResult);
  });

  test('dispose during an in-flight upload does not throw or notify', () async {
    final media = _FakeArticleMediaService();
    final provider = _newProvider(_FakeArticleService(), media);

    final future = provider.pickAndUploadImage();
    provider.dispose();

    // Must complete cleanly — a notifyListeners after dispose throws in
    // debug mode, which would surface as a failed/errored test here.
    await future;
  });

  group('pickAndUploadContentImage (inline body images)', () {
    test('returns the uploaded public URL, via uploadContentImage', () async {
      final media = _FakeArticleMediaService();
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);

      final url = await provider.pickAndUploadContentImage();

      expect(url, media.uploadResult);
      expect(media.contentUploadCalls, 1);
      expect(
        media.uploadCalls,
        0,
        reason: 'a body image must not go through the featured-image path',
      );
    });

    test('cancelling the picker is a no-op, not an error', () async {
      final media = _FakeArticleMediaService()..cancelPick = true;
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);

      final url = await provider.pickAndUploadContentImage();

      expect(url, isNull);
      expect(media.contentUploadCalls, 0);
    });

    test('an upload failure propagates so the toolbar can show it', () async {
      final media = _FakeArticleMediaService()
        ..throwOnUpload = StateError('network blip');
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);

      await expectLater(
        provider.pickAndUploadContentImage(),
        throwsA(isA<StateError>()),
      );
    });

    test('still picks and uploads for an already-approved article — the '
        'editor never locks editing, matching the portal', () async {
      final media = _FakeArticleMediaService();
      final provider = _newProvider(
        _FakeArticleService(existing: _article(approvalStatus: 'approved')),
        media,
        articleId: 'a-1',
      );
      addTearDown(provider.dispose);
      await provider.load();

      final url = await provider.pickAndUploadContentImage();

      expect(url, media.uploadResult);
      expect(media.contentUploadCalls, 1);
    });

    test('uses the same entityId convention as the featured image', () async {
      final media = _FakeArticleMediaService();
      final provider = _newProvider(_FakeArticleService(), media);
      addTearDown(provider.dispose);

      await provider.pickAndUploadImage();
      await provider.pickAndUploadContentImage();

      expect(media.contentUploadEntityIds.single, media.uploadEntityIds.single);
    });
  });
}
