// Regression guard for two PropertyModel additive fixes:
//  1. `availableFromRaw` — `available_from` can hold the literal word
//     "Immediately" (the Dimensions step's "Immediately" checkbox), which
//     `DateTime.tryParse` silently returns null for, losing the signal
//     entirely rather than just its format.
//  2. `areaValue`/`areaUnit` — see property_area_formatter_test.dart for the
//     display-side coverage; this file covers the model's own parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/property_model.dart';

void main() {
  group('PropertyModel.availableFromRaw', () {
    test('preserves "Immediately" where availableFrom (DateTime) goes null', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'available_from': 'Immediately',
      });

      expect(p.availableFrom, isNull);
      expect(p.availableFromRaw, 'Immediately');
    });

    test('an actual date parses into availableFrom normally', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'available_from': '2026-03-01',
      });

      expect(p.availableFrom, DateTime.parse('2026-03-01'));
      expect(p.availableFromRaw, '2026-03-01');
    });

    test('absent available_from leaves both fields null', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
      });

      expect(p.availableFrom, isNull);
      expect(p.availableFromRaw, isNull);
    });

    test('round-trips through toJson/fromJson', () {
      final original = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'available_from': 'Immediately',
      });

      final restored = PropertyModel.fromJson(original.toJson());
      expect(restored.availableFromRaw, 'Immediately');
    });
  });

  group('PropertyModel.areaValue / areaUnit', () {
    test('areaValue preserves decimal precision sqft rounds away', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'area': '2.75',
        'area_unit': 'acres',
      });

      expect(p.sqft, 3); // rounded, unchanged legacy behavior
      expect(p.areaValue, 2.75); // exact
      expect(p.areaUnit, 'acres');
    });

    test('copyWith preserves areaValue/areaUnit when not overridden', () {
      final p = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'area': '0.25',
        'area_unit': 'acres',
      }).copyWith(title: 'Renamed');

      expect(p.title, 'Renamed');
      expect(p.areaValue, 0.25);
      expect(p.areaUnit, 'acres');
    });

    test('round-trips through toJson/fromJson', () {
      final original = PropertyModel.fromSupabase({
        'id': 'p-1',
        'title': 'Test',
        'location': 'Test Location',
        'price': '100000',
        'area': '1200.5',
        'area_unit': 'sq_ft',
      });

      final restored = PropertyModel.fromJson(original.toJson());
      expect(restored.areaValue, 1200.5);
      expect(restored.areaUnit, 'sq_ft');
    });
  });
}
