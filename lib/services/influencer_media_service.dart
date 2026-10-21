// services/influencer_media_service.dart
//
// Video and thumbnail uploads for the influencer content form.
//
// SELF-CONTAINED, LIKE ProjectMediaService
// ----------------------------------------
// Nothing here touches `PropertyService`, `ProfileMediaService` or
// `ProjectMediaService`. It shares `property-media` with `PropertyService` but not
// its path shape or its size rules, and PropertyService is under a standing
// instruction not to change.
//
// THE BUCKET IS THE PORTAL'S; THE PATH IS NOT, AND CANNOT BE
// ----------------------------------------------------------
// `InfluencerVideoModal.tsx:141-151` uploads to `property-media` at:
//
//   videos/{user.id}/{Date.now()}-{sanitized name}
//   thumbnails/{user.id}/{Date.now()}-{sanitized name}
//
// That path is refused by production. The live INSERT policy on the bucket is
//
//   bucket_id = 'property-media' AND (storage.foldername(name))[1] = auth.uid()::text
//
// (20260317110000_create_required_storage_buckets.sql:29-34) — the *first* folder
// must be the caller's uid, and in the portal's path it is the literal `videos`.
// The migration that relaxes this to allow a category prefix
// (20270302030000_fix_storage_owner_policies.sql) sits in `supabase/migration2/`,
// which supabase/MIGRATIONS.md records as never applied. 20270322000000:6 confirms
// the live convention in as many words: "In property-media and avatars the
// top-level folder names are raw user UUIDs".
//
// So the uid comes first here, with the portal's folder kept as the second segment:
//
//   {uid}/videos/{ts}-{name}
//   {uid}/thumbnails/{ts}-{name}
//
// which satisfies the policy, matches what `PropertyService._uploadMedia` already
// does successfully in this bucket (`{uid}/{ts}-{i}.{ext}`), and still sorts both
// platforms' files into videos/ and thumbnails/ for anyone administering it.
//
// THE SIZE LIMIT IS 50 MB, NOT THE PORTAL'S 200
// ---------------------------------------------
// `InfluencerVideoModal.tsx:18` declares `MAX_VIDEO_BYTES = 200 * 1024 * 1024` and
// comments that it "matches the property-media bucket's file_size_limit". It does
// not: that limit is 52428800 — 50 MB — set by
// 20260522105737_fix_audit_issues.sql:18, which IS applied. A 120 MB upload
// therefore clears the portal's own gate and is then rejected by storage with a
// 400. Gating at the real limit here is a deliberate divergence; the portal's
// constant is worth correcting on that side.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';

import '../core/utils/public_media_url.dart';

/// Raised when an upload is refused before or after compression.
///
/// Carries a message meant for a snackbar, surfaced verbatim by the form.
class InfluencerMediaException implements Exception {
  const InfluencerMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InfluencerMediaService {
  InfluencerMediaService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Shared with property media. Public read; writes scoped to `{uid}/…`.
  static const String bucket = 'property-media';

  /// The bucket's real per-object ceiling, in bytes (50 MB).
  static const int maxVideoBytes = 50 * 1024 * 1024;

  /// Thumbnails are compressed by the picker before they get here, so this only
  /// catches something pathological.
  static const int maxThumbnailBytes = 50 * 1024 * 1024;

  static const String videoPrefix = 'videos';
  static const String thumbnailPrefix = 'thumbnails';

  /// Compresses [file] and uploads it, returning the public URL.
  ///
  /// Compression mirrors the portal's `compressVideo(file, {maxDimension: 1080,
  /// fps: 30})` (InfluencerVideoModal.tsx:133) — `VideoQuality.Res1280x720Quality`
  /// is the nearest preset that guarantees the long edge lands at or under 1080p
  /// while cutting a phone clip enough to clear 50 MB. If compression fails or
  /// somehow returns a larger file, the original is used and the size gate below
  /// decides: a failed optimisation must not become a failed upload.
  ///
  /// Takes the `XFile` `image_picker` returns rather than a `dart:io.File` —
  /// on Flutter Web, `file.path` is a `blob:` URL, and `dart:io.File`
  /// operations on it throw `Unsupported operation: _Namespace`.
  /// `XFile.readAsBytes()` works on every platform.
  Future<String> uploadVideo({
    required XFile file,
    required String userId,
    void Function(String stage)? onProgress,
  }) async {
    Uint8List originalBytes;
    try {
      originalBytes = await file.readAsBytes();
    } catch (e) {
      throw const InfluencerMediaException('That video could not be read.');
    }
    if (originalBytes.isEmpty) {
      throw const InfluencerMediaException('That video appears to be empty.');
    }

    onProgress?.call('Compressing video…');
    final compression = await _compress(file, originalBytes);
    final Uint8List toUpload = compression.bytes;

    if (toUpload.length > maxVideoBytes) {
      // The portal's wording, with the real number
      // (InfluencerVideoModal.tsx:136-138).
      throw InfluencerMediaException(
        'Video is too large (${_mb(toUpload.length)}). Maximum is '
        '${_mb(maxVideoBytes)}. Please upload a shorter or lower-resolution '
        'clip.',
      );
    }

    // `video_compress` always encodes into an MP4 container regardless of
    // the source format (its own README: "All video files are encoded in an
    // MP4 container") — so once compression actually produced different
    // bytes, [toUpload] is genuinely MP4 and the upload's name/content-type
    // must say so, not repeat the original (e.g. `.mov`) file's extension.
    // That mismatch was the actual bug: a compressed `.mov` selection still
    // uploaded labeled `video/quicktime`, which this bucket's allow-list
    // rejects even though the bytes themselves were fine. When compression
    // fell back to the original bytes, the original extension decides, and
    // one this bucket doesn't accept is refused here — before the network
    // round trip — instead of failing later with a raw storage error.
    final String uploadFileName = resolveUploadFileName(
      originalFileName: file.name,
      compressedToMp4: compression.isMp4,
    );

    if (!compression.isMp4 && !isAcceptedVideoFileName(uploadFileName)) {
      throw const InfluencerMediaException(
        "This video format isn't supported. Please upload an MP4 file.",
      );
    }

    onProgress?.call('Uploading video…');
    return _upload(
      bytes: toUpload,
      path:
          '$userId/$videoPrefix/${_stamp()}-'
          '${sanitizeFileName(uploadFileName)}',
      fileName: uploadFileName,
    );
  }

  /// The name to upload a video under, given whether compression actually
  /// produced real MP4 bytes ([compressedToMp4]) or [originalFileName]'s
  /// own bytes are what's being sent unchanged. Exposed for testing — this
  /// decision is the fix for the extension/content-type mismatch bug.
  @visibleForTesting
  static String resolveUploadFileName({
    required String originalFileName,
    required bool compressedToMp4,
  }) {
    if (!compressedToMp4) return originalFileName;
    final dot = originalFileName.lastIndexOf('.');
    final stem = dot <= 0
        ? originalFileName
        : originalFileName.substring(0, dot);
    return '$stem.mp4';
  }

  /// Whether [fileName]'s extension maps to a MIME type `property-media`'s
  /// real allow-list (Supabase Storage's `allowed_mime_types` for this
  /// bucket) accepts for video: MP4/MPEG only, never MOV or anything else.
  @visibleForTesting
  static bool isAcceptedVideoFileName(String fileName) =>
      const {'video/mp4', 'video/mpeg'}.contains(mimeFromName(fileName));

  /// Uploads a thumbnail already downscaled by the picker.
  ///
  /// The portal runs `compressImage(file, {maxDimension: 1280, quality: 0.8})`.
  /// On this side `image_picker`'s own `maxWidth: 1280, imageQuality: 80` does
  /// that during selection — the same approach `ProfileMediaService` takes — so
  /// there is nothing left to do here but check and send.
  Future<String> uploadThumbnail({
    required XFile file,
    required String userId,
  }) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw const InfluencerMediaException('That image could not be read.');
    }
    if (bytes.isEmpty) {
      throw const InfluencerMediaException('That image appears to be empty.');
    }
    if (bytes.length > maxThumbnailBytes) {
      throw InfluencerMediaException(
        'That thumbnail is larger than the ${_mb(maxThumbnailBytes)} limit.',
      );
    }

    return _upload(
      bytes: bytes,
      path:
          '$userId/$thumbnailPrefix/${_stamp()}-${sanitizeFileName(file.name)}',
      fileName: file.name,
    );
  }

  /// Downscales to 1080p/30fps, or returns [file] unchanged if that is not
  /// possible or not an improvement.
  ///
  /// Split out and overridable so the form's upload path can be tested without a
  /// native plugin — `video_compress` talks to platform channels that do not exist
  /// under `flutter test`.
  @visibleForTesting
  Future<File> compressForUpload(File file) async {
    final info = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.Res1280x720Quality,
      includeAudio: true,
    );
    final compressed = info?.file;
    if (compressed == null) return file;
    return compressed;
  }

  /// Compression is an optimisation, never a gate — any failure (including
  /// "unsupported on this platform") falls back to [originalBytes] and lets
  /// the caller's size check have the final say.
  ///
  /// `isMp4` tells the caller whether [bytes] is real `video_compress`
  /// output (always MP4) or the untouched original (whatever format that
  /// was) — the two cases need different upload naming/content-type
  /// handling, so this can no longer just return the bytes alone.
  Future<({Uint8List bytes, bool isMp4})> _compress(
    XFile file,
    Uint8List originalBytes,
  ) async {
    if (kIsWeb) {
      // `video_compress` has no web implementation, and there is no real
      // filesystem path to hand it on web anyway — an `XFile.path` there is
      // a `blob:` URL, not something `dart:io.File` can open.
      return (bytes: originalBytes, isMp4: false);
    }
    try {
      final compressed = await compressForUpload(File(file.path));
      final compressedBytes = await compressed.readAsBytes();
      if (compressedBytes.length >= originalBytes.length) {
        return (bytes: originalBytes, isMp4: false);
      }
      return (bytes: compressedBytes, isMp4: true);
    } catch (e) {
      debugPrint(
        'InfluencerMediaService compression failed, '
        'uploading original: $e',
      );
      return (bytes: originalBytes, isMp4: false);
    }
  }

  Future<String> _upload({
    required Uint8List bytes,
    required String path,
    required String fileName,
  }) async {
    try {
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeFromName(fileName)),
          );
      return PublicMediaUrl.resolve(
        _supabase.storage.from(bucket).getPublicUrl(path),
      );
    } catch (e) {
      debugPrint('InfluencerMediaService upload to $path failed: $e');
      rethrow;
    }
  }

  /// Milliseconds since epoch — the portal's `Date.now()`.
  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// The portal's `sanitizeFileName` (InfluencerVideoModal.tsx:84-90): strip the
  /// path, keep one extension, and reduce both halves to characters storage will
  /// accept without escaping.
  ///
  /// Exposed for tests because the resulting object key is part of the contract
  /// with the portal.
  @visibleForTesting
  static String sanitizeFileName(String pathOrName) {
    final separator = pathOrName.lastIndexOf(RegExp(r'[/\\]'));
    final name = separator < 0
        ? pathOrName
        : pathOrName.substring(separator + 1);

    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot + 1);

    final cleanBase = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final cleanExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    return cleanExt.isEmpty ? cleanBase : '$cleanBase.$cleanExt';
  }

  /// Content type from the file name.
  ///
  /// The same table `ProjectMediaService` carries, minus the PDF case: this form
  /// takes videos and images only. Copied rather than imported so neither service
  /// can change the other's uploads.
  @visibleForTesting
  static String mimeFromName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mpeg' || 'mpg' => 'video/mpeg',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      _ => 'application/octet-stream',
    };
  }
}
