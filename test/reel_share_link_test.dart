// Reel sharing — the shared text must carry a link.
//
// `shareMessage` used to end on "Discover more premium properties on PropCID."
// and nothing else, so the share sheet opened with a wall of text and no URL.
// Nothing failed and nothing logged; the message just wasn't actionable.
//
// The link rule is `ReelView.handleShare` (`ReelView.tsx:542-547`): a
// property-backed reel shares that property's page, everything else shares the
// reels feed. Slug rule is `toSlug` in `src/lib/seoSlug.ts`. Both read from the
// reference repo at `c:\Users\USER\Desktop\Flutter\propcid`.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/utils/profile_link.dart';
import 'package:propcid_app/models/reel_model.dart';

ReelModel _reel({String? propertyId, String title = 'Sea View 3BHK'}) =>
    ReelModel.fromSupabase({
      'id': 'v-1',
      'title': title,
      'description': '',
      'video_url': 'https://cdn.test/v-1.mp4',
      'property_id': propertyId,
      if (propertyId != null)
        '_property': <String, dynamic>{'price': '2.4 Cr', 'location': 'Bandra'},
    });

void main() {
  group('seoSlug', () {
    test('lowercases and hyphenates, matching toSlug', () {
      expect(seoSlug('Sea View 3BHK'), 'sea-view-3bhk');
      // Runs of non-alphanumerics collapse to one hyphen, and the ends trim.
      expect(seoSlug('  Luxury -- Villa!!  '), 'luxury-villa');
    });

    test('folds accents rather than dropping the letter', () {
      // `.normalize('NFKD')` + strip-marks on the web; the folding table here.
      // Dropping the char instead would give "jos-villa".
      expect(seoSlug('José Villa'), 'jose-villa');
    });

    test('falls back to "item" when nothing survives', () {
      expect(seoSlug(null), 'item');
      expect(seoSlug(''), 'item');
      expect(seoSlug('!!!'), 'item');
    });

    test('caps at 80 characters and never ends on a hyphen', () {
      final slug = seoSlug('a ${'long ' * 40}tail');
      expect(slug.length, lessThanOrEqualTo(80));
      expect(slug.endsWith('-'), isFalse);
    });

    test('is not the same rule as profileSlug', () {
      // profilePath strips separators; SEO paths keep them. Collapsing the two
      // would silently change every profile URL.
      expect(seoSlug('Komal Pal'), 'komal-pal');
      expect(profileSlug('Komal Pal'), 'komalpal');
    });
  });

  group('ReelModel.shareUrl', () {
    test('a property-backed reel links to that property', () {
      final url = _reel(propertyId: 'p-7').shareUrl;
      expect(url, 'https://propcid.com/property/p-7/sea-view-3bhk');
    });

    test('an unlinked reel falls back to the feed, not a dead per-reel URL', () {
      // The portal registers `/property-reels` as a whole-feed route and has no
      // `/reel/:id`, so an id-scoped link would 404.
      expect(_reel().shareUrl, 'https://propcid.com/property-reels');
      expect(_reel(propertyId: '').shareUrl, 'https://propcid.com/property-reels');
    });

    test('is always absolute', () {
      for (final reel in [_reel(), _reel(propertyId: 'p-7')]) {
        expect(reel.shareUrl, startsWith('https://'));
      }
    });
  });

  group('ReelModel.shareMessage', () {
    test('carries the link — the whole point of sharing', () {
      final reel = _reel(propertyId: 'p-7');
      expect(reel.shareMessage, contains(reel.shareUrl));
    });

    test('carries a link even when the reel has no property at all', () {
      final reel = _reel();
      expect(reel.shareMessage, contains('https://propcid.com/property-reels'));
    });

    test('ends on the URL so link preview unfurls pick it up', () {
      final reel = _reel(propertyId: 'p-7');
      expect(reel.shareMessage.trimRight(), endsWith(reel.shareUrl));
    });

    test('still leads with the title and keeps the existing body', () {
      final reel = _reel(propertyId: 'p-7');
      expect(reel.shareMessage, startsWith('🏡 Sea View 3BHK'));
      expect(reel.shareMessage, contains('2.4 Cr'));
      expect(
        reel.shareMessage,
        contains('Discover more premium properties on PropCID.'),
      );
    });
  });
}
