// services/article_media_service.dart
//
// Picks and uploads an article's featured image.
//
// Self-contained, mirroring `ProfileMediaService`'s own approach (path/MIME
// mirrored rather than imported, no shared upload helper) — the codebase has
// no shared upload utility to extend without widening an unrelated service's
// surface.
//
// PORTAL CONTRACT — ArticleWriteForm.tsx's `<ImageUploader preset="blog" />`
// resolves (`imagePresets.ts`'s `blog` preset, `imageUploader.ts`) to the
// public `media-library` bucket at
// `{ownerId}/blogs/{entityId}/{uuid}-{variant}.{ext}`, storing a public URL.
// The portal generates three resized variants (large/medium/thumbnail)
// client-side; this service produces the one image the app actually needs
// (downscaled once via `image_picker`, the same approach
// `ProfileMediaService` already uses for avatar/cover), which is what ends
// up in `featured_image_url`/`cover_image` either way — the DB column holds
// a single URL string, not a variant set.
//
// STORAGE POLICIES — no backend change needed. `media-library` already
// exists and is public (used by the portal today); this service only
// reuses it.
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/public_media_url.dart';

class ArticleMediaService {
  ArticleMediaService({ImagePicker? picker, SupabaseClient? client})
    : _picker = picker ?? ImagePicker(),
      _supabase = client ?? Supabase.instance.client;

  final ImagePicker _picker;
  final SupabaseClient _supabase;
  static const _uuid = Uuid();

  /// `imagePresets.ts`'s `blog` preset — `defaultBucket: "media-library"`.
  static const String bucket = 'media-library';

  /// The portal's own `blog` preset ceiling (`maxDimension: 1920`).
  static const double maxDimension = 1920;

  /// Close to the portal's `quality: 0.83`; kept as an integer percentage to
  /// match `image_picker`'s own `imageQuality` scale and the rest of this
  /// app's upload code.
  static const int jpegQuality = 83;

  /// Opens the gallery or camera and returns the chosen image, already
  /// downscaled. Returns null when the user cancels — not an error.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: jpegQuality,
      );
    } catch (e) {
      debugPrint('ArticleMediaService.pickImage failed: $e');
      return null;
    }
  }

  /// `{ownerId}/blogs/{entityId}/{uuid}-original.{ext}` — mirrors the
  /// portal's `ENTITY_PATH_PREFIX.blog` (`"blogs/{id}/"`) and its
  /// `{ownerId}/{prefix}{uuid}-{variant}.{ext}` template, naming the single
  /// file this service produces `original` since there is only one.
  @visibleForTesting
  static String path(
    String ownerId,
    String entityId,
    String ext,
    String uuid,
  ) => '$ownerId/blogs/$entityId/$uuid-original.$ext';

  /// `{ownerId}/blogs/{entityId}/content/{uuid}-original.{ext}` — the same
  /// template as [path] with a `content/` segment, so an article's inline
  /// images can't collide with its single featured image.
  @visibleForTesting
  static String contentPath(
    String ownerId,
    String entityId,
    String ext,
    String uuid,
  ) => '$ownerId/blogs/$entityId/content/$uuid-original.$ext';

  /// Lowercased extension, defaulting to `jpg` — mirrors
  /// `ProfileMediaService.extensionOf` exactly (same reason: a filename with
  /// no dot must not produce a path ending in `.`).
  @visibleForTesting
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'jpg';
    final ext = fileName.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  /// Extension → MIME — mirrors `ProfileMediaService.mimeFromExtension`'s
  /// image formats exactly; no PDF branch, since an article's featured image
  /// can only be a picked photo.
  @visibleForTesting
  static String mimeFromExtension(String ext) => switch (ext.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'gif' => 'image/gif',
    _ => 'application/octet-stream',
  };

  /// Uploads [file] as the featured image for [entityId] (the article's own
  /// id once persisted, or a stable per-session draft id before that) and
  /// returns its public URL.
  ///
  /// `upsert: true` so retrying after a failed attempt replaces rather than
  /// 409s on the same path.
  Future<String> uploadImage({
    required String ownerId,
    required String entityId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final ext = extensionOf(file.name);
    final storagePath = path(ownerId, entityId, ext, _uuid.v4());

    await _supabase.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: file.mimeType ?? mimeFromExtension(ext),
            upsert: true,
          ),
        );

    return PublicMediaUrl.resolve(
      _supabase.storage.from(bucket).getPublicUrl(storagePath),
    );
  }

  /// Uploads [file] as an inline content image (inserted from the Quill
  /// toolbar's image button, not the featured-image field) and returns its
  /// public URL.
  ///
  /// Separate `content/` segment so an article's inline images don't share a
  /// path — and can't collide — with its single featured image, which
  /// [uploadImage] writes to `{ownerId}/blogs/{entityId}/{uuid}-original.*`.
  Future<String> uploadContentImage({
    required String ownerId,
    required String entityId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final ext = extensionOf(file.name);
    final storagePath = contentPath(ownerId, entityId, ext, _uuid.v4());

    await _supabase.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: file.mimeType ?? mimeFromExtension(ext),
            upsert: true,
          ),
        );

    return PublicMediaUrl.resolve(
      _supabase.storage.from(bucket).getPublicUrl(storagePath),
    );
  }
}
