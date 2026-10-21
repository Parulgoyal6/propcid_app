// GENERATED FROM REACT SOURCE — DO NOT HAND-EDIT VALUES.
//
// T0 ground truth for the listing migration. Every option list below is parsed
// verbatim out of the React wizard (propcid/src) by
// scripts/t0/gen_dart.py, because CLAUDE.md forbids inventing dropdown values
// and a single differing enum string silently breaks web filters and reads.
//
// Flutter keeps its own widgets and styling (migration-specification PHASE 11);
// only the *values* are shared. Tailwind colour classes attached to React's
// media categories are deliberately dropped — they are web presentation.
//
// Regenerate rather than edit. listing_constants_parity_test.dart asserts these
// lists still equal the React arrays.

/// An option whose stored id differs from its display label.
class ListingOption {
  const ListingOption(this.id, this.label);

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ListingOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'ListingOption($id, $label)';
}

/// A labelled group of options (React renders these as `SelectGroup`).
class ListingOptionGroup {
  const ListingOptionGroup(this.label, this.options);

  final String label;
  final List<String> options;
}

// ==========================================================================
// Step 1 — Category & listing type
// ==========================================================================

/// Canonical category values written to properties.category input.
/// Source: components/PropertyWizard/steps/TypeSelectionStep.tsx:119
const List<String> kPropertyTypeIds = [
  'land',
  'residential',
  'commercial',
  'pg/Co-living',
  'others',
];

/// Source: components/PropertyWizard/steps/TypeSelectionStep.tsx:119
const List<ListingOption> kPropertyTypeTitles = [
  ListingOption('land', 'Land / Plot'),
  ListingOption('residential', 'Residential'),
  ListingOption('commercial', 'Commercial'),
  ListingOption('pg/Co-living', 'PG / Co-living'),
  ListingOption('others', 'Others'),
];

/// Source: components/PropertyWizard/steps/TypeSelectionStep.tsx:119
const List<ListingOption> kPropertyTypeDescriptions = [
  ListingOption('land', 'Plots, Agricultural Land, Independent Land, etc.'),
  ListingOption('residential', 'Houses, Apartments, Flats, Villas, etc.'),
  ListingOption('commercial', 'Offices, Shops, Showrooms, Warehouses, etc.'),
  ListingOption('pg/Co-living', 'PG, Hostels, Co-living Spaces, etc.'),
  ListingOption('others', 'Other properties, warehouses, etc.'),
];

/// Written to the properties.property_type column (NOT the category).
/// Source: TypeSelectionStep.tsx getAvailableListingTypes()
const List<String> kListingTypeIds = ['rent', 'sell', 'lease'];

// ==========================================================================
// Residential subtypes
// ==========================================================================

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:178
const List<ListingOptionGroup> kResidentialSubTypeGroups = [
  ListingOptionGroup('Apartment', [
    'Flat',
    'Independent / Builder Floor',
    'Studio / Service Apartment',
  ]),
  ListingOptionGroup('House', [
    'Raw / Independent House',
    'Villa / Kothi',
    'Duplex House',
    'Triplex House',
    'Pent House',
    'Bungalow',
    'Farm House',
  ]),
];

/// Drives React isApartment/isHouse validation branching. A subtype outside this list is treated as a house.
/// Source: components/PropertyWizard/steps/PricingStep.tsx:19
const List<String> kApartmentSubtypes = [
  'Flat',
  'Independent / Builder Floor',
  'Studio / Service Apartment',
];

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:178
const List<String> kHouseSubtypes = [
  'Raw / Independent House',
  'Villa / Kothi',
  'Duplex House',
  'Triplex House',
  'Pent House',
  'Bungalow',
  'Farm House',
];

// ==========================================================================
// Land
// ==========================================================================

/// Source: BasicInfoStep.tsx:263
const List<String> kLandSubtypes = ['land', 'plot'];

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:23
const List<String> kLandTypeOptions = [
  'Agriculture Land',
  'Residential Land',
  'Commercial Land',
  'Industrial Land',
  'Institutional Land',
];

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:31
const List<String> kPlotTypeOptions = ['Residential Plot', 'Commercial Plot'];

/// Required only when listingType == rent (propertyListingRules.ts).
/// Source: components/PropertyWizard/steps/PropertyDimensionsStep.tsx:195
const List<String> kLandUseMasterPlanOptions = [
  'Agriculture',
  'Residential',
  'Commercial',
  'Industrial',
  'Institutional / IT park',
  'Parking Zone / Transport Hub',
  'Others',
];

/// Source: components/PropertyWizard/steps/PropertyDimensionsStep.tsx:222
const List<String> kLandSoilTypes = [
  'Alluvial Soil',
  'Black Soil',
  'Red Soil',
  'Laterite Soil',
  'Sandy Soil',
  'Clay Soil',
  'Loamy Soil',
  'Silty Soil',
  'Gravelly Soil',
  'Rocky Soil',
  'Peaty Soil',
  'Chalky Soil',
  'Saline Soil',
  'Mixed Soil',
  'Mountain Soil',
  'Agricultural Fertile Soil',
  'Filled/Reclaimed Land',
  'Unknown',
];

/// Source: components/PropertyWizard/steps/LegalDetailsStep.tsx:18
const List<String> kLandOwnershipTypes = [
  'Freehold',
  'Leasehold',
  'Power of Attorney',
  'Co-Operative Society',
];

// ==========================================================================
// PG / Co-living
// ==========================================================================

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:36
const List<String> kPgPropertyTypes = [
  'Boys PG',
  'Girls PG',
  'Co-ed PG',
  'Co-living Space',
  'Student Housing',
  'Working Professional PG',
  'Hostel',
];

/// Source: components/PropertyWizard/steps/BasicInfoStep.tsx:40
const List<String> kBuildingTypeOptions = [
  'Apartment',
  'Independent House',
  'Individual Building',
  'Villa',
  'Hostel Building',
  'Gated Community Society',
  'Others',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:94
const List<ListingOption> kPgRoomAmenities = [
  ListingOption('acPg', 'AC'),
  ListingOption('fanPg', 'Fan'),
  ListingOption('tvPg', 'TV'),
  ListingOption('wifiPg', 'Wi-Fi'),
  ListingOption('studyTablePg', 'Study Table'),
  ListingOption('chairPg', 'Chair'),
  ListingOption('wardrobePg', 'Wardrobe'),
  ListingOption('bedIncluded', 'Bed Included'),
  ListingOption('mattressIncluded', 'Mattress Included'),
  ListingOption('curtainsPg', 'Curtains'),
  ListingOption('refrigeratorPg', 'Refrigerator'),
  ListingOption('attachedBathroom', 'Attached Bathroom'),
  ListingOption('balconyPg', 'Balcony'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:111
const List<ListingOption> kPgCommonAreaAmenities = [
  ListingOption('Common Area', 'Common Area'),
  ListingOption('Dining Area', 'Dining Area'),
  ListingOption('Living Area', 'Living Area'),
  ListingOption('Library', 'Library'),
  ListingOption('Gym / Fitness Center', 'Gym / Fitness Center'),
  ListingOption('Swimming Pool', 'Swimming Pool'),
  ListingOption('Indoor Games', 'Indoor Games'),
  ListingOption('Outdoor Sports Area', 'Outdoor Sports Area'),
  ListingOption('Power Backup (100%)', 'Power Backup (100%)'),
  ListingOption('Power Backup (Partial)', 'Power Backup (Partial)'),
  ListingOption('Water Purifier (RO)', 'Water Purifier (RO)'),
  ListingOption('Lift', 'Lift'),
  ListingOption('Parking (2-Wheeler)', 'Parking (2-Wheeler)'),
  ListingOption('Parking (4-Wheeler)', 'Parking (4-Wheeler)'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:129
const List<ListingOption> kPgSafetyAndSecurity = [
  ListingOption('cctvCoverage', 'CCTV Coverage'),
  ListingOption('biometricAccess', 'Biometric Access'),
  ListingOption('policeVerificationRequired', 'Police Verification'),
  ListingOption('visitorEntryRegister', 'Visitor Entry Register'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:136
const List<ListingOption> kPgTenantRules = [
  ListingOption('studentsAllowed', 'Students Allowed'),
  ListingOption('workingProfessionalsAllowed', 'Working Professionals'),
  ListingOption('maleAllowed', 'Male Allowed'),
  ListingOption('femaleAllowed', 'Female Allowed'),
  ListingOption('couplesAllowed', 'Couples Allowed'),
  ListingOption('foreignNationalsAllowed', 'Foreign Nationals'),
  ListingOption('petsAllowedPg', 'Pets Allowed'),
  ListingOption('visitorsAllowedPg', 'Visitors Allowed'),
];

/// Source: components/PropertyWizard/steps/PropertyDimensionsStep.tsx:200
const List<ListingOption> kPgRoomFeatures = [
  ListingOption('attachedBathroom', 'Attached Bathroom'),
  ListingOption('balconyPg', 'Balcony'),
  ListingOption('acPg', 'AC'),
  ListingOption('fanPg', 'Fan'),
  ListingOption('tvPg', 'TV'),
  ListingOption('wifiPg', 'WiFi'),
  ListingOption('studyTablePg', 'Study Table'),
  ListingOption('chairPg', 'Chair'),
  ListingOption('wardrobePg', 'Wardrobe'),
  ListingOption('bedIncluded', 'Bed Included'),
  ListingOption('mattressIncluded', 'Mattress Included'),
  ListingOption('curtainsPg', 'Curtains'),
  ListingOption('refrigeratorPg', 'Refrigerator'),
];

/// Source: ConditionStep.tsx:196
const List<String> kLinenChangeFrequencies = [
  'Daily',
  'Alternate Days',
  'Weekly',
  'Fortnightly',
];

/// NOTE: differs from kLinenChangeFrequencies — On Demand vs Fortnightly.
/// Source: ConditionStep.tsx:216
const List<String> kRoomCleaningFrequencies = [
  'Daily',
  'Alternate Days',
  'Weekly',
  'On Demand',
];

// ==========================================================================
// Amenity lists
// ==========================================================================

/// NOTE: React source lists "Visitor Parking" twice; preserved verbatim.
/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:18
const List<String> kResidentialSocietyAmenities = [
  'Lift',
  'Power Backup',
  'Security Guard',
  'CCTV',
  'Intercom',
  'Swimming Pool',
  'Gym / Fitness Center',
  'Clubhouse',
  'Park / Garden',
  'Children Play Area',
  'Jogging Track',
  'Badminton Court',
  'Basketball Court',
  'Indoor Games',
  'Visitor Parking',
  'Gated Community',
  'Water Purifier (RO)',
  'Sewage Treatment',
  'Rainwater Harvesting',
  'Solar Power',
  'Air Conditioner',
  'Ceiling Fan',
  'Modular Kitchen',
  'Chimney',
  'Hob',
  'Refrigerator',
  'Washing Machine',
  'Dishwasher',
  'Water Heater / Geyser',
  'Exhaust Fan',
  'Wardrobe',
  'TV',
  'Wi-Fi / Internet',
  'Sofa',
  'Dining Table',
  'Attached Bathroom',
  'Balcony',
  'Bath Tub',
  'Curtains',
  'Storeroom',
  'Servant Room',
  'Pooja Room',
  'Study Room',
  'Car Parking (Covered)',
  'Car Parking (Open)',
  'Bike Parking',
  'Visitor Parking',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:34
const List<String> kResidentialFlatAmenities = [
  'Air Conditioner',
  'Ceiling Fan',
  'Modular Kitchen',
  'Chimney',
  'Hob',
  'Refrigerator',
  'Washing Machine',
  'Dishwasher',
  'Water Heater / Geyser',
  'Exhaust Fan',
  'Wardrobe',
  'TV',
  'Wi-Fi / Internet',
  'Sofa',
  'Dining Table',
  'Attached Bathroom',
  'Balcony',
  'Bath Tub',
  'Curtains',
  'Storeroom',
  'Servant Room',
  'Pooja Room',
  'Study Room',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:43
const List<String> kResidentialParkingAmenities = [
  'Car Parking (Covered)',
  'Car Parking (Open)',
  'Bike Parking',
  'Visitor Parking',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:56
const List<String> kCommercialSuitableFor = [
  'Office',
  'Retail',
  'Restaurant',
  'Clinic',
  'Salon',
  'Gym',
  'Warehouse',
  'Manufacturing',
  'Startup',
  'IT Company',
  'Franchise',
  'Showroom',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:62
const List<String> kCommercialOfficeBuildingAmenities = [
  'Reception Area',
  'Waiting Lounge',
  'Conference Room',
  'Meeting Room',
  'Open Workspace',
  'Cafeteria',
  'Biometric Entry',
  'Service Lift',
  'Escalator',
  'Security Guard',
  'CCTV',
  'Fire Fighting System',
  'Fire Exit',
  'Fiber Connectivity',
  'Intercom',
  'DG Backup',
  'Solar Backup',
  'ATM',
  'Wheelchair Accessibility',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:70
const List<String> kCommercialRetailWarehouseAmenities = [
  'Glass Frontage',
  'Display Area',
  'Signage Space',
  'Dock Height',
  'Truck Parking',
  'Loading Area',
  'Crane Facility',
  'Storage Racks',
  'Ventilation',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:147
const List<String> kOtherGeneralAmenities = [
  'Power Backup',
  'Security Guard',
  'CCTV',
  'Lift',
  'Parking',
  'Wi-Fi / Internet',
  'Water Purifier',
  'Gymnasium',
  'Swimming Pool',
  'Cafeteria',
  'Conference Room',
  'Fire Safety System',
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:47
const List<ListingOption> kResidentialTenantPreferences = [
  ListingOption('familyAllowed', 'Family'),
  ListingOption('bachelorAllowed', 'Bachelor'),
  ListingOption('companyLeaseAllowed', 'Company Lease'),
  ListingOption('petsAllowed', 'Pets Allowed'),
  ListingOption('smokingAllowed', 'Smoking Allowed'),
  ListingOption('vegetariansOnly', 'Vegetarians Only'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:72
const List<ListingOption> kCommercialWashrooms = [
  ListingOption('washrooms', 'Total Washrooms'),
  ListingOption('westernSeats', 'Western Seats'),
  ListingOption('indianSeats', 'Indian Seats'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:78
const List<ListingOption> kCommercialParking = [
  ListingOption('totalParking', 'Total Parking'),
  ListingOption('coveredParking', 'Covered Parking'),
  ListingOption('openParking', 'Open Parking'),
];

/// Source: components/PropertyWizard/steps/AmenitiesStep.tsx:84
const List<ListingOption> kCommercialOtherParking = [
  ListingOption('visitorParking', 'Visitor Parking'),
  ListingOption('reservedParking', 'Reserved Parking'),
  ListingOption('bikeParking', 'Bike Parking'),
  ListingOption('carParking', 'Car Parking'),
  ListingOption('truckParking', 'Truck Parking'),
  ListingOption('loadingVehicleAccess', 'Loading Vehicle Access'),
];

// ==========================================================================
// Select enums (extracted from step JSX)
// ==========================================================================

/// Source: PropertyDimensionsStep.tsx:567
const List<String> kBhkTypes = ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4+ BHK'];

/// Also used for projectStatus / ownership in the same control.
/// Source: ConditionStep.tsx:28
const List<String> kPropertyConditions = [
  'New',
  'Resale',
  'Under Construction',
  'Off-Plan',
  'Leasehold',
  'Freehold',
  'Co-ownership',
  'Joint Venture',
  'Other',
];

/// Source: PricingStep.tsx:234
const List<String> kLockInPeriods = [
  'None',
  '3 Months',
  '6 Months',
  '1 Year',
  '2 Years',
];

/// Commercial plot area — a SUBSET of kAreaUnitLabels keys.
/// Source: PropertyDimensionsStep.tsx:1714
const List<String> kPlotAreaUnits = ['sq_ft', 'sq_yd', 'sq_mtr', 'acres'];

/// Source: PropertyDimensionsStep.tsx:460
const List<String> kHeightRestrictionUnits = ['ft', 'm'];

/// Units for the front/back/right/left land dimensions. Three options, unlike kHeightRestrictionUnits which has two.
/// Source: PropertyDimensionsStep.tsx land side-dimension map
const List<String> kLandSideDimensionUnits = ['ft', 'm', 'yards'];

// ==========================================================================
// Media categories
// ==========================================================================

/// Order matters: metadata.mediaCategories is index-aligned with media_urls.
/// Source: components/PropertyWizard/steps/MediaAndFinalStep.tsx:23
const List<ListingOption> kDefaultImageCategories = [
  ListingOption('interior', 'Interior'),
  ListingOption('exterior', 'Exterior'),
  ListingOption('amenities', 'Amenities'),
  ListingOption('floor_plan', 'Floor Plan'),
  ListingOption('property_video', 'Property Video'),
  ListingOption('other', 'Other'),
];

/// Source: components/PropertyWizard/steps/MediaAndFinalStep.tsx:32
const List<ListingOption> kLandImageCategories = [
  ListingOption('sajra', 'Sajra'),
  ListingOption('land_video', 'Land video'),
  ListingOption('land_images', 'Land images'),
  ListingOption('other', 'Others'),
];

// ==========================================================================
// Area units
// ==========================================================================

/// Source: utils/areaUnits.ts AREA_UNITS
/// The full canonical set — 15 units, not the 3 Flutter shipped.
const Map<String, String> kAreaUnitLabels = {
  'sq_ft': 'Square Feet',
  'sq_mtr': 'Square Meters',
  'sq_yards': 'Square Yards',
  'acres': 'Acres',
  'hectares': 'Hectares',
  'bigha': 'Bigha',
  'katha': 'Katha',
  'marla': 'Marla',
  'kanal': 'Kanal',
  'guntha': 'Guntha',
  'ground': 'Ground',
  'cent': 'Cent',
  'decimal': 'Decimal',
  'biswa': 'Biswa',
  'ankanam': 'Ankanam',
};

/// Source: utils/areaUnits.ts UNITS_BY_PROPERTY_TYPE
/// Which units each category may offer. Not every unit is valid everywhere.
const Map<String, List<String>> kAreaUnitsByPropertyType = {
  'land': [
    'acres',
    'hectares',
    'sq_yards',
    'sq_ft',
    'sq_mtr',
    'bigha',
    'katha',
    'marla',
    'kanal',
    'guntha',
    'ground',
    'cent',
    'decimal',
    'biswa',
    'ankanam',
  ],
  'residential': [
    'sq_ft',
    'sq_mtr',
    'sq_yards',
    'marla',
    'kanal',
    'ground',
    'cent',
  ],
  'commercial': ['sq_ft', 'sq_mtr', 'sq_yards', 'acres', 'guntha', 'kanal'],
  'pg/Co-living': ['sq_ft', 'sq_mtr'],
  'others': [
    'sq_ft',
    'sq_mtr',
    'sq_yards',
    'acres',
    'hectares',
    'bigha',
    'katha',
    'marla',
    'kanal',
    'guntha',
    'ground',
    'cent',
    'decimal',
    'biswa',
    'ankanam',
  ],
};

/// Source: utils/areaUnits.ts DEFAULT_UNIT_BY_PROPERTY_TYPE
const Map<String, String> kDefaultAreaUnitByPropertyType = {
  'land': 'acres',
  'residential': 'sq_ft',
  'commercial': 'sq_ft',
  'pg/Co-living': 'sq_ft',
  'others': 'sq_ft',
};
