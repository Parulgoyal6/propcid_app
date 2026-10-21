// Influencer video upload — MP4/MOV extension & content-type consistency.
//
// Root cause fixed here: `InfluencerMediaService.uploadVideo` always derived
// the uploaded file's extension/content-type from the *original* picked
// file's name, even when `video_compress` (which always outputs an MP4
// container — see its own README) had actually produced different, real MP4
// bytes. A compressed `.mov` selection therefore still uploaded labeled
// `video/quicktime`, which `property-media`'s Storage `allowed_mime_types`
// allow-list rejects (only `video/mp4`/`video/mpeg` are accepted) even
// though the bytes themselves were fine. When compression instead fell back
// to the original bytes, an unsupported original extension (e.g. `.mov`)
// was never rejected before the upload attempt either.
//
// The live `uploadBinary` call needs a Supabase session and isn't covered
// here — the same boundary `article_media_service_test.dart` and
// `profile_media_service_test.dart` draw. What's asserted is every pure
// decision that feeds that call: the extension/MIME mapping, and the new
// `resolveUploadFileName`/`isAcceptedVideoFileName` helpers the fix added.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/services/influencer_media_service.dart';

void main() {
  group('resolveUploadFileName', () {
    test(
      'a compressed .mov selection uploads as .mp4 — the actual bug fix',
      () {
        final name = InfluencerMediaService.resolveUploadFileName(
          originalFileName: 'holiday_clip.mov',
          compressedToMp4: true,
        );
        expect(name, 'holiday_clip.mp4');
        expect(
          InfluencerMediaService.mimeFromName(name),
          'video/mp4',
          reason:
              'the uploaded content-type must describe the real MP4 '
              'bytes, not the original .mov extension',
        );
      },
    );

    test('an already-.mp4 selection that compresses stays .mp4 — unchanged '
        'path for an already-accepted upload', () {
      final name = InfluencerMediaService.resolveUploadFileName(
        originalFileName: 'clip.mp4',
        compressedToMp4: true,
      );
      expect(name, 'clip.mp4');
    });

    test('a name with no extension still gets a clean .mp4 suffix', () {
      final name = InfluencerMediaService.resolveUploadFileName(
        originalFileName: 'clip',
        compressedToMp4: true,
      );
      expect(name, 'clip.mp4');
    });

    test('when compression did not produce MP4 bytes, the original name is '
        'kept untouched (the fallback-bytes case)', () {
      final name = InfluencerMediaService.resolveUploadFileName(
        originalFileName: 'holiday_clip.mov',
        compressedToMp4: false,
      );
      expect(name, 'holiday_clip.mov');
    });
  });

  group('isAcceptedVideoFileName', () {
    test('mp4 and mpeg are accepted — property-media\'s real allow-list', () {
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.mp4'),
        isTrue,
      );
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.mpeg'),
        isTrue,
      );
    });

    test('mov is rejected — not in the bucket\'s allow-list', () {
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.mov'),
        isFalse,
      );
    });

    test('other unrelated formats are rejected too', () {
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.webm'),
        isFalse,
      );
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.avi'),
        isFalse,
      );
      expect(
        InfluencerMediaService.isAcceptedVideoFileName('clip.mkv'),
        isFalse,
      );
    });
  });

  group('mimeFromName (unchanged mapping, still exercised by the fix)', () {
    test('covers the formats this form actually produces', () {
      expect(InfluencerMediaService.mimeFromName('a.mp4'), 'video/mp4');
      expect(InfluencerMediaService.mimeFromName('a.mpeg'), 'video/mpeg');
      expect(InfluencerMediaService.mimeFromName('a.mov'), 'video/quicktime');
      expect(InfluencerMediaService.mimeFromName('a.jpg'), 'image/jpeg');
      expect(InfluencerMediaService.mimeFromName('a.png'), 'image/png');
      expect(InfluencerMediaService.mimeFromName('a.webp'), 'image/webp');
    });
  });

  group('bucket/size constants (unchanged)', () {
    test('shares property-media, at the real 50 MB ceiling', () {
      expect(InfluencerMediaService.bucket, 'property-media');
      expect(InfluencerMediaService.maxVideoBytes, 50 * 1024 * 1024);
    });
  });
}
