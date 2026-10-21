// T6 residential-parity guard.
//
// Closes the residential half of migration-specification Task 3: the fields
// React renders for residential, the amenity arrays it writes, and the
// apartment-vs-house branching that decides which of those apply.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

PostPropertyProvider residential({
  String subtype = 'Flat',
  ListingIntent intent = ListingIntent.rent,
}) =>
    PostPropertyProvider()
      ..setCategory(PropertyCategory.residential)
      ..setListingIntent(intent)
      ..setResidentialSubType(subtype);

Set<String> blockers(PostPropertyProvider p, WizardStep step) {
  final i = p.visibleSteps.indexOf(step);
  return p.issuesForStep(i).map((e) => e.field).toSet();
}

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('propertyCondition is reachable for residential', () {
    test('the Condition step is hidden, so it must live on Dimensions', () {
      final p = residential();
      expect(p.visibleSteps.contains(WizardStep.condition), isFalse);
      // The rule fires on Dimensions...
      expect(blockers(p, WizardStep.dimensions), contains('propertyCondition'));
    });

    test('setting it clears the blocker', () {
      // Before T6 this was unsatisfiable: the only input was on the hidden
      // Condition step, so every residential listing was unpublishable.
      final p = residential()..setPropertyCondition('New');
      expect(
          blockers(p, WizardStep.dimensions), isNot(contains('propertyCondition')));
    });

    test('the options are React\'s canonical set', () {
      expect(kPropertyConditions.first, 'New');
      expect(kPropertyConditions, contains('Resale'));
      expect(kPropertyConditions, contains('Under Construction'));
    });
  });

  group('Apartment vs house field branching', () {
    test('apartment requires floorNo, not builtUpArea', () {
      final p = residential(subtype: 'Flat');
      final b = blockers(p, WizardStep.dimensions);
      expect(b, contains('floorNo'));
      expect(b, isNot(contains('builtUpArea')));
    });

    test('house requires builtUpArea, not floorNo', () {
      final p = residential(subtype: 'Villa / Kothi');
      final b = blockers(p, WizardStep.dimensions);
      expect(b, contains('builtUpArea'));
      expect(b, isNot(contains('floorNo')));
    });

    test('builtUpArea is now collectable, so it genuinely blocks', () {
      // It was in kFieldsNotYetCollectable before T6, so the rule was gated
      // off and a house could be saved without it.
      expect(kFlutterCollectableFields, contains('builtUpArea'));
      final p = residential(subtype: 'Bungalow')
        ..setText('builtUpArea', '1800');
      expect(blockers(p, WizardStep.dimensions), isNot(contains('builtUpArea')));
    });

    test('apartment rent requires societyCharges instead of maintenance', () {
      final p = residential(subtype: 'Flat', intent: ListingIntent.rent);
      final b = blockers(p, WizardStep.pricing);
      expect(b, contains('societyCharges'));
      expect(b, isNot(contains('maintenanceCharges')));

      p.setText('societyCharges', '3000');
      expect(blockers(p, WizardStep.pricing),
          isNot(contains('societyCharges')));
    });

    test('house rent requires maintenance instead of societyCharges', () {
      final p = residential(subtype: 'Duplex House', intent: ListingIntent.rent);
      final b = blockers(p, WizardStep.pricing);
      expect(b, contains('maintenanceCharges'));
      expect(b, isNot(contains('societyCharges')));
    });

    test('neither applies on a sale', () {
      final p = residential(subtype: 'Flat', intent: ListingIntent.sell);
      final b = blockers(p, WizardStep.pricing);
      expect(b, isNot(contains('societyCharges')));
      expect(b, isNot(contains('maintenanceCharges')));
    });
  });

  group('Amenities', () {
    test('all three residential lists write to one shared array', () {
      // React toggles society / flat / parking into formData.amenities, which
      // is what the web's amenity filters read.
      final p = residential();
      p.setListVal('amenities', ['Lift', 'Modular Kitchen', 'Bike Parking']);

      expect(p.listVal('amenities'),
          containsAll(<String>['Lift', 'Modular Kitchen', 'Bike Parking']));
      expect(kResidentialSocietyAmenities, contains('Lift'));
      expect(kResidentialFlatAmenities, contains('Modular Kitchen'));
      expect(kResidentialParkingAmenities, contains('Bike Parking'));
    });

    test('the amenities rule is satisfied by any one selection', () {
      final p = residential();
      expect(blockers(p, WizardStep.amenities), contains('amenities'));

      p.setListVal('amenities', ['Lift']);
      expect(blockers(p, WizardStep.amenities), isNot(contains('amenities')));
    });

    test('tenant preferences are booleans, not amenities', () {
      final p = residential();
      for (final pref in kResidentialTenantPreferences) {
        expect(p.boolVal(pref.id), isFalse);
      }
      p.setBoolVal('familyAllowed', true);
      expect(p.boolVal('familyAllowed'), isTrue);
      // They must not leak into the shared array.
      expect(p.listVal('amenities'), isEmpty);
    });

    test('tenant preference ids are the canonical metadata keys', () {
      expect(kResidentialTenantPreferences.map((o) => o.id).toList(), [
        'familyAllowed', 'bachelorAllowed', 'companyLeaseAllowed',
        'petsAllowed', 'smokingAllowed', 'vegetariansOnly',
      ]);
    });
  });

  group('amenities column round-trip', () {
    test('hydrates from the properties.amenities column', () {
      // It is a real column, not metadata, so the bag flush never sees it —
      // without explicit hydration every edit would clear the listing.
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'rent',
          'amenities': <String>['Lift', 'Gym / Fitness Center'],
          'metadata': <String, dynamic>{},
        },
      );

      expect(p.listVal('amenities'), ['Lift', 'Gym / Fitness Center']);
    });

    test('an empty column leaves the array empty', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'rent',
          'amenities': <String>[],
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.listVal('amenities'), isEmpty);
    });
  });

  group('Grandfathering still applies on edit', () {
    test('a hydrated listing reports no blockers for fields blank on load', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'rent',
          'metadata': <String, dynamic>{},
        },
      );
      // T2 behaviour, reconfirmed here because T6 adds newly-required fields
      // (propertyCondition, builtUpArea, societyCharges) that would otherwise
      // block every pre-existing residential listing from being re-saved.
      expect(blockers(p, WizardStep.dimensions), isEmpty);
      expect(p.grandfatheredBlankFields, contains('propertyCondition'));
    });
  });

  group('Residential subtypes', () {
    test('canonical set is React\'s ten, apartment group first', () {
      final canonical = [...kApartmentSubtypes, ...kHouseSubtypes];
      expect(canonical.length, 10);
      expect(canonical.take(3).toList(), [
        'Flat',
        'Independent / Builder Floor',
        'Studio / Service Apartment',
      ]);
    });

    test('a legacy value with a definitive mapping is aliased on read', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'rent',
          'residential_subtype': 'Studio Apartment',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.residentialSubType, 'Studio / Service Apartment');

      // ...and it now branches as an apartment, as React would. Checked on a
      // fresh provider: an edited listing grandfathers its blank fields (T2),
      // so blockers are deliberately empty there.
      final fresh = residential(subtype: p.residentialSubType!);
      expect(blockers(fresh, WizardStep.dimensions), contains('floorNo'));
      expect(blockers(fresh, WizardStep.dimensions),
          isNot(contains('builtUpArea')));
    });

    test('an unresolved value is preserved, never guessed', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'rent',
          'residential_subtype': 'Row House',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.residentialSubType, 'Row House');

      // Not in the apartment group, so it takes the house branch.
      final fresh = residential(subtype: 'Row House');
      expect(blockers(fresh, WizardStep.dimensions), contains('builtUpArea'));
      expect(blockers(fresh, WizardStep.dimensions), isNot(contains('floorNo')));
    });
  });

  group('Residential no longer has unreachable required fields', () {
    test('every blocking rule can be satisfied through the UI', () {
      final p = residential(subtype: 'Flat', intent: ListingIntent.rent);

      final everyBlocker = <String>{
        for (final step in p.visibleSteps)
          ...p.issuesForStep(p.visibleSteps.indexOf(step)).map((e) => e.field),
      };

      // Anything reported as blocking must be a field the wizard can fill.
      for (final f in everyBlocker) {
        expect(kFlutterCollectableFields, contains(f),
            reason: '$f blocks residential but has no input');
      }
    });
  });
}
