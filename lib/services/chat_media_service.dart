import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';

import 'messaging_exceptions.dart';

/// Image/voice upload into the shared, private `chat-media` Supabase Storage
/// bucket, plus signed-URL reads. Every limit/path convention below matches
/// the portal's features/messaging/lib/uploadChatMedia.ts and
/// chatMediaUrlCache.ts exactly — this reuses the same bucket, the same
/// `moderate-media`/`get-chat-media-url` Edge Functions, and the same
/// `${authUid}/${uuid}.${ext}` path the bucket's RLS policy requires.
class ChatMediaService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 50 * 1024 * 1024;
  static const int maxVoiceBytes = 10 * 1024 * 1024;
  static const Duration maxVoiceDuration = Duration(minutes: 5);

  static const Set<String> allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  };

  final Map<String, _CachedUrl> _urlCache = {};

  /// Validates, strips EXIF/GPS, uploads, and inserts a `media_status:
  /// 'pending'` message row, then fires (fire-and-forget) the `moderate-media`
  /// Edge Function. Returns the inserted message id so the caller can offer a
  /// manual "Retry" if it's still pending after ~2 minutes.
  Future<String> sendImage({
    required Uint8List bytes,
    required String extension,
    required String surface, // 'dm' | 'channel'
    required String threadId, // conversation_id or channel_id
    required String senderId,
  }) async {
    final ext = extension.toLowerCase().replaceFirst('.', '');
    if (!allowedImageExtensions.contains(ext)) {
      throw ChatMediaValidationError(
        '"$ext" isn\'t supported. Use JPEG, PNG, WebP, HEIC, or MP4.',
      );
    }
    if (bytes.lengthInBytes > maxImageBytes) {
      throw const ChatMediaValidationError('Image must be 10MB or smaller.');
    }

    final stripped = await _stripExif(bytes, ext: ext);
    final path = '$senderId/${_uuid.v4()}.$ext';

    try {
      await _supabase.storage
          .from('chat-media')
          .uploadBinary(
            path,
            stripped,
            fileOptions: FileOptions(contentType: _contentTypeFor(ext)),
          );
    } catch (e) {
      debugPrint('ChatMediaService.sendImage upload failed: $e');
      rethrow;
    }

    final table = surface == 'channel' ? 'channel_messages' : 'messages';
    final idColumn = surface == 'channel' ? 'channel_id' : 'conversation_id';

    final inserted = await _supabase
        .from(table)
        .insert({
          idColumn: threadId,
          'sender_id': senderId,
          'content': '',
          'message_type': 'image',
          'media_urls': [path],
          'media_status': 'pending',
        })
        .select('id')
        .single();

    final messageId = inserted['id']?.toString();
    if (messageId == null) {
      throw StateError('Image message insert returned no id');
    }

    unawaited(
      requestModeration(
        storagePath: path,
        messageId: messageId,
        surface: surface,
      ),
    );

    return messageId;
  }

  /// Validates, compresses, uploads, and inserts a `media_status: 'pending'`
  /// message row for a video — the video half of the portal's
  /// `uploadChatMedia.ts`: compress first (`compressVideo`), gate on size,
  /// then grab a frame (`captureVideoFrame`) so `moderate-media` has an
  /// actual image to run through moderation instead of raw video bytes.
  ///
  /// Channel-only, same as the portal ("Video is only supported in channels
  /// right now") — this method trusts the caller to have already checked
  /// that; see [ChatThreadProvider.sendVideo]'s doc comment for why.
  ///
  /// Takes the `XFile` `image_picker` returns (not a `dart:io.File`) because
  /// `video_compress` needs a real filesystem path to operate on — same
  /// reasoning as [InfluencerMediaService.uploadVideo], which this mirrors.
  Future<String> sendVideo({
    required XFile file,
    required String surface, // 'dm' | 'channel'
    required String threadId,
    required String senderId,
  }) async {
    Uint8List originalBytes;
    try {
      originalBytes = await file.readAsBytes();
    } catch (e) {
      throw const ChatMediaValidationError('That video could not be read.');
    }
    if (originalBytes.isEmpty) {
      throw const ChatMediaValidationError('That video appears to be empty.');
    }

    final compression = await _compressVideo(file, originalBytes);
    final Uint8List toUpload = compression.bytes;

    if (toUpload.lengthInBytes > maxVideoBytes) {
      throw ChatMediaValidationError(
        'Video must be ${_mb(maxVideoBytes)} or smaller.',
      );
    }
    // `video_compress` always encodes into an MP4 container regardless of
    // source format, so compressed output is always real MP4 — matching the
    // portal's `ALLOWED_VIDEO_TYPES = {'video/mp4'}`. A compression failure
    // falls back to the original bytes, which must then already be an mp4
    // file itself (checked by extension — there is no reliable sniff-by-byte
    // check worth adding here for a rare fallback path).
    if (!compression.isMp4 && !_looksLikeMp4(file.name)) {
      throw const ChatMediaValidationError(
        "This video format isn't supported. Please upload an MP4 file.",
      );
    }

    final path = '$senderId/${_uuid.v4()}.mp4';
    try {
      await _supabase.storage
          .from('chat-media')
          .uploadBinary(
            path,
            toUpload,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );
    } catch (e) {
      debugPrint('ChatMediaService.sendVideo upload failed: $e');
      rethrow;
    }

    // Best-effort — a failed frame capture just means moderate-media falls
    // back to approving without inspecting the video, same as the portal.
    final frameBytes = await _captureModerationFrame(file);
    String? moderationImagePath;
    if (frameBytes != null && frameBytes.isNotEmpty) {
      final framePath = '$senderId/${_uuid.v4()}-modcheck.jpg';
      try {
        await _supabase.storage
            .from('chat-media')
            .uploadBinary(
              framePath,
              frameBytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        moderationImagePath = framePath;
      } catch (e) {
        debugPrint('ChatMediaService.sendVideo frame upload failed: $e');
      }
    }

    final table = surface == 'channel' ? 'channel_messages' : 'messages';
    final idColumn = surface == 'channel' ? 'channel_id' : 'conversation_id';

    final inserted = await _supabase
        .from(table)
        .insert({
          idColumn: threadId,
          'sender_id': senderId,
          'content': '',
          'message_type': 'video',
          'media_urls': [path],
          'media_status': 'pending',
        })
        .select('id')
        .single();

    final messageId = inserted['id']?.toString();
    if (messageId == null) {
      throw StateError('Video message insert returned no id');
    }

    unawaited(
      requestModeration(
        storagePath: path,
        messageId: messageId,
        surface: surface,
        moderationImagePath: moderationImagePath,
      ),
    );

    return messageId;
  }

  /// Downscales to 1080p/30fps, matching [InfluencerMediaService]'s own
  /// `compressForUpload` preset — compression is an optimisation, never a
  /// gate, so any failure (including "unsupported on this platform") falls
  /// back to [originalBytes] and lets [sendVideo]'s size/format checks have
  /// the final say.
  Future<({Uint8List bytes, bool isMp4})> _compressVideo(
    XFile file,
    Uint8List originalBytes,
  ) async {
    if (kIsWeb) {
      // `video_compress` has no web implementation, and an `XFile.path` on
      // web is a `blob:` URL, not something it can open.
      return (bytes: originalBytes, isMp4: false);
    }
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res1280x720Quality,
        includeAudio: true,
      );
      final compressedFile = info?.file;
      if (compressedFile == null) {
        return (bytes: originalBytes, isMp4: false);
      }
      final compressedBytes = await compressedFile.readAsBytes();
      if (compressedBytes.isEmpty) {
        return (bytes: originalBytes, isMp4: false);
      }
      return (bytes: compressedBytes, isMp4: true);
    } catch (e) {
      debugPrint(
        'ChatMediaService: video compression failed, uploading original: $e',
      );
      return (bytes: originalBytes, isMp4: false);
    }
  }

  /// Grabs a single JPEG frame from the video for `moderate-media` to
  /// actually inspect — mirrors the portal's `captureVideoFrame`. Returns
  /// null on web (no `video_compress` implementation) or on any failure;
  /// [sendVideo] treats that as "skip the frame", not an error.
  Future<Uint8List?> _captureModerationFrame(XFile file) async {
    if (kIsWeb) return null;
    try {
      return await VideoCompress.getByteThumbnail(file.path, quality: 60);
    } catch (e) {
      debugPrint('ChatMediaService: video frame capture failed: $e');
      return null;
    }
  }

  static bool _looksLikeMp4(String fileName) =>
      fileName.toLowerCase().trim().endsWith('.mp4');

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()}MB';

  /// Re-runs moderation for a message stuck `pending` — the manual "Retry"
  /// action, or the initial fire-and-forget call right after upload. Errors
  /// are swallowed here (matching the portal's fire-and-forget pattern): a
  /// failure just leaves the row `pending` for the server-side sweep cron.
  Future<void> requestModeration({
    required String storagePath,
    required String messageId,
    required String surface,
    String? moderationImagePath,
  }) async {
    try {
      await _supabase.functions.invoke(
        'moderate-media',
        body: {
          'storagePath': storagePath,
          'bucket': 'chat-media',
          'messageId': messageId,
          'surface': surface,
          if (moderationImagePath != null)
            'moderationImagePath': moderationImagePath,
        },
      );
    } catch (e) {
      debugPrint(
        'ChatMediaService.requestModeration failed (will retry later): $e',
      );
    }
  }

  /// Uploads a recorded voice note. No moderation step for audio — approved
  /// immediately, matching the portal exactly.
  Future<void> sendVoiceNote({
    required Uint8List bytes,
    required String extension,
    required Duration duration,
    required String surface,
    required String threadId,
    required String senderId,
  }) async {
    const allowedExt = {'webm', 'm4a', 'mp4', 'ogg', 'wav', 'aac'};
    final ext = extension.toLowerCase().replaceFirst('.', '');
    if (!allowedExt.contains(ext)) {
      throw ChatMediaValidationError(
        '"$ext" isn\'t a supported recording format.',
      );
    }
    if (bytes.lengthInBytes > maxVoiceBytes) {
      throw const ChatMediaValidationError(
        'Voice note must be 10MB or smaller.',
      );
    }
    if (duration > maxVoiceDuration) {
      throw const ChatMediaValidationError(
        'Voice notes are limited to 5 minutes.',
      );
    }

    final path = '$senderId/${_uuid.v4()}.$ext';
    await _supabase.storage
        .from('chat-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentTypeFor(ext)),
        );

    final table = surface == 'channel' ? 'channel_messages' : 'messages';
    final idColumn = surface == 'channel' ? 'channel_id' : 'conversation_id';

    await _supabase.from(table).insert({
      idColumn: threadId,
      'sender_id': senderId,
      'content': 'Voice message',
      'message_type': 'audio',
      'media_urls': [path],
      'media_status': 'approved',
    });
  }

  /// A short-lived signed URL for a private `chat-media` object — the only
  /// way to read it; the bucket has no SELECT policy at all. Cached ~4
  /// minutes client-side (the function's own TTL is 5 minutes server-side).
  Future<String> getSignedUrl({
    required String path,
    required String surface,
  }) async {
    final cached = _urlCache[path];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }

    final response = await _supabase.functions.invoke(
      'get-chat-media-url',
      body: {'path': path, 'surface': surface},
    );
    final data = response.data;
    final url = data is Map ? data['url'] as String? : null;
    if (url == null) {
      throw StateError('get-chat-media-url returned no url');
    }
    _urlCache[path] = _CachedUrl(
      url,
      DateTime.now().add(const Duration(minutes: 4)),
    );
    return url;
  }

  /// Downloads the image bytes for [path] through its signed URL. A failed
  /// first attempt (an expired link, a dropped connection) is retried once
  /// with a freshly signed URL before giving up, and every failure surfaces
  /// as a [ChatMediaValidationError] with a message the user can act on.
  Future<Uint8List> _downloadImageBytes({
    required String path,
    required String surface,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) _urlCache.remove(path);
        final url = await getSignedUrl(path: path, surface: surface);
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
        debugPrint(
          'ChatMediaService: image download got ${response.statusCode} '
          '(attempt ${attempt + 1})',
        );
      } catch (e) {
        debugPrint(
          'ChatMediaService: image download failed (attempt ${attempt + 1}): $e',
        );
      }
    }
    throw const ChatMediaValidationError(
      "Couldn't download the image. Check your connection and try again.",
    );
  }

  /// Downloads the image at [path] (via the same signed URL the bubble
  /// already displays it through) and saves it to the device's photo
  /// gallery. `gal` has no web implementation — same constraint
  /// `visiting_card_sheet.dart`'s download button already documents — so
  /// this fails fast with a clear message there instead of a raw
  /// `MissingPluginException`.
  ///
  /// Every failure — including the ones that used to fall through to a
  /// generic "Couldn't save" (a missing native plugin after a hot reload, a
  /// platform error from the gallery) — is reported as a
  /// [ChatMediaValidationError] carrying the real reason.
  Future<void> saveImageToGallery({
    required String path,
    required String surface,
  }) async {
    if (kIsWeb) {
      throw const ChatMediaValidationError(
        'Saving images needs the Android/iOS app — it is not available in '
        'the web preview.',
      );
    }

    final bytes = await _downloadImageBytes(path: path, surface: surface);

    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        throw const ChatMediaValidationError(
          'Gallery access was denied. Allow photo access for PropCID in '
          'Settings, or use Share to save the image.',
        );
      }
      await Gal.putImageBytes(
        bytes,
        name: 'PropCID_${DateTime.now().millisecondsSinceEpoch}',
      );
    } on ChatMediaValidationError {
      rethrow;
    } on GalException catch (e) {
      throw ChatMediaValidationError('${e.type.message} Try Share instead.');
    } on MissingPluginException {
      throw const ChatMediaValidationError(
        'Saving needs a full app restart (stop and run the app again, not a '
        'hot reload). You can use Share in the meantime.',
      );
    } catch (e) {
      debugPrint('ChatMediaService: gallery save failed: $e');
      throw const ChatMediaValidationError(
        "The gallery couldn't save the image. Try Share instead.",
      );
    }
  }

  /// Hands the image to the system share sheet, whose "Save to device" /
  /// "Drive" / "Files" targets work with no gallery permission and no
  /// native gallery plugin — the always-available way to get the picture out
  /// of a chat.
  Future<void> shareImage({
    required String path,
    required String surface,
  }) async {
    if (kIsWeb) {
      throw const ChatMediaValidationError(
        'Sharing images needs the Android/iOS app.',
      );
    }
    final bytes = await _downloadImageBytes(path: path, surface: surface);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/PropCID_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/jpeg')]);
    } catch (e) {
      debugPrint('ChatMediaService: share failed: $e');
      throw const ChatMediaValidationError("Couldn't share the image.");
    }
  }

  /// Re-encodes jpg/png in place (dropping EXIF/GPS in the process, since
  /// `image`'s decoders don't carry it forward unless explicitly copied).
  /// webp/heic are uploaded unchanged — the `image` package's WebP encoder
  /// isn't reliable enough across platforms to risk silently corrupting the
  /// upload, and it has no HEIC encoder at all. This is a smaller privacy
  /// guarantee than the portal's (which re-encodes every image via canvas),
  /// flagged rather than papered over with an encoder that might mis-fire.
  Future<Uint8List> _stripExif(Uint8List bytes, {required String ext}) async {
    if (ext != 'jpg' && ext != 'jpeg' && ext != 'png') return bytes;
    try {
      return await compute(_StripExifJob(ext).run, bytes);
    } catch (e) {
      // Re-encoding failed (unsupported/corrupt image) — upload the original
      // rather than blocking the send entirely.
      debugPrint('ChatMediaService: EXIF strip failed, uploading as-is: $e');
      return bytes;
    }
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'webm':
        return 'audio/webm';
      default:
        return 'image/jpeg';
    }
  }
}

class _CachedUrl {
  final String url;
  final DateTime expiresAt;
  _CachedUrl(this.url, this.expiresAt);
}

/// Runs on a background isolate via `compute` — decoding/re-encoding a full
/// photo on the UI isolate would jank the send button's tap animation. A
/// small sendable job object (just the target extension) rather than a
/// closure, since `compute`/`Isolate.run` require the callback to not
/// capture non-sendable state.
class _StripExifJob {
  final String ext;
  const _StripExifJob(this.ext);

  Uint8List run(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // `image`'s decoders drop EXIF/ICC metadata by default unless explicitly
    // copied forward, so a plain re-encode is sufficient to strip GPS/EXIF.
    return ext == 'png'
        ? Uint8List.fromList(img.encodePng(decoded))
        : Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
  }
}

/// Not part of [ChatMediaService] itself since `File` (dart:io) isn't
/// available on web — kept as a free function so callers on a platform that
/// supports it can read bytes/extension from an [image_picker] `XFile`
/// without this service depending on `dart:io` at all.
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
