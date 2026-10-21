// core/utils/property_area_formatter.dart
//
// The single, canonical formatter for a listing's displayed area + unit.
//
// Before this file existed, every display site (detail page, property
// cards, search result facts, the Review step) read `PropertyModel.sqft` —
// an `int`, rounded from the raw `properties.area` text column — and
// hard-coded the literal suffix "sqft" regardless of what unit the listing
// actually used. That lost precision for any decimal area (0.25 Acres
// became "0 sqft"; 1200.5 Square Feet became "1200 sqft" or "1201 sqft"
// depending on rounding direction) and mislabeled every unit besides Square
// Feet (Land alone offers 15: acres, hectares, bigha, ... — see
// listing_area_units.dart). Every call site now goes through the one
// function below, so none of them can disagree with each other again.
library;

import '../../models/property_model.dart';
import '../../screens/post_property/listing_constants.dart'
    show kAreaUnitLabels;

/// Formats [property]'s area for display: exact decimal value (not the
/// rounded `sqft` int) paired with its real unit label — falling back to
/// the rounded int and the literal "sqft" suffix only when [property]
/// carries no [PropertyModel.areaValue]/[PropertyModel.areaUnit] at all
/// (e.g. older cached JSON built before those fields existed).
String formatPropertyArea(PropertyModel property) {
  final double value = property.areaValue ?? property.sqft.toDouble();
  final String unitLabel = (property.areaUnit == null)
      ? 'sqft'
      : (kAreaUnitLabels[property.areaUnit] ?? property.areaUnit!);
  return '${_formatAreaNumber(value)} $unitLabel';
}

/// Same as [formatPropertyArea] but without the unit suffix, for call sites
/// that render the unit separately (e.g. as a smaller trailing label).
String formatPropertyAreaValue(PropertyModel property) =>
    _formatAreaNumber(property.areaValue ?? property.sqft.toDouble());

/// A bare area number for `sq_ft` (the near-universal default, where a bare
/// number was always unambiguous and already fits the tight, non-wrapping
/// layouts some property cards use), and `formatPropertyArea`'s full
/// "value Unit" form for anything else (chiefly Land's many non-sq_ft
/// units, where a bare number is actively misleading, e.g. "2500" read as
/// square feet when it was actually 2500 Acres). Deliberately conservative:
/// only grows the string where the existing bare-number display would be
/// wrong, not just imprecise, to avoid new overflow risk in layouts with no
/// text-wrapping/ellipsis protection.
String formatPropertyAreaCompact(PropertyModel property) {
  final isDefaultUnit =
      property.areaUnit == null || property.areaUnit == 'sq_ft';
  return isDefaultUnit
      ? _formatAreaNumber(property.areaValue ?? property.sqft.toDouble())
      : formatPropertyArea(property);
}

/// Trims a decimal area to at most 2 places, dropping trailing zeros and a
/// bare integer's decimal point entirely (2.0 → "2", 2.75 → "2.75",
/// 1200.5 → "1200.5", 0.25 → "0.25").
String _formatAreaNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  final fixed = value.toStringAsFixed(2);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
