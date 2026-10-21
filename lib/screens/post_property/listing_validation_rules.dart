// Direct port of propcid/src/lib/validation/propertyListingRules.ts.
//
// One rule set per wizard step. A rule only fires when the field is actually
// rendered for the current propertyType / listingType combination — the
// `applies` guards mirror the conditional JSX in each React step component, so
// a land listing is never asked for bedrooms and a residential one is never
// asked for soil type.
//
// The engine (isBlank, positiveNumber, validPhone, ...) lives in
// listing_validators.dart and was ported verbatim in T0.
//
// Two gates exist here that React has no need for, both documented at their
// definitions below: [kFlutterCollectableFields] (a rule whose field has no
// Flutter input yet must not block a save the user cannot fix) and
// grandfathering (editing a pre-existing row must not be blocked by a field
// that was already blank when it loaded).

import '../../core/utils/geo_utils.dart';
import '../../providers/post_property_provider.dart';
import 'listing_constants.dart';
import 'listing_validators.dart';

/* ── Types ─────────────────────────────────────────────────────────────── */

typedef RuleGuard = bool Function(ListingFormData d);
typedef RuleReader = Object? Function(ListingFormData d);
typedef RuleValidator = String? Function(Object? value);

/// A single required-field declaration. Mirrors `FieldRule<PropertyFormData>`.
class ListingRule {
  const ListingRule({
    required this.field,
    required this.label,
    this.applies,
    this.get,
    this.validate,
  });

  /// Form key — also the identity used for grandfathering and gating.
  final String field;

  /// Human label shown in the error summary.
  final String label;

  /// Only enforce when this returns true.
  final RuleGuard? applies;

  /// Custom reader for values that do not live at `data[field]`.
  final RuleReader? get;

  /// Extra format check, run only when the value is present.
  final RuleValidator? validate;
}

class ListingIssue {
  const ListingIssue(this.field, this.label, this.message);

  final String field;
  final String label;
  final String message;

  @override
  String toString() => '$field: $message';
}

/* ── Data adapter ──────────────────────────────────────────────────────── */

/// Presents [PostPropertyProvider] to the rules the way React presents its flat
/// `PropertyFormData`: one `read(field)` that resolves a React field name to
/// whatever holds it on the Flutter side — a named field, or the loose
/// `_text`/`_bool`/`_list` bag.
class ListingFormData {
  ListingFormData(this.p);

  final PostPropertyProvider p;

  /// React's `propertyType` values, not Flutter's enum names.
  String get propertyType => switch (p.category) {
    PropertyCategory.land => 'land',
    PropertyCategory.residential => 'residential',
    PropertyCategory.commercial => 'commercial',
    PropertyCategory.pg => 'pg/Co-living',
    PropertyCategory.other => 'others',
    null => '',
  };

  String get listingType => p.listingIntent?.name ?? '';

  Object? read(String field) {
    final Object? named = _named[field]?.call(this);
    if (named != null) return named;
    // Fall back to the bag, checking each typed map in turn.
    if (p.allTextFields.containsKey(field)) return p.allTextFields[field];
    if (p.allBoolFields.containsKey(field)) return p.allBoolFields[field];
    if (p.allListFields.containsKey(field)) return p.allListFields[field];
    return null;
  }

  /// React field name -> the Flutter named field holding it. Anything absent
  /// here resolves through the bag instead.
  static final Map<String, Object? Function(ListingFormData)> _named = {
    'propertyType': (d) => d.propertyType,
    'listingType': (d) => d.listingType,
    'title': (d) => d.p.title,
    'description': (d) => d.p.description,
    'location': (d) => d.p.location,
    'city': (d) => d.p.city,
    'state': (d) => d.p.state,
    'pincode': (d) => d.p.pincode,
    'landmark': (d) => d.p.landmark,
    'residentialSubType': (d) => d.p.residentialSubType,
    'furnishedType': (d) => d.p.furnishingType,
    'area': (d) => d.p.area,
    'areaUnit': (d) => d.p.areaUnit,
    'carpetArea': (d) => d.p.carpetArea,
    'bhkType': (d) => d.p.bhkType,
    'bedrooms': (d) => d.p.bedrooms,
    'bathrooms': (d) => d.p.bathrooms,
    'balconies': (d) => d.p.balconies,
    'floorNo': (d) => d.p.floorNo,
    'totalFloors': (d) => d.p.totalFloors,
    'propertyCondition': (d) => d.p.propertyCondition,
    'facing': (d) => d.p.facing,
    // React's one string: '' unanswered, else 'Immediately' or yyyy-MM-dd.
    // Reading the DateTime alone would score "Immediately" as unanswered.
    'availableFrom': (d) => d.p.availableFromValue,
    'price': (d) => d.p.price,
    'securityDeposit': (d) => d.p.securityDeposit,
    // React's canonical token key; Flutter names the field bookingAmount.
    'tokenAmount': (d) => d.p.bookingAmount,
    'lockInPeriod': (d) => d.p.lockInPeriod,
    'ratePerArea': (d) => d.p.ratePerArea,
    'maintenanceCharges': (d) => d.p.maintenanceCharges,
    'brokerage': (d) => d.p.brokerage,
    'contactName': (d) => d.p.contactName,
    'contactPhone': (d) => d.p.contactPhone,
    'contactEmail': (d) => d.p.contactEmail,
    'whatsappNumber': (d) => d.p.whatsappNumber,
    'bestTimeToCall': (d) => d.p.bestTimeToCall,
    'hashtags': (d) => d.p.hashtags,
    'latitude': (d) => d.p.latitude,
    'longitude': (d) => d.p.longitude,
  };
}

/* ── Guards ────────────────────────────────────────────────────────────── */

bool _isLand(ListingFormData d) => d.propertyType == 'land';
bool _isResidential(ListingFormData d) => d.propertyType == 'residential';
bool _isCommercial(ListingFormData d) => d.propertyType == 'commercial';
bool _isPg(ListingFormData d) => d.propertyType == 'pg/Co-living';
bool _isOthers(ListingFormData d) => d.propertyType == 'others';

/// Uses the canonical apartment subtype list from T0 — membership decides which
/// layout React renders, and therefore which fields it requires.
bool _isApartment(ListingFormData d) =>
    _isResidential(d) &&
    kApartmentSubtypes.contains(d.p.residentialSubType ?? '');

bool _isHouse(ListingFormData d) =>
    _isResidential(d) &&
    !kApartmentSubtypes.contains(d.p.residentialSubType ?? '');

bool _isRentOrLease(ListingFormData d) =>
    d.listingType == 'rent' || d.listingType == 'lease';

bool _isSell(ListingFormData d) => d.listingType == 'sell';

/// Commercial Lease Terms (lease duration, escalation, CAM, fit-out) apply to
/// a commercial LEASE only — the Pricing step hides that section for rent.
bool _isCommercialLease(ListingFormData d) =>
    _isCommercial(d) && d.listingType == 'lease';

/// Reads a key out of the nested commercial `buildingInventory` object.
RuleReader _fromBuilding(String key) =>
    (d) => d.p.buildingInventoryValue(key);

/* ── Step rule sets ────────────────────────────────────────────────────── */

const List<ListingRule> _categoryRules = [
  ListingRule(field: 'propertyType', label: 'Property category'),
  ListingRule(
    field: 'listingType',
    label: 'Listing type (Rent / Sell / Lease)',
  ),
];

final List<ListingRule> _basicInfoRules = [
  const ListingRule(field: 'title', label: 'Property headline'),
  const ListingRule(field: 'description', label: 'Property description'),

  // Category-specific selects rendered next to the headline.
  ListingRule(field: 'landSubtype', label: 'Land subtype', applies: _isLand),
  ListingRule(field: 'landType', label: 'Land use type', applies: _isLand),
  ListingRule(
    field: 'residentialSubType',
    label: 'Residential subtype',
    applies: _isResidential,
  ),
  ListingRule(
    field: 'commercialSubType',
    label: 'Commercial subtype',
    applies: _isCommercial,
  ),
  ListingRule(
    field: 'furnishedType',
    label: 'Furnishing type',
    applies: _isCommercial,
  ),
  ListingRule(
    field: 'pgPropertyType',
    label: 'PG property type',
    applies: _isPg,
  ),
  ListingRule(field: 'buildingType', label: 'Building type', applies: _isPg),
  ListingRule(
    field: 'pgPropertyName',
    label: 'PG / property name',
    applies: _isPg,
  ),
  ListingRule(
    field: 'propertyStatus',
    label: 'Property status',
    applies: _isPg,
  ),

  // Location block — every listing needs a resolvable address.
  ListingRule(
    field: 'addressLine1',
    label: 'Property address',
    get: (d) {
      final Object? line1 = d.read('addressLine1');
      if (line1 != null && line1.toString().trim().isNotEmpty) return line1;
      return d.p.location;
    },
  ),
  const ListingRule(field: 'city', label: 'City'),
  const ListingRule(field: 'state', label: 'State'),
  ListingRule(field: 'pincode', label: 'Pincode', validate: validPincode),
  // Landmark has no rule in the portal's own propertyListingRules.ts — it's
  // collected (see basic_info_step.dart) but never required there, so it
  // isn't required here either.
  ListingRule(
    // Both coordinates come from the same map pin, so they are validated as
    // one requirement — "pick a spot on the map" rather than two cryptic
    // errors.
    field: 'latitude',
    label: 'Map location (drop a pin)',
    get: (d) => (d.p.latitude != null && d.p.longitude != null) ? 'set' : '',
  ),
];

final List<ListingRule> _dimensionRules = [
  // Area is asked for in every category except commercial. The commercial step
  // has no `area` input of its own — it asks for Plot + Super built-up area and
  // mirrors the latter into `area`, so demanding `area` here would be an error
  // with no field to fix it.
  ListingRule(
    field: 'area',
    label: 'Total area',
    applies: (d) => !_isCommercial(d),
    validate: positiveNumber('Total area'),
  ),
  const ListingRule(field: 'areaUnit', label: 'Area unit'),

  // LAND
  ListingRule(
    field: 'landUseMasterPlan',
    label: 'Land use / master plan',
    applies: (d) => _isLand(d) && d.listingType == 'rent',
  ),
  ListingRule(field: 'front', label: 'Front dimension', applies: _isLand),
  ListingRule(field: 'back', label: 'Back dimension', applies: _isLand),
  ListingRule(field: 'right', label: 'Right dimension', applies: _isLand),
  ListingRule(field: 'left', label: 'Left dimension', applies: _isLand),
  // Khasra number (`surveyNumber`) was required here and on the portal, but
  // is now deliberately optional on this app only, per explicit product
  // direction — not a porting gap, a one-way Flutter/portal divergence.
  //
  // fsiFarAllowed / floorAllowed / heightRestriction are collected (see
  // property_dimensions_step.dart) but have no rule at all in the portal's
  // propertyListingRules.ts for Land — they're optional there, so requiring
  // them here blocked new Land listings over fields the website never asks
  // for.
  ListingRule(field: 'soilType', label: 'Soil type', applies: _isLand),

  // RESIDENTIAL — shared between the apartment and house layouts.
  ListingRule(
    field: 'carpetArea',
    label: 'Carpet area',
    applies: (d) => _isResidential(d) || _isPg(d) || _isOthers(d),
    validate: positiveNumber('Carpet area'),
  ),
  ListingRule(
    field: 'builtUpArea',
    label: 'Built-up area',
    applies: _isHouse,
    validate: positiveNumber('Built-up area'),
  ),
  ListingRule(field: 'bhkType', label: 'BHK type', applies: _isResidential),
  ListingRule(
    field: 'bedrooms',
    label: 'Bedrooms',
    applies: _isResidential,
    validate: nonNegativeNumber('Bedrooms'),
  ),
  ListingRule(
    field: 'bathrooms',
    label: 'Bathrooms',
    applies: _isResidential,
    validate: nonNegativeNumber('Bathrooms'),
  ),
  ListingRule(
    field: 'balconies',
    label: 'Balconies',
    applies: _isResidential,
    validate: nonNegativeNumber('Balconies'),
  ),
  ListingRule(
    field: 'floorNo',
    label: 'Floor number',
    applies: _isApartment,
    validate: nonNegativeNumber('Floor number'),
  ),
  ListingRule(
    field: 'totalFloors',
    label: 'Total floors',
    applies: (d) => _isResidential(d) || _isPg(d),
    validate: nonNegativeNumberWithMax(163, 'Total floors'),
  ),
  ListingRule(
    field: 'propertyCondition',
    label: 'Property condition',
    applies: _isResidential,
  ),

  // COMMERCIAL — building-level block.
  ListingRule(
    field: 'buildingName',
    label: 'Building name',
    applies: _isCommercial,
    get: _fromBuilding('buildingName'),
  ),
  ListingRule(
    field: 'buildingCode',
    label: 'Building number',
    applies: _isCommercial,
    get: _fromBuilding('buildingCode'),
  ),
  ListingRule(
    field: 'buildingType',
    label: 'Building type',
    applies: _isCommercial,
    get: _fromBuilding('buildingType'),
  ),
  ListingRule(
    field: 'totalFloorsBuilding',
    label: 'Total floors in building',
    applies: _isCommercial,
    get: _fromBuilding('totalFloorsBuilding'),
    validate: positiveNumberWithMax(163, 'Total floors in building'),
  ),
  ListingRule(
    field: 'plotArea',
    label: 'Plot area',
    applies: _isCommercial,
    validate: positiveNumber('Plot area'),
  ),
  ListingRule(
    field: 'superBuiltUpArea',
    label: 'Super built-up area',
    applies: _isCommercial,
    validate: positiveNumber('Super built-up area'),
  ),

  // PG
  ListingRule(field: 'facing', label: 'Facing', applies: _isPg),

  // Available-from lives on this step for land / residential flows.
  ListingRule(
    field: 'availableFrom',
    label: 'Available from',
    applies: (d) => _isLand(d) || _isResidential(d),
  ),
];

final List<ListingRule> _conditionRules = [
  const ListingRule(field: 'propertyCondition', label: 'Property condition'),
  const ListingRule(field: 'availableFrom', label: 'Available from'),

  // Building condition block — commercial only.
  ListingRule(
    field: 'buildingAge',
    label: 'Building age',
    applies: _isCommercial,
    get: _fromBuilding('buildingAge'),
  ),
  ListingRule(
    field: 'ownershipTypeBuilding',
    label: 'Building ownership type',
    applies: _isCommercial,
    get: _fromBuilding('ownershipTypeBuilding'),
  ),

  // PG food & housekeeping.
  ListingRule(
    field: 'linenChangeFrequency',
    label: 'Linen change frequency',
    applies: _isPg,
  ),
  ListingRule(
    field: 'roomCleaningFrequency',
    label: 'Room cleaning frequency',
    applies: _isPg,
  ),
];

final List<ListingRule> _amenityRules = [
  ListingRule(
    field: 'amenities',
    label: 'At least one amenity',
    applies: (d) => _isResidential(d) || _isOthers(d),
  ),
  ListingRule(
    field: 'pgAmenities',
    label: 'At least one PG amenity',
    applies: _isPg,
  ),

  // Commercial building facilities that are free-text / selects.
  ListingRule(
    field: 'businessType',
    label: 'Business type',
    applies: (d) {
      final Object? running = d.read('currentBusinessRunning');
      final bool isRunning = running is bool
          ? running
          : running != null &&
                running.toString().isNotEmpty &&
                running.toString() != 'false';
      return _isCommercial(d) && isRunning;
    },
  ),
  ListingRule(
    field: 'workingDays',
    label: 'Working days',
    applies: _isCommercial,
    get: _fromBuilding('workingDays'),
  ),
  ListingRule(
    field: 'buildingWorkingHours',
    label: 'Building working hours',
    applies: _isCommercial,
    get: _fromBuilding('buildingWorkingHours'),
  ),
  ListingRule(
    field: 'liftCount',
    label: 'Lift count',
    applies: _isCommercial,
    get: _fromBuilding('liftCount'),
    validate: nonNegativeNumber('Lift count'),
  ),
  ListingRule(
    field: 'securityGuards',
    label: 'Security guards',
    applies: _isCommercial,
    get: _fromBuilding('securityGuards'),
    validate: nonNegativeNumber('Security guards'),
  ),
  ListingRule(
    field: 'maintenanceCharges',
    label: 'Building maintenance charges',
    applies: _isCommercial,
    get: _fromBuilding('maintenanceCharges'),
    validate: nonNegativeNumber('Building maintenance charges'),
  ),
  ListingRule(
    field: 'totalCarParking',
    label: 'Total car parking',
    applies: _isCommercial,
    get: _fromBuilding('totalCarParking'),
    validate: nonNegativeNumber('Total car parking'),
  ),
  ListingRule(
    field: 'totalBikeParking',
    label: 'Total bike parking',
    applies: _isCommercial,
    get: _fromBuilding('totalBikeParking'),
    validate: nonNegativeNumber('Total bike parking'),
  ),
];

final List<ListingRule> _legalRules = [
  ListingRule(
    field: 'ownershipType',
    label: 'Ownership type',
    applies: _isLand,
  ),
  ListingRule(field: 'ownerName', label: 'Owner name', applies: _isLand),
  ListingRule(
    field: 'quietHours',
    label: 'Quiet hours / gate closing time',
    applies: _isPg,
  ),
];

final List<ListingRule> _pricingRules = [
  // PG rent uses per-bed / per-room amounts instead of the single price box.
  ListingRule(
    field: 'price',
    label: 'Price / rent amount',
    applies: (d) => !(_isPg(d) && d.listingType != 'lease'),
    validate: positiveNumber('Price / rent amount'),
  ),
  ListingRule(
    field: 'monthlyRentPerBed',
    label: 'Rent per bed or per room',
    applies: (d) => _isPg(d) && d.listingType == 'rent',
    get: (d) {
      final Object? bed = d.read('monthlyRentPerBed');
      if (bed != null && bed.toString().trim().isNotEmpty) return bed;
      return d.read('monthlyRentPerRoom');
    },
  ),
  ListingRule(
    field: 'totalSalePrice',
    label: 'Total sale price',
    applies: (d) => _isPg(d) && _isSell(d),
    validate: positiveNumber('Total sale price'),
  ),
  ListingRule(
    field: 'occupancyRate',
    label: 'Current occupancy rate',
    applies: (d) => _isPg(d) && _isSell(d),
  ),

  // Deposits / tokens are rendered for every category.
  ListingRule(
    field: 'securityDeposit',
    label: 'Security deposit',
    applies: _isRentOrLease,
  ),
  const ListingRule(field: 'tokenAmount', label: 'Token amount'),
  ListingRule(
    field: 'lockInPeriod',
    label: 'Minimum rent / lease period',
    applies: (d) => _isRentOrLease(d) && !(_isPg(d) && _isSell(d)),
  ),
  // PG / co-living sale has no rate-per-area input.
  ListingRule(
    field: 'ratePerArea',
    label: 'Rate per area',
    applies: (d) => _isSell(d) && !_isPg(d),
    validate: positiveNumber('Rate per area'),
  ),

  // Maintenance: apartments show "Society charges", everything else
  // "Maintenance".
  ListingRule(
    field: 'societyCharges',
    label: 'Society charges',
    applies: (d) => _isApartment(d) && _isRentOrLease(d),
  ),
  ListingRule(
    field: 'maintenanceCharges',
    label: 'Maintenance charges',
    applies: (d) => !_isApartment(d) && !_isLand(d) && _isRentOrLease(d),
  ),

  // Commercial lease terms / investment details.
  ListingRule(
    field: 'leaseDuration',
    label: 'Lease duration',
    applies: _isCommercialLease,
    get: (d) {
      final Object? v = d.read('leaseDuration');
      if (v != null && v.toString().trim().isNotEmpty) return v;
      return d.read('minRentalDuration');
    },
  ),
  ListingRule(
    field: 'leaseEscalationPercent',
    label: 'Rent escalation %',
    applies: _isCommercialLease,
    get: (d) {
      final Object? v = d.read('leaseEscalationPercent');
      if (v != null && v.toString().trim().isNotEmpty) return v;
      return d.read('rentEscalation');
    },
  ),
  ListingRule(
    field: 'camCharges',
    label: 'CAM charges',
    applies: _isCommercialLease,
  ),
  ListingRule(
    field: 'fitOutPeriod',
    label: 'Fit-out period',
    applies: _isCommercialLease,
  ),
  ListingRule(
    field: 'roiEstimate',
    label: 'ROI estimate',
    applies: (d) => _isCommercial(d) && _isSell(d),
  ),
  ListingRule(
    field: 'currentRentalIncome',
    label: 'Current rental income',
    applies: (d) => _isCommercial(d) && _isSell(d),
  ),

  // PG charges.
  ListingRule(
    field: 'foodCharges',
    label: 'Food charges',
    applies: (d) => _isPg(d) && d.listingType == 'rent',
  ),
  ListingRule(
    field: 'laundryCharges',
    label: 'Laundry charges',
    applies: (d) => _isPg(d) && d.listingType == 'rent',
  ),

  // Optional for every user/category — no `ListingRule` entry, since a rule
  // in this table is a required-field declaration (see `collectIssues`).
];

final List<ListingRule> _mediaRules = [
  ListingRule(
    field: 'mediaFiles',
    label: 'At least one photo',
    get: (d) => [...d.p.mediaItems, ...d.p.existingMediaUrls],
  ),
  ListingRule(
    field: 'ownerManagerName',
    label: 'PG owner / manager name',
    applies: _isPg,
  ),
  // The portal's own rule for this field is permanently disabled
  // (`applies: () => false` in propertyListingRules.ts, no validator) — it's
  // collected (media_contact_step.dart) but the website never requires or
  // format-checks it, for PG or any other category.
  ListingRule(
    field: 'alternateNumber',
    label: 'Alternate contact number',
    applies: (d) => false,
  ),
  const ListingRule(field: 'contactName', label: 'Contact name'),
  ListingRule(
    field: 'contactPhone',
    label: 'Phone number',
    validate: validPhone,
  ),
  ListingRule(
    field: 'contactEmail',
    label: 'Email address',
    // Was required here and on the portal; now deliberately optional on
    // this app only, per explicit product direction — `applies` skips the
    // required check entirely while the field is blank. `validEmail` still
    // runs the moment something is typed (the field is non-blank by the
    // time `applies` lets `collectIssues` re-check it), so a malformed
    // address is still caught — only outright leaving it empty no longer is.
    applies: (d) => !isBlank(d.read('contactEmail')),
    validate: validEmail,
  ),
  ListingRule(
    field: 'whatsappNumber',
    label: 'WhatsApp number',
    // Was a custom "exactly 10 digits" regex with a typo (`d{10}` missing
    // the `\` — matched only the literal string "dddddddddd", so every
    // real WhatsApp number failed validation unconditionally). The portal
    // has no WhatsApp-specific rule at all: both `contactPhone` and
    // `whatsappNumber` map to the same `validPhone` function
    // (propertyListingRules.ts:310,312) — same as `contactPhone` right
    // above. That got this field working, but `validPhone`'s 8-15-character
    // range (meant for a free-text field that can carry "+91 98765 43210"
    // punctuation) let an incomplete 8- or 9-digit entry through this
    // field's own digits-only, max-10 text input — a real WhatsApp number
    // is always exactly 10 digits, so this uses [validWhatsappNumber]
    // instead, scoped to this field only.
    validate: validWhatsappNumber,
  ),
  ListingRule(
    field: 'bestTimeToCall',
    label: 'Best time to call',
    validate: validTimeRange,
  ),
  // `hashtags` was required here and on the portal; now deliberately
  // optional on this app only, per explicit product direction. No format
  // check existed for it either, so removing the rule entirely (rather than
  // gating it like `contactEmail` above) loses nothing.
];

/// Rules keyed by React's step titles.
final Map<String, List<ListingRule>> kPropertyStepRules = {
  'Category': _categoryRules,
  'Basic Info': _basicInfoRules,
  'Dimensions': _dimensionRules,
  'Condition': _conditionRules,
  'Amenities': _amenityRules,
  'Legal': _legalRules,
  'Pricing': _pricingRules,
  'Media': _mediaRules,
};

/* ── Step visibility (T3) ──────────────────────────────────────────────── */

/// One entry per wizard screen. Mirrors the `title`s in
/// `PropertyWizard.tsx stepsRaw`, plus Flutter's own Review step, which React
/// has no equivalent for.
enum WizardStep {
  category,
  basicInfo,
  dimensions,
  condition,
  amenities,
  legal,
  pricing,
  media,
  review,
}

/// React's rule-set key for [step]; null for Review, which validates nothing of
/// its own (it summarises the steps before it).
String? ruleKeyForStep(WizardStep step) => switch (step) {
  WizardStep.category => 'Category',
  WizardStep.basicInfo => 'Basic Info',
  WizardStep.dimensions => 'Dimensions',
  WizardStep.condition => 'Condition',
  WizardStep.amenities => 'Amenities',
  WizardStep.legal => 'Legal',
  WizardStep.pricing => 'Pricing',
  WizardStep.media => 'Media',
  WizardStep.review => null,
};

/// The steps actually shown for [category] — a verbatim port of
/// `PropertyWizard.tsx:1350`:
///
/// ```
/// const stepsRaw = [
///   Category, Basic Info, Dimensions,
///   ...(!isLand && !isResidential ? [Condition] : []),
///   ...(!isLand ? [Amenities] : []),
///   Legal, Pricing, Media
/// ];
/// ```
///
/// So Condition is hidden for land and residential; Amenities is hidden for
/// land. Resulting counts (before Flutter's Review step): land 6, residential
/// 7, commercial / PG / others 8.
///
/// A null [category] evaluates the guards exactly as the JS expression would
/// with neither predicate true, so every step is offered until the user picks
/// a category on step 1. React never reaches this state — its initial form data
/// defaults `propertyType` to `'residential'` — so there is nothing to mirror;
/// showing all steps and then removing is the conservative direction.
List<WizardStep> visibleStepsFor(PropertyCategory? category) {
  final bool isLand = category == PropertyCategory.land;
  final bool isResidential = category == PropertyCategory.residential;

  return <WizardStep>[
    WizardStep.category,
    WizardStep.basicInfo,
    WizardStep.dimensions,
    if (!isLand && !isResidential) WizardStep.condition,
    if (!isLand) WizardStep.amenities,
    WizardStep.legal,
    WizardStep.pricing,
    WizardStep.media,
    WizardStep.review,
  ];
}

/* ── Enforcement gates ─────────────────────────────────────────────────── */

/// Rule fields the Flutter wizard currently renders an input for.
///
/// A rule whose field is absent here is still *evaluated* — it appears in
/// [collectIssues] with `onlyCollectable: false`, which is how the parity tests
/// compare against React — but it never blocks a save, because the user would
/// have no field on screen to fix it. React reasons the same way about its own
/// commercial `area` rule.
///
/// This set shrinks the gap as T3-T10 add inputs; every entry removed from the
/// "missing" side turns a rule live. Derived from the setters and bag keys the
/// step widgets actually call.
const Set<String> kFlutterCollectableFields = {
  // Step 1
  'propertyType', 'listingType',
  // Step 2
  'title', 'description', 'addressLine1', 'city', 'state', 'pincode',
  'landmark', 'residentialSubType', 'commercialSubType', 'furnishedType',
  'pgPropertyType', 'buildingType', 'pgPropertyName', 'propertyStatus',
  'landType',
  // Step 3
  'area', 'areaUnit', 'carpetArea', 'bhkType', 'bedrooms', 'bathrooms',
  'balconies', 'floorNo', 'totalFloors', 'propertyCondition', 'facing',
  'availableFrom', 'plotArea', 'superBuiltUpArea', 'soilType',
  'builtUpArea', // T6: house layout
  // T8: land specification block
  'landSubtype', 'landUseMasterPlan', 'front', 'back', 'right', 'left',
  'surveyNumber',
  // Map pin — LocationPickerMap already sets both (basic_info_step.dart);
  // this was collected but missing from this set, so the rule above was
  // silently never enforced even though the portal requires a map pin.
  'latitude', 'longitude',
  // T10: commercial building block
  'buildingName', 'buildingCode', 'totalFloorsBuilding',
  'buildingAge', 'ownershipTypeBuilding',
  // Step 4
  'linenChangeFrequency', 'roomCleaningFrequency',
  // Step 5
  'amenities', 'pgAmenities', 'businessType',
  // T10: building facilities, all read from buildingInventory
  'workingDays', 'buildingWorkingHours', 'liftCount', 'securityGuards',
  'totalCarParking', 'totalBikeParking',
  // Step 6
  'quietHours',
  'ownershipType', 'ownerName', // T8: land legal
  // Step 7
  'price', 'monthlyRentPerBed', 'totalSalePrice', 'occupancyRate',
  'securityDeposit', 'tokenAmount', 'lockInPeriod', 'ratePerArea',
  'maintenanceCharges', 'societyCharges', // T6: apartment rent/lease
  'leaseDuration', 'leaseEscalationPercent',
  'camCharges', 'fitOutPeriod', 'roiEstimate', 'currentRentalIncome',
  'foodCharges', 'laundryCharges', 'brokerage',
  // Step 8
  'mediaFiles', 'ownerManagerName', 'alternateNumber', 'contactName',
  'contactPhone', 'contactEmail', 'whatsappNumber', 'bestTimeToCall',
  'hashtags',
};

/// Rule fields with no Flutter input yet — the T3-T10 backlog, in rule terms.
Set<String> get kFieldsNotYetCollectable {
  final all = <String>{
    for (final rules in kPropertyStepRules.values)
      for (final r in rules) r.field,
  };
  return all.difference(kFlutterCollectableFields);
}

/* ── Engine ────────────────────────────────────────────────────────────── */

/// Runs a rule set and returns every unmet requirement, in rule order.
/// Mirrors `collectIssues` (requiredFields.ts:58).
///
/// [onlyCollectable] gates out rules the Flutter UI cannot satisfy yet; pass
/// false to evaluate the rule table exactly as React would.
/// [grandfathered] gates out fields that were already blank when an existing
/// listing was loaded for edit (final-architecture-review Q14 item 4).
List<ListingIssue> collectIssues(
  ListingFormData data,
  List<ListingRule> rules, {
  bool onlyCollectable = true,
  Set<String> grandfathered = const <String>{},
}) {
  final issues = <ListingIssue>[];

  for (final rule in rules) {
    if (onlyCollectable && !kFlutterCollectableFields.contains(rule.field)) {
      continue;
    }
    if (rule.applies != null && !rule.applies!(data)) continue;

    final Object? value = rule.get != null
        ? rule.get!(data)
        : data.read(rule.field);

    if (isBlank(value)) {
      // Grandfathering suppresses the *required* check only, and only while
      // the field is still blank. It is an exemption from "you must supply a
      // value you never had", not a permanent opt-out of validation: as soon
      // as the user types something, the format check below applies normally.
      if (grandfathered.contains(rule.field)) continue;
      issues.add(
        ListingIssue(rule.field, rule.label, '${rule.label} is required.'),
      );
      continue;
    }

    final String? formatError = rule.validate?.call(value);
    if (formatError != null) {
      issues.add(ListingIssue(rule.field, rule.label, formatError));
    }
  }

  return issues;
}

/// Beyond "a pin was dropped" ([_basicInfoRules]'s own `latitude` rule,
/// which only checks presence), the pin actually has to be a usable one —
/// not a corrupted, out-of-range, or `(0, 0)` "Null Island" pair, which is
/// exactly what a stale/never-resolved coordinate looks like. An address
/// string alone (`addressLine1`/`city`/`state`) has never been enough to
/// satisfy this on its own; this fires independently of those rules.
List<ListingIssue> _crossFieldLocationIssues(ListingFormData data) {
  final lat = data.p.latitude;
  final lng = data.p.longitude;
  if (lat == null && lng == null) return const [];
  if (isValidCoordinatePair(lat, lng)) return const [];
  return const [
    ListingIssue(
      'latitude',
      'Map location (drop a pin)',
      'Pick a valid location on the map or from an address search.',
    ),
  ];
}

/// Floor number cannot exceed total floors — not part of the React port,
/// added on explicit request. Only fires once both are present (each is
/// already required on its own via [_dimensionRules]), and only for the
/// apartment subtypes that actually collect Floor No.
List<ListingIssue> _crossFieldDimensionIssues(ListingFormData data) {
  final floorNo = int.tryParse(data.p.floorNo);
  final totalFloors = int.tryParse(data.p.totalFloors);
  if (floorNo != null && totalFloors != null && floorNo > totalFloors) {
    return const [
      ListingIssue(
        'floorNo',
        'Floor number',
        'Floor number cannot be greater than total floors.',
      ),
    ];
  }
  return const [];
}

/// Validate one step by React step title. Unknown titles validate clean.
List<ListingIssue> validatePropertyStep(
  String stepTitle,
  ListingFormData data, {
  bool onlyCollectable = true,
  Set<String> grandfathered = const <String>{},
}) {
  final issues = collectIssues(
    data,
    kPropertyStepRules[stepTitle] ?? const <ListingRule>[],
    onlyCollectable: onlyCollectable,
    grandfathered: grandfathered,
  );
  if (stepTitle == 'Basic Info') {
    issues.addAll(_crossFieldLocationIssues(data));
  }
  if (stepTitle == 'Dimensions') {
    issues.addAll(_crossFieldDimensionIssues(data));
  }
  return issues;
}
