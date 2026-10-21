// Project video upload — format gate for `project-media`.
//
// Root cause fixed here: `ProjectMediaService.uploadVideo` had no pre-upload
// format check. Project videos upload uncompressed (no `video_compress`
// wiring here either), so a `.mov` clip reached Supabase Storage unconverted,
// labeled `video/quicktime`, which `project-media`'s real `allowed_mime_types`
// allow-list rejects (`video/mp4` only for video). `uploadImage`/`uploadLogo`/
// `uploadMasterLayout` are untouched — their only source is `image_picker`
// with resize params, which always re-encodes to JPEG/PNG regardless of the
// original format (verified against the plugin's own iOS/Android source), so
// there was nothing for them to fail on.
//
// The live `uploadBinary` call needs a Supabase session and isn't covered
// here, the same boundary this suite's other media-service tests draw — the
// format-gate test below relies on the check throwing before any network
// call, which is exactly the fix's shape (reject before the round trip).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/services/project_media_service.dart';

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

  group('mimeFromName (unchanged mapping)', () {
    test('covers every format the wizard can produce', () {
      expect(ProjectMediaService.mimeFromName('a.jpg'), 'image/jpeg');
      expect(ProjectMediaService.mimeFromName('a.png'), 'image/png');
      expect(ProjectMediaService.mimeFromName('a.webp'), 'image/webp');
      expect(ProjectMediaService.mimeFromName('a.gif'), 'image/gif');
      expect(ProjectMediaService.mimeFromName('a.pdf'), 'application/pdf');
      expect(ProjectMediaService.mimeFromName('a.mp4'), 'video/mp4');
      expect(ProjectMediaService.mimeFromName('a.mov'), 'video/quicktime');
    });
  });

  group('uploadVideo format gate', () {
    test('a mov clip maps to a content type project-media\'s allow-list does '
        'not include', () {
      // project-media's real allowed_mime_types for video is video/mp4
      // only (confirmed against
      // 20270420000100_restrict_public_bucket_mime_types.sql) — mov's
      // video/quicktime is not in it.
      expect(ProjectMediaService.mimeFromName('clip.mov'), isNot('video/mp4'));
    });

    test('uploadVideo throws ProjectMediaException before any network call '
        'for a non-mp4 file', () {
      expect(
        () => ProjectMediaService().uploadVideo(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'clip.mov',
        ),
        throwsA(isA<ProjectMediaException>()),
      );
    });
  });

  group('extension parsing / paths (unchanged)', () {
    test('videoPrefix is project-videos, matching the portal', () {
      expect(ProjectMediaService.videoPrefix, 'project-videos');
    });
  });
}
