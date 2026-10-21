// services/profile_media_service.dart
//
// Picks and uploads profile media: avatar, cover photo, and verification
// documents.
//
// COMPLETELY SELF-CONTAINED (approved decision: Option A)
// ------------------------------------------------------
// This file imports nothing from the property feature and nothing from
// `PropertyService`, which is treated as stable. The app's only other upload code
// is `PropertyService._uploadMedia` — private, coupled to `PostPropertyProvider`,
// with the `property-media` bucket and its path pattern hardcoded — so it could
// not be called from here without changing its visibility and signature. That was
// explicitly ruled out.
//
// What is deliberately MIRRORED rather than imported:
//   * `uploadBinary` + `getPublicUrl` against a named bucket
//   * `{userId}/…` path prefix, which is what the storage policies require
//   * an extension→MIME map, because `XFile.mimeType` is null on some platforms
//   * compression via `image_picker`'s own sizing, the approach
//     `post_property/steps/media_contact_step.dart:80` already documents
//
// `test/profile_media_service_test.dart` asserts the mirrored MIME map and path
// shapes, so the duplication cannot silently drift from the property feature's.
//
// STORAGE POLICIES — no backend change is needed. Both buckets already exist and
// their INSERT/UPDATE policies require the first path segment to equal
// `auth.uid()` (20260317110000_create_required_storage_buckets.sql). Every path
// built below starts with the user id.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/public_media_url.dart';
import 'auth_service.dart';

/// Thrown by [ProfileMediaService] for a problem the user caused (an
/// oversized or wrong-type file) rather than an infrastructure failure, so
/// the caller can surface the exact reason instead of a generic
/// "Upload failed" message.
class ProfileMediaValidationError implements Exception {
  ProfileMediaValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Which profile document is being uploaded.
///
/// The slug becomes the filename prefix and mirrors the portal's
/// `handleDocumentUpload` types (EditProfile.tsx:243-257).
enum ProfileDocumentKind {
  rera('rera', 'social_media.rera_certificate_url'),
  gst('gst', 'social_media.gst_certificate_url'),
  pan('pan', 'social_media.pan_card_url'),
  registrationProof('proof', 'social_media.registration_proof_url'),
  aadhaar('aadhaar', 'social_media.aadhaar_card_url'),
  // Genuine separate back-side upload — the backend's registration-submit
  // contract requires `aadhaarCardUrl` and `aadhaarCardBackUrl` as two
  // distinct fields; a single compositied front+back image can no longer
  // satisfy both.
  aadhaarBack('aadhaar-back', 'social_media.aadhaar_card_back_url'),
  companyLogo('logo', 'company_logo_url');

  const ProfileDocumentKind(this.slug, this.target);

  /// Filename prefix.
  final String slug;

  /// Where the resulting URL belongs. Documentation only — this service returns
  /// the URL and the caller stores it, because five of the six live inside the
  /// `social_media` JSON and must go through the merge-preserving writer.
  final String target;
}

class ProfileMediaService {
  ProfileMediaService({
    ImagePicker? picker,
    SupabaseClient? client,
    AuthService? authService,
  }) : _picker = picker ?? ImagePicker(),
       _supabase = client ?? Supabase.instance.client,
       _authService = authService ?? AuthService();

  final ImagePicker _picker;
  final SupabaseClient _supabase;
  final AuthService _authService;
  static const _uuid = Uuid();

  // ── Buckets ───────────────────────────────────────────────────────────────

  /// Avatars and verification documents.
  ///
  /// The portal is internally inconsistent here — `EditProfile.tsx` and
  /// `AvatarUploadModal.tsx` write avatars to `avatars`, while `UserProfile.tsx`'s
  /// inline handler writes them to `property-media`. `avatars` is followed because
  /// it is what the edit form and the dedicated modal use, and it is the bucket
  /// named for the purpose.
  static const String avatarBucket = 'avatars';

  /// Cover photos, matching `BackgroundUploadModal.tsx:161`.
  ///
  /// Not `avatars`: the portal genuinely puts covers in `property-media`, and a
  /// cover uploaded by the app must be readable by the portal at the URL it
  /// expects to find.
  static const String coverBucket = 'property-media';

  /// Aadhaar and PAN specifically — the portal's `document` preset
  /// (`imagePresets.ts`), `private: true`, `defaultBucket: "documents"`.
  /// Unlike [avatarBucket], this bucket has no public-read policy, so a
  /// stored value here is a storage *path*, never a browsable URL — see
  /// [uploadDocument].
  static const String verificationDocumentBucket = 'documents';

  /// Which document kinds the portal accepts as PDF as well as image, and
  /// which therefore use [verificationDocumentBucket] instead of
  /// [avatarBucket]. RERA/GST/registration-proof/company-logo are unchanged
  /// by this feature and keep uploading as images to the existing bucket.
  static bool acceptsPdf(ProfileDocumentKind kind) =>
      kind == ProfileDocumentKind.aadhaar ||
      kind == ProfileDocumentKind.aadhaarBack ||
      kind == ProfileDocumentKind.pan;

  // ── Sizing ────────────────────────────────────────────────────────────────
  //
  // The portal compresses client-side before upload: 1024 px for avatars
  // (AvatarUploadModal.tsx:155) and 1920 px for covers
  // (BackgroundUploadModal.tsx:152). `image_picker` applies the same ceiling at
  // capture time, which is the approach the Post Property wizard documents —
  // it avoids pulling in an image-processing package (R14 forbids new deps).

  static const double avatarMaxDimension = 1024;
  static const double coverMaxDimension = 1920;
  static const double documentMaxDimension = 2048;
  static const int jpegQuality = 85;

  /// Matches the portal's `document` preset `maxInputBytes`
  /// (`imagePresets.ts`) — 20MB, enforced client-side before upload since a
  /// PDF picked via `file_picker` bypasses `image_picker`'s own downscaling.
  static const int verificationDocumentMaxBytes = 20 * 1024 * 1024;

  /// Extensions the Aadhaar/PAN picker offers, mirroring the portal's
  /// `accept=".pdf,image/*"` (EditProfile.tsx) narrowed to the formats this
  /// service already knows how to MIME-map.
  static const List<String> verificationDocumentExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  ];

  // ── Picking ───────────────────────────────────────────────────────────────

  /// Opens the gallery or camera and returns the chosen image, already downscaled.
  ///
  /// Returns null when the user cancels — not an error.
  Future<XFile?> pickImage({
    required ImageSource source,
    required double maxDimension,
  }) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: jpegQuality,
      );
    } catch (e) {
      debugPrint('ProfileMediaService.pickImage failed: $e');
      return null;
    }
  }

  Future<XFile?> pickAvatar({ImageSource source = ImageSource.gallery}) =>
      pickImage(source: source, maxDimension: avatarMaxDimension);

  Future<XFile?> pickCover({ImageSource source = ImageSource.gallery}) =>
      pickImage(source: source, maxDimension: coverMaxDimension);

  /// Picks a verification document.
  ///
  /// [allowPdf] defaults to false, so every existing caller (the builder,
  /// broker and influencer *registration* screens, which construct this
  /// service themselves rather than going through [EditProfileProvider])
  /// keeps picking an image only via `image_picker`, exactly as before this
  /// feature. Only [EditProfileProvider.pickAndUploadDocument] opts in, for
  /// [acceptsPdf] kinds (Aadhaar/PAN) specifically, accepting image or PDF
  /// via `file_picker` — matching the portal's `.pdf,image/*` input for the
  /// Edit Profile re-upload flow this feature actually targets.
  ///
  /// Returns null when the user cancels — not an error. Throws
  /// [ProfileMediaValidationError] for a file that fails validation (wrong
  /// type or over [verificationDocumentMaxBytes]) so the caller can show the
  /// exact reason instead of a generic failure message.
  Future<XFile?> pickDocument({
    bool allowPdf = false,
    ImageSource source = ImageSource.gallery,
  }) async {
    if (!allowPdf) {
      return pickImage(source: source, maxDimension: documentMaxDimension);
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: verificationDocumentExtensions,
      withData: true,
    );
    final picked = result?.files.singleOrNull;
    if (picked == null) return null;

    final bytes = picked.bytes;
    final error = validatePickedDocument(
      fileName: picked.name,
      sizeBytes: picked.size,
      bytesAvailable: bytes != null,
    );
    if (error != null) throw ProfileMediaValidationError(error);

    final ext = extensionOf(picked.name);
    return XFile.fromData(
      bytes!,
      name: picked.name,
      mimeType: mimeFromExtension(ext),
    );
  }

  /// Pure validation for a picked Aadhaar/PAN file — no plugin or network
  /// dependency, so this is exercised directly in tests without a platform
  /// channel. Returns a user-facing message, or null when the file is fine.
  @visibleForTesting
  static String? validatePickedDocument({
    required String fileName,
    required int sizeBytes,
    required bool bytesAvailable,
  }) {
    if (!bytesAvailable) {
      return "Couldn't read that file. Please try again.";
    }
    if (!verificationDocumentExtensions.contains(extensionOf(fileName))) {
      return 'Please choose an image or PDF file.';
    }
    if (sizeBytes > verificationDocumentMaxBytes) {
      return 'That file is over 20MB. Please choose a smaller file.';
    }
    return null;
  }

  // ── Paths ─────────────────────────────────────────────────────────────────

  /// `{userId}/{timestamp}.{ext}` — mirrors `AvatarUploadModal.tsx:160-161`.
  @visibleForTesting
  static String avatarPath(String userId, String ext, int timestamp) =>
      '$userId/$timestamp.$ext';

  /// `{userId}/{timestamp}_background.{ext}` — mirrors
  /// `BackgroundUploadModal.tsx:157-158`.
  @visibleForTesting
  static String coverPath(String userId, String ext, int timestamp) =>
      '$userId/${timestamp}_background.$ext';

  /// `{userId}/{slug}_{timestamp}.{ext}` — mirrors `EditProfile.tsx:236`.
  @visibleForTesting
  static String documentPath(
    String userId,
    ProfileDocumentKind kind,
    String ext,
    int timestamp,
  ) => '$userId/${kind.slug}_$timestamp.$ext';

  /// `{userId}/profiles/{userId}/{uuid}-original.{ext}` — the portal's own
  /// `imageUploader.ts` path for its `document` preset (`entityType:
  /// "profile"`), so a document this app uploads resolves the same way the
  /// portal's own signed-URL reader (`resolveDocumentUrl`) expects.
  @visibleForTesting
  static String verificationDocumentPath(
    String userId,
    String ext,
    String uuid,
  ) => '$userId/profiles/$userId/$uuid-original.$ext';

  /// Lowercased extension, defaulting to `jpg`.
  ///
  /// A filename with no dot, or a trailing dot, yields `jpg` rather than an empty
  /// extension that would produce a path ending in `.`.
  @visibleForTesting
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'jpg';
    final ext = fileName.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  /// Extension → MIME.
  ///
  /// A self-contained mirror of the mapping the property upload uses. `XFile`'s
  /// own `mimeType` is null on several platforms, and Supabase Storage stores
  /// `application/octet-stream` when no content type is supplied — which makes the
  /// object download instead of render in a browser.
  ///
  /// Image types, plus `pdf` for the Aadhaar/PAN document picker.
  @visibleForTesting
  static String mimeFromExtension(String ext) => switch (ext.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };

  // ── Uploading ─────────────────────────────────────────────────────────────

  /// Uploads [file] to [bucket] at [path] and returns its public URL, or —
  /// when [private] is true — the bare [path] with no URL resolution at all.
  ///
  /// [private] is for [verificationDocumentBucket], which has no public-read
  /// policy: calling `getPublicUrl` against it would return a URL that
  /// cannot actually be fetched. The portal's own `imageUploader.ts` makes
  /// the same choice — it stores the storage path for a private preset and
  /// resolves a signed URL only at display time, never persisting one.
  ///
  /// `upsert: true` so re-uploading the same path replaces rather than 409s. Paths
  /// carry a timestamp so this is belt-and-braces rather than load-bearing.
  Future<String> _upload({
    required String bucket,
    required String path,
    required XFile file,
    bool private = false,
  }) async {
    final bytes = await file.readAsBytes();
    final ext = extensionOf(file.name);

    await _supabase.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: file.mimeType ?? mimeFromExtension(ext),
            upsert: true,
          ),
        );

    if (private) return path;
    return PublicMediaUrl.resolve(
      _supabase.storage.from(bucket).getPublicUrl(path),
    );
  }

  /// Uploads a new avatar and writes `profiles.avatar_url`.
  ///
  /// Returns the public URL. Throws on failure so the caller can tell the user —
  /// a silently failed upload that leaves the old photo in place is worse than an
  /// error, because the user believes it worked.
  ///
  /// The `profiles` write goes through `AuthService.updateProfileFields`, the app's
  /// established writer, rather than a second `.update()` here.
  Future<String> uploadAvatar({
    required String userId,
    required XFile file,
  }) async {
    final url = await _upload(
      bucket: avatarBucket,
      path: avatarPath(
        userId,
        extensionOf(file.name),
        DateTime.now().millisecondsSinceEpoch,
      ),
      file: file,
    );

    await _authService.updateProfileFields(userId, {'avatar_url': url});
    return url;
  }

  /// Uploads a cover photo and writes `profiles.background_image_url`.
  Future<String> uploadCover({
    required String userId,
    required XFile file,
  }) async {
    final url = await _upload(
      bucket: coverBucket,
      path: coverPath(
        userId,
        extensionOf(file.name),
        DateTime.now().millisecondsSinceEpoch,
      ),
      file: file,
    );

    await _authService.updateProfileFields(userId, {
      'background_image_url': url,
    });
    return url;
  }

  /// Uploads a verification document and returns a value the caller stores
  /// **without writing it anywhere**.
  ///
  /// SECURITY FIX (see git history / the incident this closes): Aadhaar and
  /// PAN — [acceptsPdf] kinds — now **always** go to the private
  /// [verificationDocumentBucket], regardless of what [private] the caller
  /// passes. Previously only [EditProfileProvider.pickAndUploadDocument] set
  /// `private: true` for these; the three registration screens (Builder,
  /// Broker, Influencer) never did, so every Aadhaar/PAN uploaded at sign-up
  /// landed in the public [avatarBucket] — readable by anyone with the URL,
  /// no login required (that bucket's own Storage policy grants unauthenticated
  /// `SELECT`). Deciding this here, once, means no call site can get it wrong
  /// again; the five existing call sites (Edit Profile, and Builder/Broker/
  /// Influencer's PAN + Aadhaar-front + Aadhaar-back uploads) are unchanged —
  /// none of them needed to pass `private` correctly in the first place.
  ///
  /// RERA, GST, Registration proof and the Company logo are unaffected: they
  /// keep using whatever [private] the caller passes (always `false` today),
  /// exactly as before. If you decide those should also move to the private
  /// bucket, that is a separate, deliberate follow-up, not bundled here.
  ///
  /// A caller that explicitly passes `private: true` for a *non*-[acceptsPdf]
  /// kind (no current caller does) still goes private too — this only ever
  /// widens privacy, never narrows it below what the caller asked for.
  ///
  /// For an [acceptsPdf] kind, the returned value is a private storage
  /// *path*, not a URL (see [_upload]'s own doc comment for why a path, not a
  /// signed URL, is what gets stored) — unchanged from the existing Edit
  /// Profile behavior this now also applies to registration.
  ///
  /// Five of the six kinds live inside `profiles.social_media`, which must be
  /// written through the merge-preserving path in `ProfileWriteService` — writing
  /// the JSON column from here would replace it and destroy every other key. The
  /// caller stores the returned value and saves it with the rest of the form.
  /// The actual routing decision [uploadDocument] makes, pulled out as a
  /// pure function so it's unit-testable without a real upload (storage
  /// calls need a live Supabase project, so [uploadDocument] itself is not
  /// exercised by [test/profile_media_service_test.dart] — this is).
  @visibleForTesting
  static bool resolvesPrivate({
    required bool callerRequestedPrivate,
    required ProfileDocumentKind kind,
  }) => callerRequestedPrivate || acceptsPdf(kind);

  Future<String> uploadDocument({
    required String userId,
    required ProfileDocumentKind kind,
    required XFile file,
    bool private = false,
  }) async {
    final mustBePrivate = resolvesPrivate(
      callerRequestedPrivate: private,
      kind: kind,
    );

    if (mustBePrivate) {
      return _upload(
        bucket: verificationDocumentBucket,
        path: verificationDocumentPath(
          userId,
          extensionOf(file.name),
          _uuid.v4(),
        ),
        file: file,
        private: true,
      );
    }

    return _upload(
      bucket: avatarBucket,
      path: documentPath(
        userId,
        kind,
        extensionOf(file.name),
        DateTime.now().millisecondsSinceEpoch,
      ),
      file: file,
    );
  }
}
