// services/project_media_service.dart
//
// Uploads for the builder project wizard's five asset types.
//
// SELF-CONTAINED BY DESIGN
// ------------------------
// Neither `PropertyService` nor `ProfileMediaService` is touched or depended on.
// Both already own a bucket and a path pattern that differ from this one, and the
// project feature must not be coupled to either — the same reasoning that made
// `ProfileMediaService` its own service in the profile work.
//
// THE BUCKET AND PATHS ARE THE PORTAL'S
// -------------------------------------
// Bucket `project-media`: public read, authenticated insert/update/delete with
// **no path restriction** (`20260409000000_create_project_media_bucket.sql`).
// The app's own client-side ceiling below is 50 MB per object.
//
//   logo            logos/{ts}-logo.{ext}                    BuilderProjectWizard.tsx:323-324
//   master layout   master-layouts/{ts}-master-layout.{ext}  :347-348
//   images          other-images/{ts}-{rand}.{ext}           :375-377
//   videos          project-videos/{ts}-{rand}.{ext}         :407-409
//   brochure        brochures/{ts}-brochure.{ext}            :1055-1056
//
// Paths are deliberately **not** namespaced by user id — the portal writes every
// builder's logos into one flat `logos/` folder, and matching it keeps both apps'
// files in the same structure for anyone administering the bucket. Collisions are
// avoided by the millisecond timestamp plus, for the multi-file types, a random
// suffix. See PD3 in docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md: the bucket's
// INSERT policy checks only `bucket_id`, so this is not a boundary the client can
// tighten.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/public_media_url.dart';

/// Raised when an upload is refused before it is attempted.
///
/// Carries a message meant for a snackbar — the wizard surfaces it verbatim
/// rather than translating an exception into its own copy.
class ProjectMediaException implements Exception {
  const ProjectMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProjectMediaService {
  ProjectMediaService({SupabaseClient? client, Random? random})
    : _supabase = client ?? Supabase.instance.client,
      _random = random ?? Random();

  final SupabaseClient _supabase;
  final Random _random;

  /// The bucket every project asset lives in.
  static const String bucket = 'project-media';

  /// This app's own per-object ceiling, in bytes (50 MB).
  ///
  /// Checked client-side so an oversize file fails with a sentence the user can
  /// act on, rather than a storage `413` surfacing as a generic upload error.
  /// Applied to every asset type here, not just videos.
  static const int maxBytes = 50 * 1024 * 1024;

  // ── Path prefixes, one per asset type ───────────────────────────────────
  static const String logoPrefix = 'logos';
  static const String masterLayoutPrefix = 'master-layouts';
  static const String imagePrefix = 'other-images';
  static const String videoPrefix = 'project-videos';
  static const String brochurePrefix = 'brochures';

  /// Uploads a project logo. Returns its public URL.
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String fileName,
  }) => _upload(
    bytes: bytes,
    path: '$logoPrefix/${_stamp()}-logo.${_ext(fileName)}',
    fileName: fileName,
  );

  /// Uploads a master-plan layout image. Returns its public URL.
  ///
  /// The caller appends the result to `map_images`; `master_layout_url` is then
  /// derived from that list's first entry at write time.
  Future<String> uploadMasterLayout({
    required Uint8List bytes,
    required String fileName,
  }) => _upload(
    bytes: bytes,
    path: '$masterLayoutPrefix/${_stamp()}-master-layout.${_ext(fileName)}',
    fileName: fileName,
  );

  /// Uploads one project photograph. Returns its public URL.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) => _upload(
    bytes: bytes,
    path: '$imagePrefix/${_stamp()}-${_suffix()}.${_ext(fileName)}',
    fileName: fileName,
  );

  /// Uploads one project video. Returns its public URL.
  ///
  /// `project-media`'s real, backend-enforced allow-list (Supabase
  /// Storage's `allowed_mime_types`) accepts `video/mp4` only. Project
  /// videos upload uncompressed — there is no `video_compress` wiring here,
  /// unlike the influencer video path — so a `.mov` clip (the common
  /// default on iPhone) would otherwise reach Storage unconverted and be
  /// rejected there; this catches it first with a message that says why.
  Future<String> uploadVideo({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (mimeFromName(fileName) != 'video/mp4') {
      throw const ProjectMediaException(
        "This video format isn't supported. Please upload an MP4 file.",
      );
    }
    return _upload(
      bytes: bytes,
      path: '$videoPrefix/${_stamp()}-${_suffix()}.${_ext(fileName)}',
      fileName: fileName,
      oversizeMessage: 'Videos must be under 50 MB.',
    );
  }

  /// Uploads the project brochure. Returns its public URL.
  ///
  /// Uploaded as-is — the portal does not compress it either (`:1059` passes the
  /// raw `file`), because a PDF is not an image and re-encoding it would corrupt
  /// it. `application/pdf` is set explicitly so the browser opening the public URL
  /// renders it instead of downloading an octet-stream.
  Future<String> uploadBrochure({
    required Uint8List bytes,
    required String fileName,
  }) => _upload(
    bytes: bytes,
    path: '$brochurePrefix/${_stamp()}-brochure.${_ext(fileName)}',
    fileName: fileName,
    oversizeMessage: 'The brochure must be under 50 MB.',
  );

  /// One upload, one public URL.
  Future<String> _upload({
    required Uint8List bytes,
    required String path,
    required String fileName,
    String? oversizeMessage,
  }) async {
    if (bytes.isEmpty) {
      throw const ProjectMediaException('That file appears to be empty.');
    }
    if (bytes.length > maxBytes) {
      throw ProjectMediaException(
        oversizeMessage ?? 'That file is larger than the 50 MB limit.',
      );
    }

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
      debugPrint('ProjectMediaService upload to $path failed: $e');
      rethrow;
    }
  }

  /// Milliseconds since epoch — the portal's `Date.now()`.
  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// The portal's `Math.random().toString(36).substring(7)` — a short random tag
  /// so two files picked in the same millisecond cannot collide.
  String _suffix() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      6,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  /// Lowercased extension, or `bin` when the name carries none.
  ///
  /// Exposed for tests: the path format is part of the contract with the portal.
  @visibleForTesting
  static String extensionOf(String fileName) => _ext(fileName);

  static String _ext(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'bin';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Content type from the file name.
  ///
  /// The image and video cases are `PropertyService._mimeFromExt`'s, extended
  /// with `application/pdf` for the brochure. Copied rather than imported so this
  /// service stays free of any dependency on the property feature.
  @visibleForTesting
  static String mimeFromName(String fileName) => switch (_ext(fileName)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'gif' => 'image/gif',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
