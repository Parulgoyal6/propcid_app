// Regression guard for the area-precision/unit fix: PropertyModel.sqft is an
// `int` (rounded), which silently lost precision for any decimal area
// (0.25 Acres -> "0 sqft") and every display site hardcoded the literal
// suffix "sqft" regardless of the listing's actual unit (Land alone offers
// 15). `PropertyModel.areaValue`/`areaUnit` plus `formatPropertyArea`/
// `formatPropertyAreaCompact` fix both, additively, without touching `sqft`.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/core/utils/property_area_formatter.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/screens/search/widgets/property_card_facts.dart';

PropertyModel _property({
  required String area,
  String? areaUnit,
  String category = 'land',
  int? beds,
  int? baths,
}) {
  return PropertyModel.fromSupabase({
    'id': 'p-1',
    'title': 'Test listing',
    'location': 'Test Location',
    'price': '1000000',
    'area': area,
    'area_unit': areaUnit,
    'category': category,
    if (category == 'residential' && (beds != null || baths != null))
      'properties_residential': {
        'bedrooms': beds ?? 0,
        'bathrooms': baths ?? 0,
      },
  });
}

void main() {
  group('formatPropertyArea — decimal precision', () {
    test('0.25 Acres remains 0.25 Acres, not rounded to 0', () {
      final p = _property(area: '0.25', areaUnit: 'acres');
      expect(formatPropertyArea(p), '0.25 Acres');
    });

    test('2.75 Acres remains 2.75 Acres', () {
      final p = _property(area: '2.75', areaUnit: 'acres');
      expect(formatPropertyArea(p), '2.75 Acres');
    });

    test('1200.5 Square Feet remains 1200.5, not rounded', () {
      final p = _property(area: '1200.5', areaUnit: 'sq_ft', category: 'residential');
      expect(formatPropertyArea(p), '1200.5 Square Feet');
    });

    test('a whole-number area has no trailing decimal point', () {
      final p = _property(area: '1200', areaUnit: 'sq_ft');
      expect(formatPropertyArea(p), '1200 Square Feet');
    });
  });

  group('formatPropertyArea — unit labels', () {
    test('an unrecognized unit id falls back to itself verbatim', () {
      final p = _property(area: '10', areaUnit: 'some_new_unit');
      expect(formatPropertyArea(p), '10 some_new_unit');
    });

    test('no areaUnit at all falls back to the literal "sqft"', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test listing',
        'location': 'Test Location',
        'price': '1000000',
        'area': '1200',
        'category': 'residential',
      });
      expect(formatPropertyArea(p), '1200 sqft');
    });
  });

  group('formatPropertyAreaCompact — conservative, overflow-safe cards', () {
    test('sq_ft (the default) stays a bare number, unchanged from before', () {
      final p = _property(area: '1200', areaUnit: 'sq_ft');
      expect(formatPropertyAreaCompact(p), '1200');
    });

    test('a non-default unit grows to the full "value Unit" form', () {
      final p = _property(area: '2500', areaUnit: 'acres');
      expect(formatPropertyAreaCompact(p), '2500 Acres');
    });

    test('a decimal non-default-unit area keeps its precision too', () {
      final p = _property(area: '0.25', areaUnit: 'acres');
      expect(formatPropertyAreaCompact(p), '0.25 Acres');
    });
  });

  group('propertyFactsLine — search result cards', () {
    test('a decimal area under 1 no longer vanishes entirely', () {
      final p = _property(
        area: '0.25',
        areaUnit: 'acres',
        category: 'land',
      );
      // 0.25 rounds to sqft == 0, which used to read as "no area at all".
      expect(propertyFactsLine(p), contains('0.25 Acres'));
    });

    test('the default sq_ft unit keeps its exact prior wording', () {
      final p = _property(
        area: '1200',
        areaUnit: 'sq_ft',
        category: 'residential',
        beds: 2,
        baths: 2,
      );
      expect(propertyFactsLine(p), '2 Bed · 2 Bath · 1200 sqft');
    });

    test('a non-default unit is labelled instead of assumed sqft', () {
      final p = _property(area: '5', areaUnit: 'acres', category: 'land');
      expect(propertyFactsLine(p), '5 Acres');
    });
  });
}
