// core/constants/influencer_video_options.dart
//
// The vocabulary of the influencer video form, taken from the portal's
// `InfluencerVideoModal.tsx`.
//
// `video_type` is the only one of these the database constrains:
//
//   video_type TEXT NOT NULL CHECK (video_type IN
//     ('property_listing', 'property_news', 'property_education'))
//
// — 20250828001551_a8c692e2…sql:14. The modal offers exactly those three
// (InfluencerVideoModal.tsx:47-50), titles and descriptions included, so this is a
// straight transcription rather than a choice.
//
// `status` is CHECK-constrained to ('active','inactive','pending') and defaults to
// 'active'; `approval_status` is a bare text column defaulting to 'pending', added
// later by 20251213104811. Neither is offered as a control anywhere in the portal's
// influencer flow — the modal writes `approval_status: 'pending'` and never touches
// `status` — so this file only supplies their *labels*.

/// One selectable video type, with the copy the portal shows beside it.
class InfluencerVideoType {
  const InfluencerVideoType({
    required this.id,
    required this.title,
    required this.description,
  });

  /// The exact string written to `influencer_videos.video_type`.
  final String id;

  /// The radio row's heading.
  final String title;

  /// The one-line explanation under it.
  final String description;
}

/// The three CHECK values, in the modal's order (InfluencerVideoModal.tsx:47-50).
const List<InfluencerVideoType> kInfluencerVideoTypes = [
  InfluencerVideoType(
    id: 'property_listing',
    title: 'Property Listing Video',
    description: 'Showcase a specific property',
  ),
  InfluencerVideoType(
    id: 'property_news',
    title: 'Property News',
    description: 'Share market updates and news',
  ),
  InfluencerVideoType(
    id: 'property_education',
    title: 'Property Education',
    description: 'Educational content about real estate',
  ),
];

/// Whether [id] is one of the three the CHECK constraint accepts.
///
/// Guards the payload rather than the picker: a value from outside this list is a
/// `23514`, so it is worth refusing before the round trip.
bool isValidInfluencerVideoType(String? id) =>
    kInfluencerVideoTypes.any((t) => t.id == id);

/// Title-cased label for a stored `video_type`.
///
/// Falls back to the raw value with underscores expanded, which is what the portal
/// renders (`video.video_type.replace('_', ' ')` with a `capitalize` class,
/// InfluencerContentManager.tsx:188-190).
String influencerVideoTypeLabel(String? id) {
  for (final type in kInfluencerVideoTypes) {
    if (type.id == id) return type.title;
  }
  final raw = (id ?? '').replaceAll('_', ' ').trim();
  if (raw.isEmpty) return 'Video';
  return raw
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Label for `approval_status`, matching `getApprovalBadge`
/// (InfluencerContentManager.tsx:118-127). Anything unrecognised — including the
/// NULL that pre-20251213 rows can still hold — reads as pending review.
String influencerApprovalLabel(String? approvalStatus) =>
    switch (approvalStatus) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => 'Pending Review',
    };

/// Label for `status`, matching `getStatusBadge`
/// (InfluencerContentManager.tsx:100-113). The portal prints the raw value; these
/// are its title-cased forms, since the app capitalises its badges everywhere else.
String influencerVideoStatusLabel(String? status) => switch (status) {
  'active' => 'Active',
  'inactive' => 'Inactive',
  'pending' => 'Pending',
  _ => 'Draft',
};

// ── Property Listing Video fields ────────────────────────────────────────
//
// Only meaningful (and required) when `videoType == 'property_listing'`.
// Every constant below is copied verbatim from
// `backend/functions/influencer-video-save/index.ts`, which is the only
// thing that writes these columns — the values, casing and limits here are
// a contract, not a style choice. In particular `'pg/Co-living'` is exactly
// how the DB CHECK constraint spells it (lowercase `pg`, a slash, capital
// `C`); anything else is a `23514` from Postgres.

/// The 5 values `influencer_videos.property_category`'s CHECK accepts.
const List<String> kPropertyListingCategories = [
  'residential',
  'commercial',
  'pg/Co-living',
  'land',
  'others',
];

/// Display label for a category value — the CHECK values above aren't all
/// human-readable as-is (`pg/Co-living` needs no change, but this keeps
/// every label in one place rather than scattering `switch`es).
String propertyListingCategoryLabel(String value) => switch (value) {
  'residential' => 'Residential',
  'commercial' => 'Commercial',
  'pg/Co-living' => 'PG/Co-living',
  'land' => 'Land',
  'others' => 'Others',
  _ => value,
};

/// The 3 values `influencer_videos.property_listing_type`'s CHECK accepts.
const List<String> kPropertyListingTypes = ['sale', 'rent', 'lease'];

String propertyListingTypeLabel(String value) => switch (value) {
  'sale' => 'Sale',
  'rent' => 'Rent',
  'lease' => 'Lease',
  _ => value,
};

/// Categories that show Bedrooms/Bathrooms — matches the portal's own
/// distinction between a livable unit (residential, PG/co-living) and a
/// category where a bedroom count is meaningless (commercial, land, others).
bool propertyCategoryHasBedBath(String? category) =>
    category == 'residential' || category == 'pg/Co-living';

/// `influencer-video-save`'s exact length/range limits, so client-side
/// validation refuses the same inputs the edge function would 400 on,
/// instead of round-tripping to find out.
const int kPropertyLocationMaxLength = 200;
const int kPropertyPriceMaxLength = 50;
const int kPropertyAreaMaxLength = 50;
const int kPropertyBedBathMax = 20;
const int kVideoTitleMaxLength = 200;
const int kVideoDescriptionMaxLength = 2000;
const int kMaxHashtags = 20;
const int kMaxHashtagLength = 50;

/// Digits only, matching `PRICE_PATTERN = /^\d+$/` — a whole number of
/// rupees, no decimals, no currency symbol, no separators.
final RegExp kPropertyPricePattern = RegExp(r'^\d+$');

/// `AREA_PATTERN = /^\d+(\.\d+)?$/` — a plain number, optionally decimal.
final RegExp kPropertyAreaPattern = RegExp(r'^\d+(\.\d+)?$');

/// Splits a comma-separated hashtag field the way the portal does.
///
/// `InfluencerVideoModal.tsx:154-158`, step for step: split on commas, trim,
/// lowercase, strip one leading `#`, drop the empties. Note what it does *not* do —
/// no deduplication, no length cap, no character filtering — so neither does this.
/// A user who types `#Pune, pune` gets two identical tags on both platforms.
List<String> parseInfluencerHashtags(String raw) => raw
    .split(',')
    .map((tag) => tag.trim().toLowerCase())
    .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
    .where((tag) => tag.isNotEmpty)
    .toList(growable: false);

/// Renders a stored hashtag list back into the form's single text field.
///
/// The inverse of [parseInfluencerHashtags], and the portal's own edit seed:
/// `editingVideo?.hashtags?.join(', ')` (InfluencerVideoModal.tsx:32).
String joinInfluencerHashtags(List<String> hashtags) => hashtags.join(', ');
