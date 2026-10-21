// Feature 2 — article featured-image upload.
//
// `ArticleMediaService` mirrors `ProfileMediaService`'s own self-contained
// approach: the path/MIME conventions are duplicated rather than shared, so
// this file pins them the same way `profile_media_service_test.dart` pins
// the profile feature's — a wrong bucket or a path that omits the owner id
// fails silently against the storage policy, and a missing content type
// makes the uploaded image download instead of render.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/services/article_media_service.dart';

void main() {
  const ownerId = 'a1b2c3d4-0000-0000-0000-000000000000';
  const entityId = 'article-1';
  const uuid = '11111111-2222-3333-4444-555555555555';

  group('bucket', () {
    test('is the portal\'s public media-library, not a private one', () {
      // imagePresets.ts's "blog" preset: defaultBucket "media-library",
      // private: false.
      expect(ArticleMediaService.bucket, 'media-library');
    });
  });

  group('path', () {
    test('starts with the owner id, as the storage policy requires', () {
      final p = ArticleMediaService.path(ownerId, entityId, 'jpg', uuid);
      expect(p.split('/').first, ownerId);
    });

    test('mirrors the portal\'s {owner}/blogs/{entity}/... template', () {
      final p = ArticleMediaService.path(ownerId, entityId, 'jpg', uuid);
      expect(p, '$ownerId/blogs/$entityId/$uuid-original.jpg');
    });

    test('a new article\'s draft id groups its images the same way', () {
      // Before the article is saved, `entityId` is a per-session draft id
      // rather than a real article id — the path shape doesn't care which.
      const draftId = 'draft-9f8e7d6c';
      final p = ArticleMediaService.path(ownerId, draftId, 'png', uuid);
      expect(p, '$ownerId/blogs/$draftId/$uuid-original.png');
    });

    test('no path contains a double slash or a trailing dot', () {
      final p = ArticleMediaService.path(ownerId, entityId, 'jpg', uuid);
      expect(p.contains('//'), isFalse);
      expect(p.endsWith('.'), isFalse);
    });
  });

  group('content path', () {
    test('starts with the owner id, as the storage policy requires', () {
      final p = ArticleMediaService.contentPath(
        ownerId,
        entityId,
        'jpg',
        uuid,
      );
      expect(p.split('/').first, ownerId);
    });

    test('adds a content/ segment so it never collides with the featured '
        'image path', () {
      final featured = ArticleMediaService.path(ownerId, entityId, 'jpg', uuid);
      final content = ArticleMediaService.contentPath(
        ownerId,
        entityId,
        'jpg',
        uuid,
      );
      expect(content, '$ownerId/blogs/$entityId/content/$uuid-original.jpg');
      expect(content, isNot(featured));
    });

    test('no path contains a double slash or a trailing dot', () {
      final p = ArticleMediaService.contentPath(
        ownerId,
        entityId,
        'jpg',
        uuid,
      );
      expect(p.contains('//'), isFalse);
      expect(p.endsWith('.'), isFalse);
    });
  });

  group('extension parsing', () {
    test('lowercases and takes the last segment', () {
      expect(ArticleMediaService.extensionOf('cover.JPG'), 'jpg');
      expect(ArticleMediaService.extensionOf('a.b.png'), 'png');
    });

    test('defaults to jpg when there is no usable extension', () {
      expect(ArticleMediaService.extensionOf('noextension'), 'jpg');
      expect(ArticleMediaService.extensionOf('trailingdot.'), 'jpg');
      expect(ArticleMediaService.extensionOf(''), 'jpg');
    });
  });

  group('MIME mapping', () {
    test('covers every format image_picker can return', () {
      expect(ArticleMediaService.mimeFromExtension('jpg'), 'image/jpeg');
      expect(ArticleMediaService.mimeFromExtension('jpeg'), 'image/jpeg');
      expect(ArticleMediaService.mimeFromExtension('png'), 'image/png');
      expect(ArticleMediaService.mimeFromExtension('webp'), 'image/webp');
      expect(ArticleMediaService.mimeFromExtension('heic'), 'image/heic');
      expect(ArticleMediaService.mimeFromExtension('gif'), 'image/gif');
    });

    test('is case-insensitive', () {
      expect(ArticleMediaService.mimeFromExtension('PNG'), 'image/png');
    });

    test('an unknown extension falls back to octet-stream', () {
      expect(
        ArticleMediaService.mimeFromExtension('xyz'),
        'application/octet-stream',
      );
    });

    test('no PDF branch — a featured image can only be a photo', () {
      expect(
        ArticleMediaService.mimeFromExtension('pdf'),
        'application/octet-stream',
      );
    });
  });

  group('sizing matches the portal\'s blog preset', () {
    test('1920px ceiling', () {
      expect(ArticleMediaService.maxDimension, 1920);
    });

    test('quality is a sane JPEG value close to the portal\'s 0.83', () {
      expect(ArticleMediaService.jpegQuality, inInclusiveRange(70, 95));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// NOT COVERED HERE
//
// The upload call itself needs a live bucket and a signed-in session, neither
// available in this environment — the same boundary
// `profile_media_service_test.dart` draws. What is asserted above is every
// value that would make such an upload fail or silently misbehave.
// `ArticleEditorProvider`'s own tests cover the picking/uploading *flow*
// (cancellation, failure, retry, entityId selection) against a fake service.
