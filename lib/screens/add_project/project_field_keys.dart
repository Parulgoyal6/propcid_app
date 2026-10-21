// screens/add_project/project_field_keys.dart
//
// Field identities for the builder project wizard.
//
// These are the `field` values on every rule in `project_validation_rules.dart`,
// and they double as the key a step body uses to decide whether one of its inputs
// should render in its error state. They are the **column names**, matching the
// reference's `ProjectFormShape` keys (`projectRules.ts:17-40`), so an issue can
// be traced from the summary line straight to the column it will be written to.
//
// Kept as constants rather than an enum so the rule tables stay `const`.

const String kProjectTitle = 'title';
const String kProjectDescription = 'description';
const String kProjectType = 'project_type';
const String kProjectLocation = 'location';

/// Not a column on its own — flags the cross-field "has a valid map pin"
/// check in `project_validation_rules.dart`, pointed at the `latitude`
/// column the way `kProjectAvailableUnits` already stands in for its own
/// two-field cross-check.
const String kProjectCoordinates = 'latitude';

const String kProjectTotalUnits = 'total_units';
const String kProjectAvailableUnits = 'available_units';
const String kProjectPriceMin = 'price_range_min';
const String kProjectPriceMax = 'price_range_max';
const String kProjectAreaMin = 'area_sqft_min';
const String kProjectAreaMax = 'area_sqft_max';
const String kProjectCompletionDate = 'completion_date';
const String kProjectPossessionDate = 'possession_date';
const String kProjectReraNumber = 'rera_number';

const String kProjectWebsiteUrl = 'website_url';
const String kProjectContactNumber = 'contact_number';
const String kProjectLogoUrl = 'logo_url';
const String kProjectBrochureUrl = 'brochure_url';
const String kProjectMapImages = 'map_images';
const String kProjectOtherImages = 'other_images';
const String kProjectVideosUrls = 'videos_urls';

const String kProjectAmenities = 'amenities';
