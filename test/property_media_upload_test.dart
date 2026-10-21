// Property listing media upload — format/size gate for `property-media`.
//
// Root cause fixed here: `PropertyService._uploadMedia` had no pre-upload
// format or size check at all. Property/land videos upload uncompressed (no
// `video_compress` wiring, unlike the influencer video path), so a `.mov`
// clip — the common default on iPhone — reached Supabase Storage
// unconverted, labeled `video/quicktime`, which `property-media`'s real
// `allowed_mime_types` allow-list rejects (only JPEG/PNG/WebP images and
// MP4/MPEG video are accepted). There was also no size check at the service
// layer, even though the bucket's own `file_size_limit` is 50 MB.
//
// The live `uploadBinary` call needs a Supabase session and isn't covered
// here — `PropertyService` doesn't accept an injected client, the same
// boundary every other media-service test in this suite draws. What's
// asserted is every pure decision that feeds that call.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/services/property_service.dart';

void main() {
  group('mimeFromExt (unchanged mapping)', () {
    test('covers the formats this wizard can produce', () {
      expect(PropertyService.mimeFromExt('jpg'), 'image/jpeg');
      expect(PropertyService.mimeFromExt('jpeg'), 'image/jpeg');
      expect(PropertyService.mimeFromExt('png'), 'image/png');
      expect(PropertyService.mimeFromExt('webp'), 'image/webp');
      expect(PropertyService.mimeFromExt('heic'), 'image/heic');
      expect(PropertyService.mimeFromExt('mp4'), 'video/mp4');
      expect(PropertyService.mimeFromExt('mov'), 'video/quicktime');
    });

    test('an unknown extension falls back to octet-stream', () {
      expect(PropertyService.mimeFromExt('xyz'), 'application/octet-stream');
    });
  });

  group('isAcceptedPropertyMediaMimeType', () {
    test('accepts exactly property-media\'s real allow-list — an already-'
        'working upload must keep passing', () {
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('image/jpeg'),
        isTrue,
      );
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('image/png'),
        isTrue,
      );
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('image/webp'),
        isTrue,
      );
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('video/mp4'),
        isTrue,
      );
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('video/mpeg'),
        isTrue,
      );
    });

    test('rejects a .mov video — the exact bug: uncompressed property videos '
        'upload with this content type and the bucket refuses it', () {
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType(
          PropertyService.mimeFromExt('mov'),
        ),
        isFalse,
      );
    });

    test('rejects heic and any other unrecognised format', () {
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType('image/heic'),
        isFalse,
      );
      expect(
        PropertyService.isAcceptedPropertyMediaMimeType(
          'application/octet-stream',
        ),
        isFalse,
      );
    });
  });

  group('maxPropertyMediaBytes', () {
    test('matches the bucket\'s real 50 MB file_size_limit', () {
      expect(PropertyService.maxPropertyMediaBytes, 50 * 1024 * 1024);
    });
  });
}
