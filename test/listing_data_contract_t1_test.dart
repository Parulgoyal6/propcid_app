// T1 data-contract regression guard.
//
// Covers final-architecture-review Q14 item 3: NEW-4 typed-empty semantics,
// the sq_mtr / area-unit migration, and the residential subtype strings —
// plus a list-of-objects hydration defect T1 found in the Phase 0 code.
//
// The typed-empty fill and Phase 0's merge interact dangerously: filling a
// nested-object key with '' would let the merge overwrite a real
// buildingInventory with an empty string, re-creating exactly the data loss
// Phase 0 fixed. That interaction is asserted explicitly below.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';
import 'package:propcid_app/screens/post_property/listing_value_aliases.dart';

/// A row written by an older Flutter build: legacy enum spellings, and
/// metadata holding structures the form does not collect.
Map<String, dynamic> legacyAppRow() => {
      'category': 'residential',
      'property_type': 'sell',
      'title': 'Legacy app listing',
      'area': '1200',
      'area_unit': 'sq_m', // legacy spelling
      'residential_subtype': 'Studio Apartment', // legacy spelling
      'metadata': <String, dynamic>{
        'city': 'Pune',
        'maintenanceAmount': '4500', // legacy key
        'allInclusivePrice': true, // legacy key
        'commercialSubType': 'IT Park',
        'suitableFor': <String>['Office', 'Retail'],
        // Array OF OBJECTS — must not be stringified into the bag.
        'floorWiseRoomDetails': <dynamic>[
          {'floor': 1, 'rooms': {'single': 2, 'double': 1}},
          {'floor': 2, 'rooms': {'single': 4}},
        ],
        'buildingInventory': <String, dynamic>{
          'buildingName': 'Tower A',
          'totalFloorsBuilding': '12',
        },
      },
    };

void main() {
  late PostPropertyProvider provider;

  setUp(() {
    WidgetsFlutterBinding.ensureInitialized();
    provider = PostPropertyProvider();
  });

  group('Value aliases applied on read', () {
    test('legacy area unit and subtype canonicalise on hydration', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      expect(provider.areaUnit, 'sq_mtr');
      expect(provider.residentialSubType, 'Studio / Service Apartment');
    });

    test('already-canonical and unknown values pass through untouched', () {
      final row = legacyAppRow()
        ..['area_unit'] = 'acres'
        ..['residential_subtype'] = 'Row House'; // deliberately unresolved

      provider.initFromRawData(editingPropertyId: 'p1', propertyRow: row);

      expect(provider.areaUnit, 'acres');
      expect(provider.residentialSubType, 'Row House');
    });
  });

  group('List-of-objects hydration (defect found in Phase 0 code)', () {
    test('array of maps is NOT stringified into the bag', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      // Before the fix this became ['{floor: 1, rooms: {...}}', ...] and would
      // have been written back as mangled strings, corrupting the structure.
      expect(provider.allListFields.containsKey('floorWiseRoomDetails'), isFalse,
          reason: 'list of objects must be left to the merge, not the bag');
    });

    test('array of scalars still hydrates normally', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      expect(provider.listVal('suitableFor'), ['Office', 'Retail']);
    });

    test('nested map still skipped', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      expect(provider.allTextFields.containsKey('buildingInventory'), isFalse);
    });
  });

  group('NEW-4 typed-empty semantics', () {
    // _fillTypedEmpties is private to PropertyService; these assert the rule it
    // implements, over the same allow-list, so a change to either side shows up.
    Map<String, dynamic> fillTypedEmpties(Map<String, dynamic> meta) {
      for (final key in kAllReactMetadataKeys) {
        if (kNestedObjectMetadataKeys.contains(key)) continue;
        meta.putIfAbsent(key, () => '');
      }
      return meta;
    }

    test('every non-nested allow-list key exists after filling', () {
      final meta = fillTypedEmpties(<String, dynamic>{});
      for (final key in kAllReactMetadataKeys) {
        if (kNestedObjectMetadataKeys.contains(key)) continue;
        expect(meta.containsKey(key), isTrue, reason: 'missing key "$key"');
      }
    });

    test('the default is an empty STRING, matching React dbText', () {
      final meta = fillTypedEmpties(<String, dynamic>{});
      expect(meta['tenantPreference'], '');
      expect(meta['courtCasePending'], '');
    });

    test('existing values are never downgraded to blanks', () {
      final meta = fillTypedEmpties(<String, dynamic>{
        'brokerage': '50000',
        'courtCasePending': false,
        'suitableFor': <String>['Office'],
      });

      expect(meta['brokerage'], '50000');
      expect(meta['courtCasePending'], isFalse);
      expect(meta['suitableFor'], ['Office']);
    });

    test('nested-object keys are NOT filled — this guards the Phase 0 merge',
        () {
      final meta = fillTypedEmpties(<String, dynamic>{});

      // If these were filled with '', the update-time merge
      // {...existing, ...new} would overwrite a real nested object with an
      // empty string — the exact destruction Phase 0 fixed.
      expect(meta.containsKey('buildingInventory'), isFalse);
      expect(meta.containsKey('pgHouseRules'), isFalse);
    });

    test('FILL-AFTER-MERGE preserves every non-scalar the provider cannot hold',
        () {
      // This is the ordering PropertyService.updateProperty uses:
      //   _fillTypedEmpties({...existing, ..._buildMetadata()})
      final existing = <String, dynamic>{
        'buildingInventory': {'buildingName': 'Tower A'},
        'pgHouseRules': {'smoking': false},
        'floorWiseRoomDetails': <dynamic>[
          {'floor': 1, 'rooms': {'single': 2}},
        ],
        'brokerage': '9000',
      };
      final rebuilt = <String, dynamic>{'brokerage': '12000'};

      final merged = fillTypedEmpties(<String, dynamic>{...existing, ...rebuilt});

      expect(merged['buildingInventory'], {'buildingName': 'Tower A'});
      expect(merged['pgHouseRules'], {'smoking': false});
      expect(merged['floorWiseRoomDetails'], existing['floorWiseRoomDetails']);
      expect(merged['brokerage'], '12000'); // fresh value wins
    });

    test('FILL-BEFORE-MERGE would destroy an array of objects', () {
      // Documents why the ordering above is load-bearing rather than stylistic.
      // floorWiseRoomDetails is in the allow-list but is NOT a nested-object
      // key, so filling before the merge blanks it and the merge then writes
      // that blank over the real array.
      final existing = <String, dynamic>{
        'floorWiseRoomDetails': <dynamic>[
          {'floor': 1, 'rooms': {'single': 2}},
        ],
      };
      final wrong = <String, dynamic>{
        ...existing,
        ...fillTypedEmpties(<String, dynamic>{}),
      };

      expect(wrong['floorWiseRoomDetails'], '',
          reason: 'demonstrates the destruction the real ordering avoids');
    });
  });

  group('Round-trip stability', () {
    test('canonicalising twice is a no-op', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      expect(canonicalAreaUnit(provider.areaUnit), provider.areaUnit);
      expect(canonicalResidentialSubtype(provider.residentialSubType!),
          provider.residentialSubType);
    });

    test('Phase 0 legacy key fallbacks still work alongside T1', () {
      provider.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: legacyAppRow(),
      );

      expect(provider.maintenanceCharges, '4500');
      expect(provider.allInclusivePriceToggle, isTrue);
    });
  });
}
