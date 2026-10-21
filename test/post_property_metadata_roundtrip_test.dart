// Phase 0 regression guard — metadata integrity across an in-app edit.
//
// Protects the NEW-1 fix (final-architecture-review.md): before it, editing a
// web-created listing in Flutter destroyed every metadata key the app's form
// does not collect, because hydration read only ~39 named keys while the write
// path replaced the whole column with a freshly built blob.
//
// The provider half is testable in isolation (no Supabase needed): hydrate a
// web-shaped row, then assert the bag carries the keys forward. The merge half
// lives in PropertyService.updateProperty and is asserted here as a pure
// spread over the rebuilt blob, matching what that method now does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';

/// A listing as the React web app would have written it: rich metadata,
/// including blocks the Flutter form has no inputs for yet.
Map<String, dynamic> webCreatedRow() => {
      'category': 'commercial',
      'property_type': 'rent',
      'title': 'Web-created commercial unit',
      'description': 'Created on the website, edited in the app.',
      'location': 'MG Road',
      'price': '250000',
      'area': '4200',
      'area_unit': 'sq_ft',
      'media_urls': <String>['https://example.com/a.jpg'],
      'metadata': <String, dynamic>{
        // Named keys the provider already hydrated before Phase 0.
        'city': 'Bengaluru',
        'state': 'Karnataka',
        'pincode': '560001',
        'brokerage': '50000',
        // Canonical React keys for the two corrected mappings.
        'maintenanceCharges': '8000',
        'allInclusivePriceToggle': true,
        'tokenAmount': '25000',
        // Bag-only keys: no Flutter input collects these today.
        'commercialSubType': 'IT Park',
        'buildingClass': 'A',
        'propertyOn': 'Second Floor+',
        'workingDays': 'Mon-Sat',
        'liftCount': '4',
        'courtCasePending': false,
        'jamabandiAvailable': true,
        'pgHouseRules': <String>['No smoking', 'No pets'],
        'tenantPreference': <String>['Company Lease'],
        // Nested object: preserved by merge, never hydrated into the bag.
        'buildingInventory': <String, dynamic>{
          'buildingName': 'Tower A',
          'buildingCode': 'TA-01',
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

  group('Phase 0 — metadata survives an in-app edit', () {
    test('bag-only scalar/bool/list keys hydrate instead of being dropped', () {
      final row = webCreatedRow();
      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: row,
      );

      expect(provider.text('commercialSubType'), 'IT Park');
      expect(provider.text('buildingClass'), 'A');
      expect(provider.text('propertyOn'), 'Second Floor+');
      expect(provider.text('liftCount'), '4');
      expect(provider.boolVal('jamabandiAvailable'), isTrue);
      expect(provider.boolVal('courtCasePending'), isFalse);
      expect(provider.listVal('pgHouseRules'), ['No smoking', 'No pets']);
      expect(provider.listVal('tenantPreference'), ['Company Lease']);
    });

    test('named-owned keys do not leak into the bag (no double source)', () {
      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: webCreatedRow(),
      );

      for (final key in const [
        'city',
        'state',
        'pincode',
        'brokerage',
        'maintenanceCharges',
        'tokenAmount',
        'allInclusivePriceToggle',
      ]) {
        expect(provider.allTextFields.containsKey(key), isFalse,
            reason: '$key is owned by a named field, must not be in _text');
        expect(provider.allBoolFields.containsKey(key), isFalse,
            reason: '$key is owned by a named field, must not be in _bool');
      }
    });

    test('nested objects are NOT hydrated into the bag', () {
      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: webCreatedRow(),
      );

      expect(provider.allTextFields.containsKey('buildingInventory'), isFalse);
      expect(provider.allBoolFields.containsKey('buildingInventory'), isFalse);
      expect(provider.allListFields.containsKey('buildingInventory'), isFalse);
    });

    test('canonical keys hydrate into their named fields', () {
      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: webCreatedRow(),
      );

      expect(provider.maintenanceCharges, '8000');
      expect(provider.allInclusivePriceToggle, isTrue);
      expect(provider.bookingAmount, '25000');
    });

    test('legacy keys from older app builds still hydrate', () {
      final row = webCreatedRow();
      final meta = row['metadata'] as Map<String, dynamic>
        ..remove('maintenanceCharges')
        ..remove('allInclusivePriceToggle')
        ..['maintenanceAmount'] = '7777'
        ..['allInclusivePrice'] = true;
      row['metadata'] = meta;

      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: row,
      );

      expect(provider.maintenanceCharges, '7777');
      expect(provider.allInclusivePriceToggle, isTrue);
    });

    test('merge-on-update loses no key, and nested objects survive', () {
      final original =
          Map<String, dynamic>.from(webCreatedRow()['metadata'] as Map);

      provider.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: webCreatedRow(),
      );

      // What updateProperty now writes: existing blob spread under the rebuilt
      // one. The rebuilt blob is approximated by the hydrated bag, which is
      // exactly what _buildMetadata flushes into it.
      final rebuilt = <String, dynamic>{
        ...provider.allTextFields,
        ...provider.allBoolFields,
        ...provider.allListFields,
      };
      final merged = <String, dynamic>{...original, ...rebuilt};

      for (final key in original.keys) {
        expect(merged.containsKey(key), isTrue,
            reason: 'metadata key "$key" was lost across an app edit');
      }
      expect(merged['buildingInventory'], original['buildingInventory']);
    });

    test(
      'clearing state/pincode/landmark during an edit actually clears them',
      () {
        final original = Map<String, dynamic>.from(
          webCreatedRow()['metadata'] as Map,
        )..addAll({'landmark': 'Near Metro Station'});

        provider.initFromRawData(
          editingPropertyId: 'prop-1',
          propertyRow: webCreatedRow()..['metadata'] = original,
        );
        expect(provider.state, 'Karnataka');
        expect(provider.pincode, '560001');
        expect(provider.landmark, 'Near Metro Station');

        // The user clears all three in the edit wizard.
        provider.setState('');
        provider.setPincode('');
        provider.setLandmark('');

        // Mirrors PropertyService._buildMetadata's fixed behavior for these
        // four fields: always written, never omitted when blank — see the
        // comment at that write site. Before the fix, the guard was
        // `if (provider.state.isNotEmpty) meta['state'] = provider.state`,
        // which would have left 'state' entirely out of `rebuilt` below,
        // and the merge then kept the stale 'Karnataka' from `original`.
        final rebuilt = <String, dynamic>{
          'city': provider.city,
          'state': provider.state,
          'pincode': provider.pincode,
          'landmark': provider.landmark,
        };
        final merged = <String, dynamic>{...original, ...rebuilt};

        expect(merged['state'], '');
        expect(merged['pincode'], '');
        expect(merged['landmark'], '');
      },
    );

    test(
      'a whole-number double subtype column ("2.0") hydrates as a clean int string',
      () {
        final row = webCreatedRow()..['category'] = 'residential';
        provider.initFromRawData(
          editingPropertyId: 'prop-1',
          propertyRow: row,
          subtableRow: {
            // Simulates Postgres/PostgREST handing back a `numeric` column
            // as a Dart double rather than an int — see PropertyModel
            // .fromSupabase's own coercion comment for first-party
            // confirmation this shape occurs for these exact columns.
            'bedrooms': 2.0,
            'bathrooms': 1.0,
            'balconies': 0.0,
            'parking_spaces': 2.0,
          },
        );

        // Not "2.0" — which would fail a later `int.tryParse` on save and
        // silently null the column.
        expect(provider.bedrooms, '2');
        expect(provider.bathrooms, '1');
        expect(provider.balconies, '0');
        expect(provider.coveredParking, '2');
      },
    );

    test(
      'a known boolean bag key hydrates from a historical non-bool shape',
      () {
        final row = webCreatedRow()
          ..['category'] = 'pg_coliving'
          ..['metadata'] = <String, dynamic>{
            // Real Dart bool — already worked.
            'cctvCoverage': true,
            // Historical shapes `_safeBool` already proves occur in real
            // data, but which the bag hydration's old strict `value is
            // bool` check silently routed into `_text` instead, reading
            // back as unset/false in the edit wizard.
            'vegFoodPg': 'true',
            'studentsAllowed': 1,
            'maleAllowed': 'yes',
            // A genuinely numeric bag field must NOT be reinterpreted as a
            // bool just because its value happens to look boolean-ish —
            // confirms the fix is keyed on a closed, known-boolean list,
            // not a value-shape guess.
            'numberOfCabins': '1',
          };

        provider.initFromRawData(editingPropertyId: 'prop-1', propertyRow: row);

        expect(provider.boolVal('cctvCoverage'), isTrue);
        expect(provider.boolVal('vegFoodPg'), isTrue);
        expect(provider.boolVal('studentsAllowed'), isTrue);
        expect(provider.boolVal('maleAllowed'), isTrue);
        expect(provider.text('numberOfCabins'), '1');
        expect(provider.allBoolFields.containsKey('numberOfCabins'), isFalse);
      },
    );
  });
}
