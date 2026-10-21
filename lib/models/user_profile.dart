// models/user_profile.dart
//
// A read model over one `profiles` row, for the Public Profile screen.
//
// WHY THIS EXISTS
// ---------------
// The React portal reads `profiles` in ~130 places and each site re-derives the
// same fallbacks inline (`company_name || agency_name || display_name`,
// `bio || company_description`, `rera_number || license_number`, ...). Those
// chains are the portal's *display contract*: get one wrong and Flutter shows a
// different name or a blank field for the same row. They are collected here once
// rather than repeated per widget.
//
// READ-ONLY BY DESIGN
// -------------------
// There is no `toMap()` and no write path. Writes go through
// `AuthService.updateProfileFields()` (Phase 3), which is the app's single
// `profiles` writer. A `toMap()` here would invite a second, competing writer
// and — worse — would make it easy to send `user_type` / `user_role` /
// `is_blocked` / `approval_status`, which the `can_update_profile_fields()`
// BEFORE UPDATE trigger reverts *silently*, producing a save that looks
// successful and changes nothing.
//
// TOLERANT PARSING IS MANDATORY, NOT DEFENSIVE STYLE
// --------------------------------------------------
// Three different column sets reach [UserProfile.fromMap]:
//   * own profile        -> `select('*')`, every column present
//   * signed-in visitor  -> the portal's public list + phone/email/mobile_number
//   * anonymous visitor  -> the portal's public list only
// `email`, `phone` and `mobile_number` are REVOKEd from `anon`
// (20270311000000_profiles_hide_contact_from_anon.sql), so for a logged-out
// viewer those keys are absent from the map entirely — not null, absent. Every
// field therefore reads through a null-tolerant accessor.
//
// JS TRUTHINESS, NOT DART `??`
// ----------------------------
// The portal's fallbacks are JS `||`, where `''` and `0` are falsy. Dart's `??`
// only tests null, so `companyName ?? agencyName` would return an empty string
// where React returns the agency name. The `_firstText` / `_firstNumber` helpers
// below reproduce `||`. This is the same rule `core/utils/profile_completion.dart`
// already encodes in its `_isPresent()`.
import 'package:flutter/foundation.dart';

/// Typed view over `profiles.social_media` (jsonb).
///
/// This column is a bag of ~35 keys whose names differ by role, and the portal
/// reads **two different names for the same value** depending on which file you
/// are in. For example the display page reads `facebook` and the edit form reads
/// `facebook_page_link`; the influencer save path writes `facebook_page_link`
/// while the builder save path writes `facebook`. Neither name is "the" name.
///
/// So every accessor here coalesces across both spellings. Where the two portal
/// files disagree on precedence, the **display page's** order
/// (`pages/UserProfile.tsx`) wins, because this model backs a display screen —
/// then the other spelling is tried, so a value written by either path is still
/// visible. Reading only one spelling would silently hide data for whole roles.
/// One entry in `social_media.document_reviews` — written by an admin
/// reviewing a KYC document (`AdminPanel.tsx`'s `reviewDocument`). Mirrors
/// the portal's `DocumentReviewEntry` interface; `requested_at`/
/// `resubmitted_at`/`reviewed_at` are stored but not modelled here since
/// nothing in this app reads them.
@immutable
class DocumentReviewEntry {
  final String status; // 'reupload_requested' | 'resubmitted' | 'approved'
  final String? reason;

  const DocumentReviewEntry({required this.status, this.reason});

  bool get isReuploadRequested => status == 'reupload_requested';

  static DocumentReviewEntry? fromValue(dynamic value) {
    if (value is! Map) return null;
    final status = value['status']?.toString();
    if (status == null || status.isEmpty) return null;
    return DocumentReviewEntry(
      status: status,
      reason: value['reason']?.toString(),
    );
  }
}

@immutable
class ProfileSocialMedia {
  /// The raw map, kept so a key nothing has modelled yet is still reachable and
  /// so a merge-preserving write (Phase 3) can spread the original.
  final Map<String, dynamic> raw;

  const ProfileSocialMedia(this.raw);

  static const ProfileSocialMedia empty = ProfileSocialMedia(
    <String, dynamic>{},
  );

  factory ProfileSocialMedia.fromValue(dynamic value) {
    if (value is Map) {
      return ProfileSocialMedia(Map<String, dynamic>.from(value));
    }
    return empty;
  }

  bool get isEmpty => raw.isEmpty;
  bool get isNotEmpty => raw.isNotEmpty;

  // ── Social handles ────────────────────────────────────────────────────────
  // UserProfile.tsx:1555 reads `facebook || facebook_page_link`;
  // EditProfile.tsx:190 reads `facebook_page_link || facebook`. Display order
  // wins, both are consulted.

  String? get facebook =>
      _firstText([raw['facebook'], raw['facebook_page_link']]);
  String? get instagram =>
      _firstText([raw['instagram'], raw['instagram_username']]);
  String? get linkedin =>
      _firstText([raw['linkedin'], raw['linkedin_profile_url']]);
  String? get youtube =>
      _firstText([raw['youtube'], raw['youtube_channel_link']]);
  String? get whatsapp => _firstText([raw['whatsapp'], raw['whatsapp_number']]);
  String? get telegram =>
      _firstText([raw['telegram'], raw['telegram_channel_link']]);
  String? get twitter =>
      _firstText([raw['twitter'], raw['twitter_profile_url']]);

  // ── Personal ──────────────────────────────────────────────────────────────

  String? get gender => _firstText([raw['gender']]);

  /// Stored as a `yyyy-MM-dd` string by the portal's `<input type="date">`.
  String? get dob => _firstText([raw['dob']]);

  /// Broker writes `alt_mobile_number`; builder and influencer write
  /// `alternate_mobile` (EditProfile.tsx:365, 381, 395).
  String? get alternateMobile =>
      _firstText([raw['alternate_mobile'], raw['alt_mobile_number']]);

  String? get landmark => _firstText([raw['landmark']]);

  // ── Influencer ────────────────────────────────────────────────────────────

  /// UserProfile.tsx:1378 reads `primary_platform`; EditProfile.tsx:169 reads
  /// `primary_content_platform || primary_platform`.
  String? get primaryPlatform =>
      _firstText([raw['primary_platform'], raw['primary_content_platform']]);

  String? get category => _firstText([raw['category']]);
  String? get audienceType => _firstText([raw['audience_type']]);

  int? get instagramFollowers => _asInt(raw['instagram_followers']);
  int? get youtubeSubscribers => _asInt(raw['youtube_subscribers']);
  int? get facebookFollowers => _asInt(raw['facebook_followers']);
  int? get linkedinFollowers => _asInt(raw['linkedin_followers']);

  num? get basePricingShoutout => _asNum(raw['base_pricing_shoutout']);
  num? get basePricingVideo => _asNum(raw['base_pricing_video']);

  List<String> get contentTypes => _asStringList(raw['content_types']);
  List<String> get preferredPromotionTypes =>
      _asStringList(raw['preferred_promotion_types']);

  // ── Broker ────────────────────────────────────────────────────────────────

  String? get brokerType => _firstText([raw['broker_type']]);
  String? get commissionDetails => _firstText([raw['commission_details']]);
  num? get priceRangeMin => _asNum(raw['price_range_min']);
  num? get priceRangeMax => _asNum(raw['price_range_max']);

  // ── Builder / shared business ─────────────────────────────────────────────

  String? get companyType => _firstText([raw['company_type']]);
  String? get gstNumber => _firstText([raw['gst_number']]);
  String? get panNumber => _firstText([raw['pan_number']]);

  List<String> get projectTypes => _asStringList(raw['project_types']);
  List<String> get areasOfExpertise => _asStringList(raw['areas_of_expertise']);
  List<String> get languagesKnown => _asStringList(raw['languages_known']);

  /// Influencer saves duplicate experience into `social_media`
  /// (EditProfile.tsx:398), and the edit form reads it as a third fallback
  /// behind the two real columns.
  int? get yearsOfExperience => _asInt(raw['years_of_experience']);

  // ── Verification documents ────────────────────────────────────────────────

  String? get reraCertificateUrl => _firstText([raw['rera_certificate_url']]);
  String? get gstCertificateUrl => _firstText([raw['gst_certificate_url']]);
  String? get panCardUrl => _firstText([raw['pan_card_url']]);
  String? get registrationProofUrl =>
      _firstText([raw['registration_proof_url']]);
  String? get aadhaarCardUrl => _firstText([raw['aadhaar_card_url']]);
  String? get aadhaarCardBackUrl =>
      _firstText([raw['aadhaar_card_back_url']]);

  /// Admin's per-document review state, keyed by the same 'rera'/'gst'/'pan'/
  /// 'proof'/'aadhaar' strings `ProfileDocumentKind.slug` already uses — so no
  /// separate key mapping is needed to look one up for a given document kind.
  /// Empty until an admin has reviewed anything for this user.
  Map<String, DocumentReviewEntry> get documentReviews {
    final value = raw['document_reviews'];
    if (value is! Map) return const {};
    final result = <String, DocumentReviewEntry>{};
    value.forEach((key, entry) {
      final parsed = DocumentReviewEntry.fromValue(entry);
      if (parsed != null) result[key.toString()] = parsed;
    });
    return result;
  }

  /// True when any social handle is set — drives whether the profile's social
  /// row renders at all.
  bool get hasAnySocialLink =>
      facebook != null ||
      instagram != null ||
      linkedin != null ||
      youtube != null ||
      whatsapp != null ||
      telegram != null ||
      twitter != null;
}

/// One `profiles` row, as the Public Profile screen needs it.
@immutable
class UserProfile {
  // ── Identity ──────────────────────────────────────────────────────────────
  final String userId;

  /// `profiles.id`. The portal normalises `id = user_id ?? id`
  /// (UserProfile.tsx:346-350) because some call sites receive one and some the
  /// other; [userId] is the authoritative key for every query.
  final String? id;

  final String? displayName;
  final String? username;
  final String? userType;
  final String? userRole;

  // ── Media ─────────────────────────────────────────────────────────────────
  final String? avatarUrl;
  final String? backgroundImageUrl;
  final String? companyLogoUrl;

  // ── Business identity ─────────────────────────────────────────────────────
  final String? companyName;
  final String? agencyName;
  final String? agencyAddress;
  final String? companyDescription;
  final String? bio;
  final String? licenseNumber;
  final String? reraNumber;
  final String? verificationStatus;
  final String? approvalStatus;
  final String? businessHours;

  // ── Contact — absent from the map entirely for anonymous viewers ──────────
  final String? phone;
  final String? mobileNumber;
  final String? email;

  // ── Location ──────────────────────────────────────────────────────────────
  final String? city;
  final String? workCity;
  final String? state;
  final String? pincode;
  final String? officeAddress;

  // ── Web ───────────────────────────────────────────────────────────────────
  final String? website;
  final String? websiteUrl;

  // ── Experience ────────────────────────────────────────────────────────────
  final int? yearsExperience;
  final int? yearsOfExperience;

  // ── Arrays ────────────────────────────────────────────────────────────────
  final List<String> specialization;
  final List<String> operatingCities;
  final List<String> propertyTypes;

  // ── Meta-verified follower counts ─────────────────────────────────────────
  // Mirrored from `social_accounts` by the meta-followers-sync job. Absent from
  // `integrations/supabase/types.ts` (hence the portal's `(supabase as any)`
  // casts), but explicitly GRANTed to `anon` by
  // 20270312000000_social_follower_counts.sql:76-79 — "so logged-out visitors
  // see them too". They are therefore safe to request on every read.
  final int? fbFollowersCount;
  final int? igFollowersCount;
  final int? igFollowsCount;
  final int? igMediaCount;
  final DateTime? socialFollowersSyncedAt;

  // ── Flags / housekeeping ──────────────────────────────────────────────────
  final bool? commentsEnabled;
  final bool? isActive;
  final bool? isBlocked;
  final bool? isOnline;
  final bool? profileComplete;
  final int? profileCompleteness;
  final String? preferredLanguage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastSeenAt;
  final DateTime? lastLoginAt;

  /// Parsed `social_media` jsonb.
  final ProfileSocialMedia socialMedia;

  /// The unmodified row. Kept so `calculateProfileCompletion()` — which takes a
  /// `Map<String, dynamic>` and is already a verified port of the portal's
  /// checklist — can be called without a second fetch or a reverse mapping.
  final Map<String, dynamic> raw;

  const UserProfile({
    required this.userId,
    required this.socialMedia,
    required this.raw,
    this.id,
    this.displayName,
    this.username,
    this.userType,
    this.userRole,
    this.avatarUrl,
    this.backgroundImageUrl,
    this.companyLogoUrl,
    this.companyName,
    this.agencyName,
    this.agencyAddress,
    this.companyDescription,
    this.bio,
    this.licenseNumber,
    this.reraNumber,
    this.verificationStatus,
    this.approvalStatus,
    this.businessHours,
    this.phone,
    this.mobileNumber,
    this.email,
    this.city,
    this.workCity,
    this.state,
    this.pincode,
    this.officeAddress,
    this.website,
    this.websiteUrl,
    this.yearsExperience,
    this.yearsOfExperience,
    this.specialization = const [],
    this.operatingCities = const [],
    this.propertyTypes = const [],
    this.fbFollowersCount,
    this.igFollowersCount,
    this.igFollowsCount,
    this.igMediaCount,
    this.socialFollowersSyncedAt,
    this.commentsEnabled,
    this.isActive,
    this.isBlocked,
    this.isOnline,
    this.profileComplete,
    this.profileCompleteness,
    this.preferredLanguage,
    this.createdAt,
    this.updatedAt,
    this.lastSeenAt,
    this.lastLoginAt,
  });

  /// Builds from any `profiles` row shape — a full `select('*')`, either public
  /// projection, or the map `AuthProvider.profileRow` already holds. Missing keys
  /// are absences, not errors.
  ///
  /// Named `fromMap` rather than `fromSupabase` (the `ArticleSummary`
  /// convention) precisely because the map does not have to come from a fresh
  /// query — `AuthProvider` caches one.
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      // The portal's `id` normalisation, in reverse: whichever of the two is
      // present identifies the user.
      userId: _text(map['user_id']) ?? _text(map['id']) ?? '',
      id: _text(map['id']),
      displayName: _text(map['display_name']),
      username: _text(map['username']),
      userType: _text(map['user_type']),
      userRole: _text(map['user_role']),
      avatarUrl: _text(map['avatar_url']),
      backgroundImageUrl: _text(map['background_image_url']),
      companyLogoUrl: _text(map['company_logo_url']),
      companyName: _text(map['company_name']),
      agencyName: _text(map['agency_name']),
      agencyAddress: _text(map['agency_address']),
      companyDescription: _text(map['company_description']),
      bio: _text(map['bio']),
      licenseNumber: _text(map['license_number']),
      reraNumber: _text(map['rera_number']),
      verificationStatus: _text(map['verification_status']),
      approvalStatus: _text(map['approval_status']),
      businessHours: _text(map['business_hours']),
      phone: _text(map['phone']),
      mobileNumber: _text(map['mobile_number']),
      email: _text(map['email']),
      city: _text(map['city']),
      workCity: _text(map['work_city']),
      state: _text(map['state']),
      pincode: _text(map['pincode']),
      officeAddress: _text(map['office_address']),
      website: _text(map['website']),
      websiteUrl: _text(map['website_url']),
      yearsExperience: _asInt(map['years_experience']),
      yearsOfExperience: _asInt(map['years_of_experience']),
      specialization: _asStringList(map['specialization']),
      operatingCities: _asStringList(map['operating_cities']),
      propertyTypes: _asStringList(map['property_types']),
      fbFollowersCount: _asInt(map['fb_followers_count']),
      igFollowersCount: _asInt(map['ig_followers_count']),
      igFollowsCount: _asInt(map['ig_follows_count']),
      igMediaCount: _asInt(map['ig_media_count']),
      socialFollowersSyncedAt: _asDate(map['social_followers_synced_at']),
      commentsEnabled: _asBool(map['comments_enabled']),
      isActive: _asBool(map['is_active']),
      isBlocked: _asBool(map['is_blocked']),
      isOnline: _asBool(map['is_online']),
      profileComplete: _asBool(map['profile_complete']),
      profileCompleteness: _asInt(map['profile_completeness']),
      preferredLanguage: _text(map['preferred_language']),
      createdAt: _asDate(map['created_at']),
      updatedAt: _asDate(map['updated_at']),
      lastSeenAt: _asDate(map['last_seen_at']),
      lastLoginAt: _asDate(map['last_login_at']),
      socialMedia: ProfileSocialMedia.fromValue(map['social_media']),
      raw: Map<String, dynamic>.unmodifiable(map),
    );
  }

  // ── Derived display values — the portal's fallback chains ─────────────────

  /// Heading shown for this profile.
  ///
  /// `company_name || agency_name || display_name` — UserProfile.tsx:1050.
  /// Note the portal's `<h1>` also carries `className="lowercase"`; that is a
  /// CSS quirk and is deliberately NOT reproduced.
  String? get displayTitle =>
      _firstText([companyName, agencyName, displayName]);

  /// `city || work_city` — UserProfile.tsx:1099.
  String? get effectiveCity => _firstText([city, workCity]);

  /// `bio || company_description` — UserProfile.tsx:1259.
  ///
  /// Note the edit form reads these the other way round
  /// (`company_description || bio`, EditProfile.tsx:148). Display order wins.
  String? get effectiveBio => _firstText([bio, companyDescription]);

  /// `rera_number || license_number`.
  String? get effectiveRera => _firstText([reraNumber, licenseNumber]);

  /// `website || website_url` — UserProfile.tsx:1317 renders `website`; the two
  /// columns are always written together by the portal.
  String? get effectiveWebsite => _firstText([website, websiteUrl]);

  /// `phone || mobile_number` — UserProfile.tsx:1526.
  ///
  /// Always null for an anonymous viewer: both columns are REVOKEd from `anon`,
  /// so neither key reaches [fromMap].
  String? get effectivePhone => _firstText([phone, mobileNumber]);

  /// `office_address || city || work_city` — UserProfile.tsx:1540. Unlike the
  /// phone and email, the address is public.
  String? get effectiveAddress => _firstText([officeAddress, city, workCity]);

  /// `years_experience || years_of_experience`, then the `social_media` copy the
  /// influencer save path writes.
  ///
  /// JS `||` semantics: a stored **0 falls through** to the next candidate,
  /// which is what the portal does. Use [hasExperienceField] to decide whether
  /// to render the row at all — the portal gates on `!== undefined`, so a
  /// genuine 0 still shows a row.
  int? get effectiveExperience => _firstNumber([
    yearsExperience,
    yearsOfExperience,
    socialMedia.yearsOfExperience,
  ])?.toInt();

  /// Presence test matching the portal's `!== undefined` row gate
  /// (UserProfile.tsx:1101), which is *not* the same as [effectiveExperience]
  /// being non-null.
  bool get hasExperienceField =>
      yearsExperience != null ||
      yearsOfExperience != null ||
      socialMedia.yearsOfExperience != null;

  /// The verified badge condition, verbatim from UserProfile.tsx:1038:
  /// `verification_status === 'verified' || license_number || rera_number`.
  ///
  /// Deliberately broader than the existing own-profile header's
  /// `auth.userRole != null`. Aligning that widget is a separate, approval-gated
  /// change (P8-4) — this getter does not alter it.
  bool get isVerified =>
      verificationStatus?.toLowerCase() == 'verified' ||
      licenseNumber != null ||
      reraNumber != null;

  /// Contact PII is present in the row. False for anonymous viewers, and for a
  /// signed-in viewer whose target simply has not filled it in.
  bool get hasContactDetails => effectivePhone != null || email != null;

  // ── Role helpers ──────────────────────────────────────────────────────────

  String get _type => userType?.toLowerCase() ?? '';
  bool get isBuilder => _type == 'builder';
  bool get isBroker => _type == 'broker';
  bool get isInfluencer => _type == 'influencer';

  /// Individual **or** an unrecognised/absent type — the portal treats both the
  /// same way (`profile.user_type !== 'individual'` gates the business cards,
  /// so anything unknown gets the business treatment; but the role *label*
  /// falls back to "Member"). This getter answers the label question.
  bool get isIndividual => !isBuilder && !isBroker && !isInfluencer;

  /// Avatar fallback initials, up to two characters.
  ///
  /// Matches the portal's `getInitials` (UserProfile.tsx:891) in taking the
  /// first letter of each word, and the app's own `SocialProfileMobileNav`
  /// convention in capping at two.
  String get initials {
    final source = displayTitle ?? '';
    final words = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'U';
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? 'U' : letters;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parsing helpers
//
// Private to this file: they encode JS truthiness, which is a portal-parity
// concern rather than a general-purpose utility. Promoting them would invite
// use where Dart's own null-safety is the correct tool.
// ─────────────────────────────────────────────────────────────────────────────

/// A non-blank string, or null. `''` and whitespace-only both become null,
/// because JS treats `''` as falsy and the portal's `||` chains rely on it.
String? _text(dynamic value) {
  if (value == null) return null;
  final s = value is String ? value : value.toString();
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// First non-blank candidate — Dart's stand-in for JS `a || b || c` over strings.
String? _firstText(List<dynamic> candidates) {
  for (final candidate in candidates) {
    final text = _text(candidate);
    if (text != null) return text;
  }
  return null;
}

/// First non-null, non-zero candidate — JS `||` over numbers, where `0` is falsy.
num? _firstNumber(List<dynamic> candidates) {
  for (final candidate in candidates) {
    final n = _asNum(candidate);
    if (n != null && n != 0) return n;
  }
  // Every candidate was absent or zero. Return a real 0 if one was present, so
  // a genuine zero is distinguishable from "no value at all".
  for (final candidate in candidates) {
    final n = _asNum(candidate);
    if (n != null) return n;
  }
  return null;
}

num? _asNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

int? _asInt(dynamic value) => _asNum(value)?.toInt();

bool? _asBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  final s = value.toString().toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return null;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Postgres `text[]` arrives as a `List`. Nulls and blanks inside it are
/// dropped so a caller never renders an empty chip.
List<String> _asStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => _text(e)).whereType<String>().toList(growable: false);
}
