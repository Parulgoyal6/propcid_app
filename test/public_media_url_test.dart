// PublicMediaUrl — rewrites a Supabase Storage getPublicUrl() result onto
// the configured MEDIA_URL host.
//
// What this pins:
//   * a public object URL is rewritten onto MEDIA_URL, with path, encoded
//     characters and query string preserved exactly;
//   * a signed URL, a private-download shape, or an external URL is never
//     rewritten, MEDIA_URL configured or not;
//   * no MEDIA_URL configured (the production case) leaves every URL
//     untouched, rather than erroring;
//   * MEDIA_URL configured but unusable fails loudly instead of handing back
//     a broken media URL that an upload call would otherwise report as a
//     success.
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/utils/public_media_url.dart';

void main() {
  const supabasePublicUrl =
      'https://staging.propcid.in/storage/v1/object/public/'
      'property-media/user/file.jpg';

  group('MEDIA_URL configured', () {
    setUp(() {
      dotenv.loadFromString(
        envString: 'MEDIA_URL=https://media-dev.propcid.com',
      );
    });

    test('rewrites a public object URL onto the configured host', () {
      expect(
        PublicMediaUrl.resolve(supabasePublicUrl),
        'https://media-dev.propcid.com/storage/v1/object/public/'
        'property-media/user/file.jpg',
      );
    });

    test('preserves a query string exactly', () {
      const withQuery =
          'https://staging.propcid.in/storage/v1/object/public/'
          'property-media/user/file.jpg?token=abc&v=2';
      expect(
        PublicMediaUrl.resolve(withQuery),
        'https://media-dev.propcid.com/storage/v1/object/public/'
        'property-media/user/file.jpg?token=abc&v=2',
      );
    });

    test('preserves percent-encoded path characters exactly', () {
      const encoded =
          'https://staging.propcid.in/storage/v1/object/public/'
          'property-media/user%20name/file%20(1).jpg';
      expect(
        PublicMediaUrl.resolve(encoded),
        'https://media-dev.propcid.com/storage/v1/object/public/'
        'property-media/user%20name/file%20(1).jpg',
      );
    });

    test('does not rewrite a signed URL', () {
      const signed =
          'https://staging.propcid.in/storage/v1/object/sign/'
          'documents/user/aadhaar.jpg?token=xyz';
      expect(PublicMediaUrl.resolve(signed), signed);
    });

    test('does not rewrite a URL outside Supabase Storage', () {
      const external = 'https://example.com/some/other/file.jpg';
      expect(PublicMediaUrl.resolve(external), external);
    });

    test('is a no-op if the URL is already on the media host', () {
      const already =
          'https://media-dev.propcid.com/storage/v1/object/public/'
          'property-media/user/file.jpg';
      expect(PublicMediaUrl.resolve(already), already);
    });
  });

  group('MEDIA_URL not configured', () {
    setUp(() {
      // No MEDIA_URL key at all — the production case (R1).
      dotenv.loadFromString(envString: 'SUPABASE_URL=https://apis.propcid.com');
    });

    test('returns the Supabase URL unchanged (production default)', () {
      expect(PublicMediaUrl.resolve(supabasePublicUrl), supabasePublicUrl);
    });
  });

  group('MEDIA_URL blank', () {
    test('a whitespace-only value is treated as not configured', () {
      dotenv.loadFromString(envString: 'MEDIA_URL=   ');
      expect(PublicMediaUrl.resolve(supabasePublicUrl), supabasePublicUrl);
    });
  });

  group('MEDIA_URL misconfigured', () {
    test('throws when the value has no scheme', () {
      dotenv.loadFromString(envString: 'MEDIA_URL=media-dev.propcid.com');
      expect(
        () => PublicMediaUrl.resolve(supabasePublicUrl),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when the value is not http(s)', () {
      dotenv.loadFromString(envString: 'MEDIA_URL=ftp://media-dev.propcid.com');
      expect(
        () => PublicMediaUrl.resolve(supabasePublicUrl),
        throwsA(isA<StateError>()),
      );
    });
  });
}
