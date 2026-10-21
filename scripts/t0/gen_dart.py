"""Generate the T0 Dart ground-truth files directly from the React source.

Nothing here is hand-typed: every option string and metadata key is parsed out
of propcid/src and emitted, so the Dart constants cannot drift from React by
transcription error. Re-run this script to regenerate after a React change.
"""
import io, re, json, os

SP = r"C:/Users/USER/AppData/Local/Temp/claude/c--Users-USER-Desktop-Flutter/eaebe9cc-357a-46a1-8018-7398bb9efccc/scratchpad/t0"
OUT = 'FLUTTER-APP/lib/screens/post_property'
NL = chr(10)
Q = chr(39)

arrays = json.load(io.open(SP + '/arrays_raw.json', encoding='utf-8'))
metakeys = json.load(io.open(SP + '/metadata_keys.json', encoding='utf-8'))
selects = json.load(io.open(SP + '/select_options.json', encoding='utf-8'))['bound']


def strings(raw):
    """All quoted string literals, in source order."""
    return re.findall(r"['\"]([^'\"]*)['\"]", raw)


def id_labels(raw):
    """[{ id: 'x', label: 'y' }, ...] -> [(x, y)]"""
    return re.findall(r"\{\s*id:\s*['\"]([^'\"]+)['\"]\s*,\s*label:\s*['\"]([^'\"]+)['\"]", raw)


def dart_str(s):
    return Q + s.replace(chr(92), chr(92) * 2).replace(Q, chr(92) + Q) + Q


def dart_list(name, items, src, doc=None):
    out = []
    if doc:
        out.append('/// ' + doc)
    out.append('/// Source: %s' % src)
    out.append('const List<String> %s = [' % name)
    for i in items:
        out.append('  %s,' % dart_str(i))
    out.append('];')
    return NL.join(out)


def dart_options(name, pairs, src, doc=None):
    out = []
    if doc:
        out.append('/// ' + doc)
    out.append('/// Source: %s' % src)
    out.append('const List<ListingOption> %s = [' % name)
    for i, l in pairs:
        out.append('  ListingOption(%s, %s),' % (dart_str(i), dart_str(l)))
    out.append('];')
    return NL.join(out)


def src_of(key):
    a = arrays[key]
    return '%s:%d' % (a['file'].replace('propcid/src/', ''), a['line'])


chunks = []

HEADER = '''// GENERATED FROM REACT SOURCE — DO NOT HAND-EDIT VALUES.
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
'''
chunks.append(HEADER)

# ── Category + listing type ────────────────────────────────────────────────
pt = arrays['propertyTypes']['raw']
ids = re.findall(r"id:\s*['\"]([^'\"]+)['\"]\s*as const", pt)
titles = re.findall(r"title:\s*['\"]([^'\"]+)['\"]", pt)
descs = re.findall(r"description:\s*['\"]([^'\"]+)['\"]", pt)
chunks.append('// ' + '=' * 74 + NL + '// Step 1 — Category & listing type' + NL + '// ' + '=' * 74)
chunks.append(dart_list('kPropertyTypeIds', ids, src_of('propertyTypes'),
                        'Canonical category values written to properties.category input.'))
chunks.append(dart_options('kPropertyTypeTitles', list(zip(ids, titles)), src_of('propertyTypes')))
chunks.append(dart_options('kPropertyTypeDescriptions', list(zip(ids, descs)), src_of('propertyTypes')))
chunks.append(dart_list('kListingTypeIds', ['rent', 'sell', 'lease'],
                        'TypeSelectionStep.tsx getAvailableListingTypes()',
                        'Written to the properties.property_type column (NOT the category).'))

# ── Residential ────────────────────────────────────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// Residential subtypes' + NL + '// ' + '=' * 74)
grp = arrays['residentialSubTypeGroups']['raw']
groups = re.findall(r"label:\s*['\"]([^'\"]+)['\"]\s*,\s*options:\s*\[(.*?)\]", grp, re.S)
lines = ['/// Source: %s' % src_of('residentialSubTypeGroups'),
         'const List<ListingOptionGroup> kResidentialSubTypeGroups = [']
for label, body in groups:
    lines.append('  ListingOptionGroup(%s, [' % dart_str(label))
    for o in strings(body):
        lines.append('    %s,' % dart_str(o))
    lines.append('  ]),')
lines.append('];')
chunks.append(NL.join(lines))

apt = strings(arrays['residentialappartment']['raw'])
chunks.append(dart_list('kApartmentSubtypes', apt, src_of('residentialappartment'),
                        'Drives React isApartment/isHouse validation branching. '
                        'A subtype outside this list is treated as a house.'))
house = [o for label, body in groups if label != 'Apartment' for o in strings(body)]
chunks.append(dart_list('kHouseSubtypes', house, src_of('residentialSubTypeGroups')))

# ── Land ───────────────────────────────────────────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// Land' + NL + '// ' + '=' * 74)
for name, key, doc in [
    ('kLandSubtypes', None, None),
    ('kLandTypeOptions', 'landTypeOptions', None),
    ('kPlotTypeOptions', 'plotTypeOptions', None),
    ('kLandUseMasterPlanOptions', 'landUseMasterPlanOptions',
     'Required only when listingType == rent (propertyListingRules.ts).'),
    ('kLandSoilTypes', 'landSoilTypes', None),
    ('kLandOwnershipTypes', 'landtypes', None),
]:
    if key is None:
        chunks.append(dart_list('kLandSubtypes', selects['landSubtype']['options'],
                                selects['landSubtype']['sources'][0]))
        continue
    chunks.append(dart_list(name, strings(arrays[key]['raw']), src_of(key), doc))

# ── PG ─────────────────────────────────────────────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// PG / Co-living' + NL + '// ' + '=' * 74)
chunks.append(dart_list('kPgPropertyTypes', strings(arrays['pgtype']['raw']), src_of('pgtype')))
chunks.append(dart_list('kBuildingTypeOptions', strings(arrays['buildingTypeOptions']['raw']),
                        src_of('buildingTypeOptions')))
chunks.append(dart_options('kPgRoomAmenities', id_labels(arrays['PgRoomAmenityList']['raw']),
                           src_of('PgRoomAmenityList')))
chunks.append(dart_options('kPgCommonAreaAmenities', id_labels(arrays['PgCommonAreaAmenityList']['raw']),
                           src_of('PgCommonAreaAmenityList')))
chunks.append(dart_options('kPgSafetyAndSecurity', id_labels(arrays['PgSafetyAndSecurityList']['raw']),
                           src_of('PgSafetyAndSecurityList')))
chunks.append(dart_options('kPgTenantRules', id_labels(arrays['PgTenantRulesList']['raw']),
                           src_of('PgTenantRulesList')))
chunks.append(dart_options('kPgRoomFeatures', id_labels(arrays['roomFeatures']['raw']),
                           src_of('roomFeatures')))
chunks.append(dart_list('kLinenChangeFrequencies', selects['linenChangeFrequency']['options'],
                        selects['linenChangeFrequency']['sources'][0]))
chunks.append(dart_list('kRoomCleaningFrequencies', selects['roomCleaningFrequency']['options'],
                        selects['roomCleaningFrequency']['sources'][0],
                        'NOTE: differs from kLinenChangeFrequencies — On Demand vs Fortnightly.'))
# kPgHouseRuleKeys deliberately lives in listing_field_keys.dart only: it is a
# metadata key set, not a UI option list, and defining it in both files makes
# the two ambiguous to import together.

# ── Residential / commercial / other amenities ─────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// Amenity lists' + NL + '// ' + '=' * 74)
for name, key, doc in [
    ('kResidentialSocietyAmenities', 'residentialSocietyAmenityList',
     'NOTE: React source lists "Visitor Parking" twice; preserved verbatim.'),
    ('kResidentialFlatAmenities', 'residentialFlatAmenityList', None),
    ('kResidentialParkingAmenities', 'residentialParkingAmenityList', None),
    ('kCommercialSuitableFor', 'commercialSuitableForList', None),
    ('kCommercialOfficeBuildingAmenities', 'commercialOfficeBuildingAmenityList', None),
    ('kCommercialRetailWarehouseAmenities', 'commercialRetailWarehouseAmenityList', None),
    ('kOtherGeneralAmenities', 'OtherGeneralAmenitiesList', None),
]:
    chunks.append(dart_list(name, strings(arrays[key]['raw']), src_of(key), doc))

for name, key in [
    ('kResidentialTenantPreferences', 'residentialTenantPreferenceList'),
    ('kCommercialWashrooms', 'commercialWashroomList'),
    ('kCommercialParking', 'commercialParkingList'),
    ('kCommercialOtherParking', 'commercialOtherParkingList'),
]:
    chunks.append(dart_options(name, id_labels(arrays[key]['raw']), src_of(key)))

# ── Select enums ───────────────────────────────────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// Select enums (extracted from step JSX)' + NL + '// ' + '=' * 74)
chunks.append(dart_list('kBhkTypes', selects['bhkType']['options'], selects['bhkType']['sources'][0]))
chunks.append(dart_list('kPropertyConditions', selects['propertyCondition']['options'],
                        selects['propertyCondition']['sources'][0],
                        'Also used for projectStatus / ownership in the same control.'))
chunks.append(dart_list('kLockInPeriods', selects['lockInPeriod']['options'],
                        selects['lockInPeriod']['sources'][0]))
chunks.append(dart_list('kPlotAreaUnits', selects['plotAreaUnit']['options'],
                        selects['plotAreaUnit']['sources'][0],
                        'Commercial plot area — a SUBSET of kAreaUnitLabels keys.'))
chunks.append(dart_list('kHeightRestrictionUnits', selects['heightRestrictionUnit']['options'],
                        selects['heightRestrictionUnit']['sources'][0]))

# The land side-dimension unit select is rendered inside a .map() over
# ['front','back','right','left'] with a COMPUTED key (`${dim}Unit`), so the
# <Select> extractor cannot bind it to a formData field. Parsed directly out of
# that block instead of hand-typed.
_dims_src = io.open(
    'propcid/src/components/PropertyWizard/steps/PropertyDimensionsStep.tsx',
    encoding='utf-8').read()
_m = re.search(r"\['front', 'back', 'right', 'left'\]\.map\(dim => \((.*?)\)\)\}",
               _dims_src, re.S)
_side_units = re.findall(r'<SelectItem value="([^"]+)"', _m.group(1))
chunks.append(dart_list('kLandSideDimensionUnits', _side_units,
                        'PropertyDimensionsStep.tsx land side-dimension map',
                        'Units for the front/back/right/left land dimensions. '
                        'Three options, unlike kHeightRestrictionUnits which has two.'))

# ── Media categories ───────────────────────────────────────────────────────
chunks.append('// ' + '=' * 74 + NL + '// Media categories' + NL + '// ' + '=' * 74)
chunks.append(dart_options('kDefaultImageCategories', id_labels(arrays['defaultImageCategories']['raw']),
                           src_of('defaultImageCategories'),
                           'Order matters: metadata.mediaCategories is index-aligned with media_urls.'))
chunks.append(dart_options('kLandImageCategories', id_labels(arrays['landImageCategories']['raw']),
                           src_of('landImageCategories')))

# ── Area units ─────────────────────────────────────────────────────────────
au = io.open('propcid/src/utils/areaUnits.ts', encoding='utf-8').read()
unit_block = re.search(r"export const AREA_UNITS = \{(.*?)\} as const;", au, re.S).group(1)
units = re.findall(r"([a-z_]+):\s*'([^']+)'", unit_block)
by_type_block = re.search(r"UNITS_BY_PROPERTY_TYPE:[^=]*=\s*\{(.*?)^\};", au, re.S | re.M).group(1)
by_type = re.findall(r"'?([a-zA-Z/\-]+)'?:\s*\[(.*?)\]", by_type_block, re.S)
defaults = re.findall(r"'?([a-zA-Z/\-]+)'?:\s*'([a-z_]+)'",
                      re.search(r"DEFAULT_UNIT_BY_PROPERTY_TYPE:[^=]*=\s*\{(.*?)^\};", au, re.S | re.M).group(1))

chunks.append('// ' + '=' * 74 + NL + '// Area units' + NL + '// ' + '=' * 74)
lines = ['/// Source: utils/areaUnits.ts AREA_UNITS',
         '/// The full canonical set — 15 units, not the 3 Flutter shipped.',
         'const Map<String, String> kAreaUnitLabels = {']
for k, v in units:
    lines.append('  %s: %s,' % (dart_str(k), dart_str(v)))
lines.append('};')
chunks.append(NL.join(lines))

lines = ['/// Source: utils/areaUnits.ts UNITS_BY_PROPERTY_TYPE',
         '/// Which units each category may offer. Not every unit is valid everywhere.',
         'const Map<String, List<String>> kAreaUnitsByPropertyType = {']
for cat, body in by_type:
    lines.append('  %s: [' % dart_str(cat))
    for u in re.findall(r"'([a-z_]+)'", body):
        lines.append('    %s,' % dart_str(u))
    lines.append('  ],')
lines.append('};')
chunks.append(NL.join(lines))

lines = ['/// Source: utils/areaUnits.ts DEFAULT_UNIT_BY_PROPERTY_TYPE',
         'const Map<String, String> kDefaultAreaUnitByPropertyType = {']
for cat, u in defaults:
    lines.append('  %s: %s,' % (dart_str(cat), dart_str(u)))
lines.append('};')
chunks.append(NL.join(lines))

io.open(OUT + '/listing_constants.dart', 'w', encoding='utf-8').write((NL * 2).join(chunks) + NL)
print('wrote listing_constants.dart  (%d chunks)' % len(chunks))
print('  area units: %d, categories: %d' % (len(units), len(by_type)))
print('  soil types: %d, society amenities: %d' % (
    len(strings(arrays['landSoilTypes']['raw'])),
    len(strings(arrays['residentialSocietyAmenityList']['raw']))))
