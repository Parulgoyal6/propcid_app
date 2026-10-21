/// Public profile URLs and the QR image that encodes them.
///
/// Ported from `profileSlug` / `profilePath` in the React portal's
/// `utils/utility.ts` and the share/QR URLs in
/// `features/profile/ProfileShareModal.tsx` — see blueprint §16.10. The scheme
/// is not invented here; a mismatch would produce links that 404.
library;

/// Canonical origin. The portal serves `propcid.in` as an alternate domain but
/// treats `.com` as canonical (`components/SEO.tsx`).
const String kProfileOrigin = 'https://propcid.com';

/// Common accented Latin characters folded to their base letter.
///
/// React calls `.normalize('NFKD')` and strips the combining marks, so "José"
/// becomes "jose". Dart's core library has no NFKD, and simply dropping
/// non-alphanumerics would yield "jos" instead — a different slug. This table
/// reproduces the web result for the characters that realistically appear in
/// names.
const Map<String, String> _accentFolding = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ž': 'z',
};

/// Lowercase, accent-folded, alphanumerics only, capped at 40 characters.
///
/// Mirrors `profileSlug`. Note it keeps **no separators** — "Komal Pal"
/// becomes "komalpal", not "komal-pal".
String profileSlug(String? value) {
  if (value == null || value.isEmpty) return '';

  final folded = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    folded.write(_accentFolding[char] ?? char);
  }

  final cleaned = folded.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40);
}

/// Canonical profile path, mirroring `profilePath`:
/// `/profile/{role}/{nameSlug}/{userId}`, with the documented fallbacks when
/// the role or name is unknown.
String profilePath({required String? userId, String? name, String? role}) {
  if (userId == null || userId.isEmpty) return '/profile';

  final roleSeg = profileSlug(role);
  final nameSlug = profileSlug(name);

  if (roleSeg.isNotEmpty) {
    return '/profile/$roleSeg/${nameSlug.isEmpty ? 'user' : nameSlug}/$userId';
  }
  return nameSlug.isEmpty ? '/profile/$userId' : '/profile/$userId/$nameSlug';
}

/// Absolute, shareable profile URL.
String profileShareUrl({required String? userId, String? name, String? role}) =>
    '$kProfileOrigin${profilePath(userId: userId, name: name, role: role)}';

/// Lowercase, hyphenated, ASCII slug — a 1:1 port of `toSlug` in
/// `src/lib/seoSlug.ts`, including its `'item'` fallback and 80-char cap.
///
/// Distinct from [profileSlug] on purpose: that one strips separators entirely
/// ("Komal Pal" → "komalpal") because `profilePath` is specified that way, while
/// SEO paths keep hyphens ("Sea View 3BHK" → "sea-view-3bhk"). Two rules,
/// because the portal has two rules.
String seoSlug(String? text) {
  final folded = StringBuffer();
  for (final char in (text ?? '').toLowerCase().split('')) {
    folded.write(_accentFolding[char] ?? char);
  }

  var slug = folded
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  if (slug.length > 80) slug = slug.substring(0, 80);
  slug = slug.replaceAll(RegExp(r'-+$'), '');

  return slug.isEmpty ? 'item' : slug;
}

/// Absolute URL for a property detail page — `propertyPath` in `seoSlug.ts`.
String propertyShareUrl(String id, {String? title}) =>
    title == null || title.isEmpty
    ? '$kProfileOrigin/property/$id'
    : '$kProfileOrigin/property/$id/${seoSlug(title)}';

/// Absolute URL for a builder project's public page — `projectPath` in
/// `seoSlug.ts`, same id+slug shape as [propertyShareUrl].
String projectShareUrl(String id, {String? title}) =>
    title == null || title.isEmpty
    ? '$kProfileOrigin/project/$id'
    : '$kProfileOrigin/project/$id/${seoSlug(title)}';

/// Where the portal points the reels feed. `App.tsx:208`.
const String kReelsFeedPath = '/property-reels';

/// Absolute URL for a single reel/video — `reelPath` in `seoSlug.ts`. The
/// portal's `/property-reels/:id` and `/property-reels/:id/:slug` routes
/// (`App.tsx`) pin the feed to this exact reel (`ReelView`'s `pathReelId`),
/// the same link `ReelView.handleShare` builds on web — always keyed on the
/// reel's own id, regardless of whether it's backed by a property.
String reelShareUrl(String id, {String? title}) =>
    title == null || title.isEmpty
    ? '$kProfileOrigin$kReelsFeedPath/$id'
    : '$kProfileOrigin$kReelsFeedPath/$id/${seoSlug(title)}';

/// QR image for [shareUrl].
///
/// The portal does not render QR codes locally either — it points an `<img>`
/// at this same endpoint. Reusing it keeps the two platforms identical and
/// needs no QR package on mobile.
String profileQrImageUrl(String shareUrl, {int size = 320}) {
  final encoded = Uri.encodeComponent(shareUrl);
  return 'https://api.qrserver.com/v1/create-qr-code/'
      '?size=${size}x$size&data=$encoded';
}

/// Role wording used in the shared message, from `getFormattedUserType` in
/// ProfileShareModal.tsx.
String formattedUserType(String? userType) {
  switch (userType?.toLowerCase()) {
    case 'builder':
      return 'Real Estate Builder';
    case 'broker':
      return 'Real Estate Broker';
    case 'influencer':
      return 'Real Estate Influencer';
    case 'seller':
      return 'Property Seller';
    default:
      return 'Real Estate Professional';
  }
}

/// The message body shared alongside the link.
///
/// Follows the structure of `shareText` in ProfileShareModal.tsx — headline,
/// verified role, optional location and rating, then the URL. The web version
/// also attaches a generated visiting-card PNG; that canvas rendering is not
/// part of this workstream, so the mobile share is text plus link.
String profileShareMessage({
  required String name,
  required String? userType,
  required String shareUrl,
  String? city,
  double? rating,
  int? reviewsCount,
}) {
  final buffer = StringBuffer()
    ..writeln(name)
    ..write('PropCID Verified ${formattedUserType(userType)}');

  if (city != null && city.trim().isNotEmpty) {
    buffer.write('\n📍 Location: ${city.trim()}');
  }
  if (rating != null && rating > 0) {
    buffer.write(
      '\n⭐ Rating: ${rating.toStringAsFixed(1)} (${reviewsCount ?? 0} reviews)',
    );
  }

  buffer
    ..write('\n\n🔗 View Full Profile & Contact:\n')
    ..write(shareUrl);

  return buffer.toString();
}
