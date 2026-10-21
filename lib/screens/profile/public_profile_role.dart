// screens/profile/public_profile_role.dart
//
// Role wording the Public Profile screen needs on top of what the existing
// profile module already provides.
//
// `profile_role.dart` is deliberately NOT modified (approved decision 2). It
// keeps its two functions and its existing callers — `ProfileIdentityBlock` on
// the live own-profile screen — completely untouched.
//
// This file IMPORTS and re-exports those two rather than restating them, so
// there is exactly one definition of role colour and role label in the app. A
// second copy would let the two profile screens drift apart on the one thing
// they most obviously share.
export 'profile_role.dart' show roleColor, roleLabel;

/// The line beneath the display name: "Real Estate Builder", "Real Estate
/// Broker", ...
///
/// Ported from the role subtitle in pages/UserProfile.tsx:1065-1071, which reads
/// `profile_page.role_builder` / `role_broker` / `role_influencer` / `role_user`
/// from the portal's i18n bundle. The English strings below are those keys'
/// values; this app has no i18n layer, so they are inlined the same way every
/// other Flutter screen inlines its copy.
///
/// Note this is NOT the same wording as `formattedUserType()` in
/// core/utils/profile_link.dart, which produces "Real Estate Builder" for the
/// *share message* and falls back to "Real Estate Professional". That function
/// is a port of the portal's share-card helper and has a different fallback, so
/// the two are kept separate rather than one being bent to serve both.
String roleSubtitle(String? userType) {
  switch (userType?.toLowerCase()) {
    case 'builder':
      return 'Real Estate Builder';
    case 'broker':
      return 'Real Estate Broker';
    case 'influencer':
      return 'Real Estate Influencer';
    default:
      return 'PropCid Member';
  }
}

/// The short uppercase word inside the gradient pill beside the name.
///
/// UserProfile.tsx:1053-1059 renders `badge_builder` / `badge_broker` /
/// `badge_influencer` / `badge_user` here — a separate set of keys from the
/// subtitle above, which is why this is not just `roleLabel().toUpperCase()`.
/// The portal's badge for an individual reads "USER"; `roleLabel()` returns
/// "Member". Both are kept, each where the portal puts it.
String roleBadge(String? userType) {
  switch (userType?.toLowerCase()) {
    case 'builder':
      return 'BUILDER';
    case 'broker':
      return 'BROKER';
    case 'influencer':
      return 'INFLUENCER';
    default:
      return 'MEMBER';
  }
}

/// Label for the listings section and its stat tile.
///
/// Builders publish projects, everyone else publishes listings
/// (UserProfile.tsx:1619-1625 switches the tab label the same way).
String contentLabel(String? userType, {required bool plural}) {
  final isBuilder = userType?.toLowerCase() == 'builder';
  if (isBuilder) return plural ? 'Projects' : 'Project';
  return plural ? 'Listings' : 'Listing';
}
