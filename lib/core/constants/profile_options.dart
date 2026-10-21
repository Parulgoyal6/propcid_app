// core/constants/profile_options.dart
//
// Dropdown and chip option sets for the Edit Profile screen.
//
// EVERY LIST HERE IS TRANSCRIBED FROM features/profile/EditProfile.tsx.
// `CLAUDE.md`: "Never invent dropdown values." These reach `profiles` and
// `profiles.social_media`, which the React portal reads — a value that is not in
// the portal's list is a value the portal cannot render or re-select.
//
// APPROVED DECISION 5.1 — React is the long-term vocabulary, and legacy values
// survive. The Flutter registration wizards write a DIFFERENT set of values into
// several of these same columns (`content_types`, `preferred_promotion_types`,
// `category`, `company_type`), so a profile created in the app can hold values
// absent from the lists below. Those are never dropped: the edit screen renders
// any stored value as selected, whether or not it appears here, and only an
// explicit user action removes it. See `EditProfileProvider` and
// `mergeSelection` below.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Shared
// ─────────────────────────────────────────────────────────────────────────────

/// EditProfile.tsx:645-648. Identical to the wizards' list, so no legacy drift.
const List<String> kGenderOptions = <String>[
  'Male',
  'Female',
  'Other',
  'Prefer not to say',
];

/// EditProfile.tsx:607-610. The value written to `profiles.user_type`.
///
/// Presented read-only once set: `can_update_profile_fields()` reverts a change
/// silently, so an editable control would imply something the database refuses.
const List<String> kUserTypeOptions = <String>[
  'builder',
  'broker',
  'individual',
  'influencer',
];

/// EditProfile.tsx:118-124.
const List<({String code, String country})> kCountryCodes =
    <({String code, String country})>[
      (code: '+91', country: 'India'),
      (code: '+1', country: 'USA'),
      (code: '+44', country: 'UK'),
      (code: '+61', country: 'Australia'),
      (code: '+971', country: 'UAE'),
    ];

/// EditProfile.tsx:31-34 — `LANGUAGE_OPTIONS`.
const List<String> kLanguageOptions = <String>[
  'English',
  'Hindi',
  'Marathi',
  'Gujarati',
  'Tamil',
  'Telugu',
  'Kannada',
  'Malayalam',
  'Bengali',
  'Punjabi',
];

/// EditProfile.tsx:25-29 — `EXPERTISE_OPTIONS`.
const List<String> kExpertiseOptions = <String>[
  'Luxury Properties',
  'High-Rise Apartments',
  'Commercial Leasing',
  'Farmhouses & Land',
  'Affordable Housing',
  'First-Time Home Buyers',
  'Industrial Spaces',
  'Real Estate Investment Advisor',
];

// ─────────────────────────────────────────────────────────────────────────────
// Builder
// ─────────────────────────────────────────────────────────────────────────────

/// EditProfile.tsx:719-722.
///
/// The wizard offers six values (adding Public Limited, Proprietorship, Other and
/// dropping Individual). A profile carrying one of those keeps it — see the
/// library note.
const List<String> kCompanyTypeOptions = <String>[
  'Individual',
  'Partnership',
  'LLP',
  'Private Limited',
];

// ─────────────────────────────────────────────────────────────────────────────
// Broker
// ─────────────────────────────────────────────────────────────────────────────

/// EditProfile.tsx:1251-1254.
const List<String> kBrokerTypeOptions = <String>[
  'Independent Broker',
  'Real Estate Agency',
  'Freelancer',
  'Property Consultant',
];

/// Approved decision 5.2 — `profiles.property_types` becomes editable.
///
/// EditProfile.tsx has no input for this column, so there is no React list to
/// transcribe. The values are taken **verbatim from the broker registration
/// wizard** (`broker_registration_screen.dart:46-53`), which is what writes the
/// column today — so editing cannot introduce a value registration would not
/// have produced.
const List<String> kPropertyTypeOptions = <String>[
  'Residential',
  'Commercial',
  'Industrial',
  'Plots',
  'Agricultural',
  'Luxury',
];

// ─────────────────────────────────────────────────────────────────────────────
// Influencer
// ─────────────────────────────────────────────────────────────────────────────

/// EditProfile.tsx:1712-1719.
const List<String> kInfluencerCategoryOptions = <String>[
  'Real Estate Influencer',
  'Lifestyle Creator',
  'YouTuber',
  'Instagram Creator',
  'Blogger',
  'Affiliate Marketer',
  'Property Reviewer',
  'Finance Creator',
];

/// EditProfile.tsx:1733-1737.
const List<String> kPrimaryPlatformOptions = <String>[
  'Instagram',
  'YouTube',
  'Facebook',
  'LinkedIn',
  'Twitter',
];

/// EditProfile.tsx:17-19 — `CONTENT_TYPES_OPTIONS`.
///
/// The wizard writes a different eight (Vlogs, Podcasts, Blog Posts, …). Those
/// survive as legacy selections.
const List<String> kContentTypeOptions = <String>[
  'Reels',
  'Shorts',
  'YouTube Videos',
  'Property Tours',
  'Reviews',
  'Stories',
  'Posts',
  'Live Sessions',
];

/// EditProfile.tsx:21-23 — `PROMOTION_TYPE_OPTIONS`.
const List<String> kPromotionTypeOptions = <String>[
  'Paid Promotion',
  'Affiliate Marketing',
  'Lead Generation',
  'Brand Collaboration',
];

// ─────────────────────────────────────────────────────────────────────────────
// Legacy-preserving selection helpers (approved decision 5.1)
// ─────────────────────────────────────────────────────────────────────────────

/// The chips to render for a multi-select: the canonical [options] plus any
/// [selected] value that is not among them, appended in stored order.
///
/// This is what keeps a wizard-written value on screen. Without it a broker whose
/// `content_types` reads `['Vlogs']` would see nothing selected and save an empty
/// list, silently destroying their answer.
List<String> mergeSelection(List<String> options, Iterable<String> selected) {
  final result = <String>[...options];
  for (final value in selected) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    if (!result.contains(trimmed)) result.add(trimmed);
  }
  return result;
}

/// True when [value] is outside the canonical [options] — a legacy selection.
///
/// The UI marks these so a user understands why the chip cannot be re-added once
/// removed, and so removal reads as deliberate rather than accidental.
bool isLegacyValue(List<String> options, String value) =>
    !options.contains(value.trim());

/// The single-select equivalent: [options] plus [current] when it is not already
/// present, so a legacy dropdown value stays visible and selected instead of the
/// control resetting to null.
List<String> mergeSingle(List<String> options, String? current) {
  final value = current?.trim() ?? '';
  if (value.isEmpty || options.contains(value)) return options;
  return <String>[...options, value];
}
