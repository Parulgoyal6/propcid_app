// Value-alias maps for the listing migration (final-architecture-review Q13).
//
// Flutter shipped enum values that differ from React's canonical strings. Rows
// already in Postgres carry the Flutter spelling, so switching the app to the
// canonical values would orphan them: web filters would stop matching, and
// React's isApartment/isHouse branching would apply the wrong field set and
// validation when an old listing is opened for edit.
//
// These maps are READ-TIME aliases: legacy value in, canonical value out. They
// let the app adopt canonical values for new writes without a data migration
// (which CLAUDE.md forbids without explicit instruction).
//
// Unlike listing_constants.dart / listing_field_keys.dart, this file is NOT
// generated — an alias is a judgement about intent, not a fact extractable from
// source. Only unambiguous pairs are encoded; genuinely ambiguous ones are
// listed in [kUnresolvedResidentialSubtypes] for a product decision rather than
// guessed at.

/// Legacy Flutter `area_unit` values -> canonical React keys.
///
/// Flutter shipped 3 units; React defines 15 (see [kAreaUnitLabels]). Two of
/// Flutter's three were misspelled relative to React.
const Map<String, String> kAreaUnitAliases = {
  'sq_m': 'sq_mtr',
  'sq_yd': 'sq_yards',
  // 'sq_ft' already matches React and needs no alias.
};

/// Legacy Flutter `residential_subtype` values -> canonical React strings.
///
/// Only pairs where the intent is unambiguous appear here. React's canonical
/// set is [kResidentialSubTypeGroups]; membership of [kApartmentSubtypes]
/// decides isApartment vs isHouse, so a wrong alias silently changes which
/// fields the web requires.
const Map<String, String> kResidentialSubtypeAliases = {
  'Builder Floor': 'Independent / Builder Floor',
  'Studio Apartment': 'Studio / Service Apartment',
  'Independent House': 'Raw / Independent House',
  'Villa': 'Villa / Kothi',
  'Penthouse': 'Pent House',
  // Exact matches needing no alias:
  //   Flat, Duplex House, Triplex House, Bungalow, Farm House
};

/// Flutter subtype values with no defensible React counterpart.
///
/// Deliberately NOT aliased — each needs a product decision, and guessing would
/// silently re-file existing listings under the wrong category:
///
/// * `Apartment`      — React uses this only as a GROUP LABEL, never a stored
///                      value. Closest member is `Flat`, but that is an
///                      assumption about user intent, not a rename.
/// * `Row House`      — no React equivalent in either subtype group.
/// * `Hostel Building`— exists in React as a `buildingType` (PG), not a
///                      residential subtype.
/// * `Residential Plot` — exists in React as a `plotTypeOptions` value (land),
///                      not a residential subtype.
///
/// Until these are resolved, [canonicalResidentialSubtype] passes them through
/// unchanged so no data is silently reclassified.
const List<String> kUnresolvedResidentialSubtypes = [
  'Apartment',
  'Row House',
  'Hostel Building',
  'Residential Plot',
];

/// Maps a stored area unit to its canonical React key, leaving already-correct
/// and unknown values untouched.
String canonicalAreaUnit(String stored) => kAreaUnitAliases[stored] ?? stored;

/// Maps a stored residential subtype to its canonical React string.
///
/// Unknown or unresolved values pass through unchanged — never guessed at.
String canonicalResidentialSubtype(String stored) =>
    kResidentialSubtypeAliases[stored] ?? stored;
