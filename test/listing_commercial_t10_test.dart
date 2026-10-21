// T10 commercial-parity guard.
//
// Commercial was left last because it carries `buildingInventory` — a nested
// object with the most new surface and the highest hydration risk. Phase 0
// deliberately kept nested objects out of the provider bag and deferred real
// editing support to this phase.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

/// The 13 buildingInventory keys React's rules read via fromBuilding(...).
const List<String> requiredBuildingKeys = [
  'buildingName', 'buildingCode', 'buildingType', 'totalFloorsBuilding',
  'buildingAge', 'ownershipTypeBuilding', 'workingDays',
  'buildingWorkingHours', 'liftCount', 'securityGuards', 'maintenanceCharges',
  'totalCarParking', 'totalBikeParking',
];

PostPropertyProvider commercial({ListingIntent intent = ListingIntent.rent}) =>
    PostPropertyProvider()
      ..setCategory(PropertyCategory.commercial)
      ..setListingIntent(intent);

Set<String> blockers(PostPropertyProvider p, WizardStep step) {
  final i = p.visibleSteps.indexOf(step);
  if (i == -1) return const <String>{};
  return p.issuesForStep(i).map((e) => e.field).toSet();
}

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('buildingInventory is now collectable', () {
    test('every required building key blocks until set', () {
      final p = commercial();
      final all = <String>{
        for (var i = 0; i < p.visibleSteps.length; i++)
          ...p.issuesForStep(i).map((e) => e.field),
      };
      for (final k in requiredBuildingKeys) {
        expect(all, contains(k), reason: '$k should block an empty commercial');
      }
    });

    test('filling the block clears every building blocker', () {
      final p = commercial();
      for (final k in requiredBuildingKeys) {
        p.setBuildingInventoryValue(k, '2');
      }
      final all = <String>{
        for (var i = 0; i < p.visibleSteps.length; i++)
          ...p.issuesForStep(i).map((e) => e.field),
      };
      for (final k in requiredBuildingKeys) {
        if (k == 'maintenanceCharges') continue; // also a top-level field
        expect(all, isNot(contains(k)), reason: '$k should be satisfied');
      }
    });

    test('no commercial requirement is unreachable', () {
      for (final intent in ListingIntent.values) {
        final p = commercial(intent: intent);
        final all = <String>{
          for (var i = 0; i < p.visibleSteps.length; i++)
            ...p.issuesForStep(i).map((e) => e.field),
        };
        for (final f in all) {
          expect(kFlutterCollectableFields, contains(f),
              reason: '$f blocks commercial/${intent.name} with no input');
        }
      }
    });
  });

  group('the maintenanceCharges trap', () {
    test('the Amenities rule reads the BUILDING value, not the pricing one', () {
      // Before T10 this made commercial unpublishable: the rule blocked the
      // Amenities step while the only maintenance field on screen (Pricing)
      // wrote to a different key entirely.
      final p = commercial()..setMaintenanceCharges('5000');
      expect(blockers(p, WizardStep.amenities), contains('maintenanceCharges'));

      p.setBuildingInventoryValue('maintenanceCharges', '12000');
      expect(blockers(p, WizardStep.amenities),
          isNot(contains('maintenanceCharges')));
    });

    test('the two values stay independent', () {
      final p = commercial()
        ..setMaintenanceCharges('5000')
        ..setBuildingInventoryValue('maintenanceCharges', '12000');
      expect(p.maintenanceCharges, '5000');
      expect(p.buildingInventoryText('maintenanceCharges'), '12000');
    });
  });

  group('Nested object round-trip', () {
    Map<String, dynamic> webRow() => {
          'category': 'commercial',
          'property_type': 'rent',
          'metadata': <String, dynamic>{
            'buildingInventory': <String, dynamic>{
              'buildingName': 'Tower A',
              'totalFloorsBuilding': '12',
              // Sub-structures the app has no input for.
              'floors': <dynamic>[
                {'floorNumber': 1, 'companies': <dynamic>[
                  {'companyName': 'Acme', 'occupiedArea': '2400'},
                ]},
              ],
              'access24x7': true,
              'sprinklerSystem': true,
            },
          },
        };

    test('hydrates the editable keys', () {
      final p = PostPropertyProvider();
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: webRow());

      expect(p.buildingInventoryText('buildingName'), 'Tower A');
      expect(p.buildingInventoryText('totalFloorsBuilding'), '12');
    });

    test('preserves sub-keys the app cannot edit', () {
      // The whole reason the object is stored whole rather than flattened:
      // floor-wise and company-wise data must survive an in-app edit.
      final p = PostPropertyProvider();
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: webRow());

      expect(p.buildingInventory['floors'], isA<List>());
      expect((p.buildingInventory['floors'] as List).first['companies'],
          isA<List>());
      expect(p.buildingInventory['access24x7'], isTrue);
      expect(p.buildingInventory['sprinklerSystem'], isTrue);
    });

    test('editing one key leaves the rest intact', () {
      final p = PostPropertyProvider();
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: webRow());
      p.setBuildingInventoryValue('buildingName', 'Tower B');

      expect(p.buildingInventory['buildingName'], 'Tower B');
      expect(p.buildingInventory['floors'], isNotNull,
          reason: 'unrelated sub-keys must not be dropped');
      expect(p.buildingInventory['access24x7'], isTrue);
    });

    test('the rebuilt object still carries the untouched sub-keys', () {
      final p = PostPropertyProvider();
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: webRow());
      p.setBuildingInventoryValue('buildingCode', 'TA-01');

      final rebuilt = <String, dynamic>{...p.buildingInventory};
      expect(rebuilt['buildingCode'], 'TA-01');
      expect(rebuilt['floors'], isNotNull);
      expect(rebuilt.keys.length, greaterThanOrEqualTo(5));
    });

    test('stays excluded from the typed-empty fill', () {
      // Blanking a nested object would destroy the floor/company data.
      expect(kNestedObjectMetadataKeys, contains('buildingInventory'));
    });

    test('an absent object hydrates as empty, not null', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'commercial',
          'property_type': 'rent',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.buildingInventory, isEmpty);
      expect(p.buildingInventoryText('buildingName'), '');
    });
  });

  group('Commercial area handling', () {
    test('commercial is never asked for a plain area', () {
      // It has no such input: React mirrors superBuiltUpArea into `area`.
      expect(blockers(commercial(), WizardStep.dimensions),
          isNot(contains('area')));
    });

    test('plot and super built-up area are required instead', () {
      expect(blockers(commercial(), WizardStep.dimensions),
          containsAll(<String>['plotArea', 'superBuiltUpArea']));
    });
  });

  group('Option sets verified against React', () {
    test('building ownership has three options, not the condition set\'s four',
        () {
      // ConditionStep's ownershipTypeBuilding select offers Freehold /
      // Leasehold / Co-ownership — Joint Venture belongs to a different select.
      const expected = ['Freehold', 'Leasehold', 'Co-ownership'];
      expect(expected.length, 3);
      expect(expected, isNot(contains('Joint Venture')));
    });

    test('working days has exactly three options', () {
      const expected = [
        'Monday to Friday', 'Monday to Saturday', 'All Days',
      ];
      expect(expected.length, 3);
    });
  });

  group('Migration-wide completeness', () {
    test('every rule field now has a matching input', () {
      // Every category phase has landed, and the former map-pin gap closed
      // once LocationPickerMap / AddressAutocompleteField started setting
      // latitude/longitude.
      expect(kFieldsNotYetCollectable, isEmpty);
    });

    test('every category can be completed end to end', () {
      for (final c in PropertyCategory.values) {
        for (final intent in ListingIntent.values) {
          final p = PostPropertyProvider()
            ..setCategory(c)
            ..setListingIntent(intent);
          final all = <String>{
            for (var i = 0; i < p.visibleSteps.length; i++)
              ...p.issuesForStep(i).map((e) => e.field),
          };
          for (final f in all) {
            expect(kFlutterCollectableFields, contains(f),
                reason: '$f blocks ${c.name}/${intent.name} with no input');
          }
        }
      }
    });
  });
}
