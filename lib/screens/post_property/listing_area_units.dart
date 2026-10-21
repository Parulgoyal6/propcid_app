import '../../providers/post_property_provider.dart';
import 'listing_constants.dart';

/// Area-unit options for [category], as `(value, label)` pairs.
///
/// Mirrors React's `getAreaUnitsForPropertyType` (utils/areaUnits.ts:95): the
/// offered units depend on the category — land gets all 15, PG only sq_ft and
/// sq_mtr — so this is not one flat list.
///
/// Shared by the Dimensions step (total area) and the Pricing step (rate per
/// area), which is exactly how React shares it. [stored] is appended when it is
/// not part of the canonical set, so a value written by an older build cannot
/// crash a DropdownButton, which asserts when its value has no matching item.
List<(String, String)> areaUnitsFor(
  PropertyCategory? category, [
  String stored = '',
]) {
  final String key = switch (category) {
    PropertyCategory.land => 'land',
    PropertyCategory.commercial => 'commercial',
    PropertyCategory.pg => 'pg/Co-living',
    PropertyCategory.other => 'others',
    _ => 'residential',
  };
  final List<String> ids =
      kAreaUnitsByPropertyType[key] ?? const <String>['sq_ft'];

  final units = <(String, String)>[
    for (final id in ids) (id, kAreaUnitLabels[id] ?? id),
  ];
  if (stored.isNotEmpty && !ids.contains(stored)) {
    units.add((stored, kAreaUnitLabels[stored] ?? stored));
  }
  return units;
}

/// The category's default area unit, per React's
/// `DEFAULT_UNIT_BY_PROPERTY_TYPE`.
String defaultAreaUnitFor(PropertyCategory? category) {
  final String key = switch (category) {
    PropertyCategory.land => 'land',
    PropertyCategory.commercial => 'commercial',
    PropertyCategory.pg => 'pg/Co-living',
    PropertyCategory.other => 'others',
    _ => 'residential',
  };
  return kDefaultAreaUnitByPropertyType[key] ?? 'sq_ft';
}
