// models/property_detail_bundle.dart
import 'property_model.dart';

/// Standalone, fully-nullable owner-profile view model for the property
/// detail screen.
///
/// Deliberately its own type rather than a shared profile model: the detail
/// screen selects a narrow `display_name, avatar_url, user_type[, phone],
/// social_media` column list, with phone included only when the caller is
/// signed in, matching the website's PII-aware query. A model requiring
/// non-nullable id/createdAt/updatedAt cannot represent that row.
///
/// (Phase 11 note: this previously referenced `ProfileModel`, an orphaned
/// never-imported file deleted in that phase.)
class PropertyOwnerProfile {
  final String? displayName;
  final String? avatarUrl;
  final String? userType;
  final String? companyName;
  final String? phone;
  final Map<String, dynamic>? socialMedia;

  /// `profiles.comments_enabled` — gates the property Comment input the same
  /// way the website's `property.user_profile?.comments_enabled ?? true`
  /// does. Defaults to true when the column/row is absent.
  final bool commentsEnabled;

  const PropertyOwnerProfile({
    this.displayName,
    this.avatarUrl,
    this.userType,
    this.companyName,
    this.phone,
    this.socialMedia,
    this.commentsEnabled = true,
  });

  factory PropertyOwnerProfile.fromSupabase(Map<String, dynamic> json) {
    return PropertyOwnerProfile(
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      userType: json['user_type']?.toString(),
      companyName: json['company_name']?.toString(),
      phone: json['phone']?.toString(),
      socialMedia: json['social_media'] as Map<String, dynamic>?,
      commentsEnabled: json['comments_enabled'] as bool? ?? true,
    );
  }
}

/// Return type of PropertyService.getPropertyDetail — the property row plus
/// its owner's profile, resolved via the same 3-query shape PropertyDetails
/// .tsx uses on the website.
class PropertyDetailBundle {
  final PropertyModel property;
  final PropertyOwnerProfile? ownerProfile;

  /// This listing's own contact email, from `property_contact_details`
  /// (`MediaContactStep`'s "Email Address" field) — null when the seller
  /// left it blank, or when RLS hides the row from this viewer (mirrors
  /// PropertyDetails.tsx's `effectiveEmail`: visible only to the owner, an
  /// admin, or an already-approved inquirer).
  final String? contactEmail;

  /// This listing's own contact phone override, from the same
  /// `property_contact_details` row (`MediaContactStep`'s "Phone Number"
  /// field) — unlike [contactEmail], this one is meant for every viewer, not
  /// just an approved inquirer (mirrors PropertyDetails.tsx's
  /// `effectivePhone`, which prefers this over the owner's profile phone).
  /// Null when the seller left it blank, falling back to [ownerProfile]'s
  /// phone in that case.
  final String? contactPhone;

  const PropertyDetailBundle({
    required this.property,
    this.ownerProfile,
    this.contactEmail,
    this.contactPhone,
  });
}
