// Feature 4 — Aadhaar/PAN accept a PDF as well as an image.
//
// `ProfileMediaService.pickDocument`/`uploadDocument` already have their own
// pure-logic coverage (bucket/path/MIME/size validation) in
// `profile_media_service_test.dart`. What this file pins is the provider
// wiring around them: `EditProfileProvider.pickAndUploadDocument` passes the
// right `kind` through, stores whatever the service returns without
// assuming it is a URL, and turns a `ProfileMediaValidationError` into its
// exact message instead of the generic "Upload failed" fallback.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/edit_profile_provider.dart';
import 'package:propcid_app/services/profile_media_service.dart';
import 'package:propcid_app/services/profile_write_service.dart';
import 'package:propcid_app/services/user_profile_service.dart';

class _FakeProfileService extends UserProfileService {
  _FakeProfileService(this.profile);
  final UserProfile? profile;

  @override
  Future<UserProfile?> fetchOwn(String userId) async => profile;
}

class _NoopWriteService extends ProfileWriteService {
  @override
  Future<void> saveProfile({
    required String userId,
    required Map<String, dynamic> columns,
    required Map<String, dynamic> socialMediaExisting,
    required Map<String, dynamic> socialMediaChanges,
  }) async {}
}

/// Records what [EditProfileProvider.pickAndUploadDocument] passed through —
/// [pickDocument]'s `allowPdf` and [uploadDocument]'s `kind`/`private` —
/// and returns a preprogrammed result — a bare storage path for the private
/// kinds, a public URL for the rest, exactly as the real service's contract
/// is.
class _FakeMediaService extends ProfileMediaService {
  bool? lastAllowPdf;
  ProfileDocumentKind? lastUploadedKind;
  bool? lastUploadedPrivate;
  Object? throwOnPick;
  String uploadResult = 'u-1/profiles/u-1/uuid-original.pdf';

  @override
  Future<XFile?> pickDocument({
    bool allowPdf = false,
    ImageSource source = ImageSource.gallery,
  }) async {
    lastAllowPdf = allowPdf;
    final toThrow = throwOnPick;
    if (toThrow != null) throw toThrow;
    return XFile.fromData(
      Uint8List.fromList(const [1, 2, 3]),
      name: 'doc.pdf',
      mimeType: 'application/pdf',
    );
  }

  @override
  Future<String> uploadDocument({
    required String userId,
    required ProfileDocumentKind kind,
    required XFile file,
    bool private = false,
  }) async {
    lastUploadedKind = kind;
    lastUploadedPrivate = private;
    return uploadResult;
  }
}

UserProfile _influencerRow() => UserProfile.fromMap(<String, dynamic>{
  'user_id': 'u-1',
  'display_name': 'Asha Menon',
  'user_type': 'influencer',
  'social_media': <String, dynamic>{},
});

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

  Future<({EditProfileProvider provider, _FakeMediaService media})>
  load() async {
    final media = _FakeMediaService();
    final provider = EditProfileProvider(
      profileService: _FakeProfileService(_influencerRow()),
      writeService: _NoopWriteService(),
      mediaService: media,
    );
    await provider.load('u-1');
    return (provider: provider, media: media);
  }

  test('aadhaar/pan opt into allowPdf and the private bucket', () async {
    final ctx = await load();
    final error = await ctx.provider.pickAndUploadDocument(
      ProfileDocumentKind.aadhaar,
    );

    expect(error, isNull);
    expect(ctx.media.lastAllowPdf, isTrue);
    expect(ctx.media.lastUploadedKind, ProfileDocumentKind.aadhaar);
    expect(ctx.media.lastUploadedPrivate, isTrue);
  });

  test(
    'every other kind keeps the exact pre-feature behaviour: image only, public bucket',
    () async {
      // Not aadhaar/pan — registration screens and this same provider for
      // rera/gst/proof/logo must see zero behaviour change from this
      // feature. `acceptsPdf` is the single source of truth for that split.
      final ctx = await load();
      final error = await ctx.provider.pickAndUploadDocument(
        ProfileDocumentKind.rera,
      );

      expect(error, isNull);
      expect(ctx.media.lastAllowPdf, isFalse);
      expect(ctx.media.lastUploadedPrivate, isFalse);
    },
  );

  test(
    'stores whatever the service returns without assuming it is a URL',
    () async {
      final ctx = await load();
      ctx.media.uploadResult = 'u-1/profiles/u-1/some-uuid-original.pdf';

      await ctx.provider.pickAndUploadDocument(ProfileDocumentKind.pan);

      // A bare storage path, not a public URL — the provider must not
      // reject, rewrite, or otherwise assume the shape of this value.
      expect(
        ctx.provider.documentUrl(ProfileDocumentKind.pan),
        'u-1/profiles/u-1/some-uuid-original.pdf',
      );
    },
  );

  test('a ProfileMediaValidationError surfaces its exact message', () async {
    final ctx = await load();
    ctx.media.throwOnPick = ProfileMediaValidationError(
      'That file is over 20MB. Please choose a smaller file.',
    );

    final error = await ctx.provider.pickAndUploadDocument(
      ProfileDocumentKind.pan,
    );

    expect(error, 'That file is over 20MB. Please choose a smaller file.');
  });

  test('an unrelated failure still falls back to a generic message', () async {
    final ctx = await load();
    ctx.media.throwOnPick = StateError('network blip');

    final error = await ctx.provider.pickAndUploadDocument(
      ProfileDocumentKind.pan,
    );

    expect(error, 'Upload failed. Please try again.');
  });

  test('cancelling the picker (null) is a no-op, not an error', () async {
    final media = _CancellingMediaService();
    final provider = EditProfileProvider(
      profileService: _FakeProfileService(_influencerRow()),
      writeService: _NoopWriteService(),
      mediaService: media,
    );
    await provider.load('u-1');

    final error = await provider.pickAndUploadDocument(
      ProfileDocumentKind.aadhaar,
    );

    expect(error, isNull);
    expect(provider.documentUrl(ProfileDocumentKind.aadhaar), isNull);
    expect(media.uploadCalled, isFalse);
  });
}

class _CancellingMediaService extends ProfileMediaService {
  bool uploadCalled = false;

  @override
  Future<XFile?> pickDocument({
    bool allowPdf = false,
    ImageSource source = ImageSource.gallery,
  }) async => null;

  @override
  Future<String> uploadDocument({
    required String userId,
    required ProfileDocumentKind kind,
    required XFile file,
    bool private = false,
  }) async {
    uploadCalled = true;
    return 'unused';
  }
}
