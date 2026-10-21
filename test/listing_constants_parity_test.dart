// T0 parity guard.
//
// migration-specification Task 0: "unit test asserting the Dart constant lists
// equal the React arrays (paste React arrays into the test as expected values)."
//
// The expected values below are typed independently of scripts/t0/gen_dart.py,
// read straight from the React source. That independence is the whole point: if
// the generator's parser is wrong, these assertions catch it. A test generated
// from the same extraction would only prove the extractor agrees with itself.
//
// Highest-risk values get exact literals — the enum strings that reach Postgres,
// where one differing character silently breaks web filters and reads. The long
// amenity lists get size + spot-check assertions instead of 47 transcribed
// strings, since transcribing those by hand is the very error the generator
// exists to prevent.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';
import 'package:propcid_app/screens/post_property/listing_value_aliases.dart';

void main() {
  group('Category & listing type', () {
    test('property type ids match React verbatim', () {
      // TypeSelectionStep.tsx:119 — note 'pg/Co-living' keeps its slash and
      // capital L, and 'others' is plural.
      expect(kPropertyTypeIds,
          ['land', 'residential', 'commercial', 'pg/Co-living', 'others']);
    });

    test('listing type ids match React verbatim', () {
      expect(kListingTypeIds, ['rent', 'sell', 'lease']);
    });
  });

  group('Residential subtypes', () {
    test('apartment subtypes match React verbatim', () {
      // PricingStep.tsx:19 / PropertyDimensionsStep.tsx — membership of this
      // list is what makes React treat a listing as isApartment rather than
      // isHouse, which changes required fields.
      expect(kApartmentSubtypes, [
        'Flat',
        'Independent / Builder Floor',
        'Studio / Service Apartment',
      ]);
    });

    test('house subtypes match React verbatim', () {
      expect(kHouseSubtypes, [
        'Raw / Independent House',
        'Villa / Kothi',
        'Duplex House',
        'Triplex House',
        'Pent House',
        'Bungalow',
        'Farm House',
      ]);
    });

    test('groups cover exactly the apartment + house sets', () {
      final flattened =
          kResidentialSubTypeGroups.expand((g) => g.options).toList();
      expect(flattened, [...kApartmentSubtypes, ...kHouseSubtypes]);
    });
  });

  group('Area units', () {
    test('canonical keys match React verbatim', () {
      // utils/areaUnits.ts:1 — 15 units. The migration specification's list
      // ('sq_ft, sq_mtr, sq_yd, acres, yards, ft, m') is wrong on three counts:
      // the canonical yard key is sq_yards, and yards/ft/m are not area units.
      expect(kAreaUnitLabels.keys.toList(), [
        'sq_ft', 'sq_mtr', 'sq_yards',
        'acres', 'hectares', 'bigha', 'katha', 'marla', 'kanal',
        'guntha', 'ground', 'cent', 'decimal', 'biswa', 'ankanam',
      ]);
    });

    test('sq_yd and sq_m are NOT canonical (they are Flutter legacy)', () {
      expect(kAreaUnitLabels.containsKey('sq_yd'), isFalse);
      expect(kAreaUnitLabels.containsKey('sq_m'), isFalse);
    });

    test('per-category unit sets match React', () {
      expect(kAreaUnitsByPropertyType['pg/Co-living'], ['sq_ft', 'sq_mtr']);
      expect(kAreaUnitsByPropertyType['residential'],
          ['sq_ft', 'sq_mtr', 'sq_yards', 'marla', 'kanal', 'ground', 'cent']);
      expect(kAreaUnitsByPropertyType['commercial'],
          ['sq_ft', 'sq_mtr', 'sq_yards', 'acres', 'guntha', 'kanal']);
      expect(kAreaUnitsByPropertyType['land']!.first, 'acres');
      expect(kAreaUnitsByPropertyType['land']!.length, 15);
    });

    test('defaults match React', () {
      expect(kDefaultAreaUnitByPropertyType, {
        'land': 'acres',
        'residential': 'sq_ft',
        'commercial': 'sq_ft',
        'pg/Co-living': 'sq_ft',
        'others': 'sq_ft',
      });
    });

    test('every per-category unit is a known unit', () {
      for (final entry in kAreaUnitsByPropertyType.entries) {
        for (final u in entry.value) {
          expect(kAreaUnitLabels.containsKey(u), isTrue,
              reason: '${entry.key} offers unknown unit "$u"');
        }
      }
    });
  });

  group('Select enums that reach Postgres', () {
    test('BHK types', () {
      expect(kBhkTypes, ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4+ BHK']);
    });

    test('land subtypes', () {
      expect(kLandSubtypes, ['land', 'plot']);
    });

    test('land ownership types', () {
      expect(kLandOwnershipTypes,
          ['Freehold', 'Leasehold', 'Power of Attorney', 'Co-Operative Society']);
    });

    test('plot type options', () {
      expect(kPlotTypeOptions, ['Residential Plot', 'Commercial Plot']);
    });

    test('PG frequencies differ between linen and cleaning', () {
      // AmenitiesStep/ConditionStep: linen ends Fortnightly, cleaning ends
      // On Demand. Easy to conflate; they are separate option sets.
      expect(kLinenChangeFrequencies,
          ['Daily', 'Alternate Days', 'Weekly', 'Fortnightly']);
      expect(kRoomCleaningFrequencies,
          ['Daily', 'Alternate Days', 'Weekly', 'On Demand']);
    });

    test('media category ids match React verbatim and keep order', () {
      // Order matters: metadata.mediaCategories is index-aligned with media_urls.
      expect(kDefaultImageCategories.map((o) => o.id).toList(), [
        'interior', 'exterior', 'amenities', 'floor_plan', 'property_video',
        'other',
      ]);
      expect(kLandImageCategories.map((o) => o.id).toList(),
          ['sajra', 'land_video', 'land_images', 'other']);
    });
  });

  group('Amenity list sizes', () {
    // The migration specification's counts are wrong for three of these; React
    // is the source of truth per CLAUDE.md.
    test('sizes match React source', () {
      expect(kResidentialSocietyAmenities.length, 47); // spec claimed 44
      expect(kResidentialFlatAmenities.length, 23); // spec claimed 22
      expect(kLandSoilTypes.length, 18); // spec truncated at 8
      expect(kResidentialParkingAmenities.length, 4);
      expect(kCommercialSuitableFor.length, 12);
      expect(kCommercialOfficeBuildingAmenities.length, 19);
      expect(kCommercialRetailWarehouseAmenities.length, 9);
      expect(kOtherGeneralAmenities.length, 12);
      expect(kPgRoomAmenities.length, 13);
      expect(kPgCommonAreaAmenities.length, 14);
      expect(kPgSafetyAndSecurity.length, 4);
      expect(kPgTenantRules.length, 8);
      expect(kResidentialTenantPreferences.length, 6);
    });

    test('society list preserves React duplicate rather than silently deduping',
        () {
      // AmenitiesStep.tsx lists 'Visitor Parking' at both line 23 and line 31.
      // Keeping it verbatim means the Dart list still round-trips React values;
      // any dedupe belongs in the UI, not the constants.
      expect(
        kResidentialSocietyAmenities.where((a) => a == 'Visitor Parking').length,
        2,
      );
      expect(kResidentialSocietyAmenities.toSet().length, 46);
    });

    test('tenant preference ids are the boolean metadata keys', () {
      expect(kResidentialTenantPreferences.map((o) => o.id).toList(), [
        'familyAllowed', 'bachelorAllowed', 'companyLeaseAllowed',
        'petsAllowed', 'smokingAllowed', 'vegetariansOnly',
      ]);
    });
  });

  group('Metadata key allow-list', () {
    test('total distinct React metadata surface', () {
      // final-architecture-review NEW-2 estimated ~340; the exact parsed figure
      // is 339 (its count included metadata.isPgListing, which React only ever
      // reads in a comparison, never writes).
      expect(kAllReactMetadataKeys.length, 339);
    });

    test('missingMetadataFields is the bulk of the surface', () {
      expect(kMissingMetadataFields.length, 246);
      expect(kMissingMetadataFields.toSet().length, 246,
          reason: 'duplicates should already be removed');
    });

    test('the Phase 0 corrected keys are canonical here', () {
      expect(kAllReactMetadataKeys.contains('maintenanceCharges'), isTrue);
      expect(kAllReactMetadataKeys.contains('allInclusivePriceToggle'), isTrue);
      expect(kAllReactMetadataKeys.contains('tokenAmount'), isTrue);
      // The key Flutter used to write does not exist in React at all.
      expect(kAllReactMetadataKeys.contains('allInclusivePrice'), isFalse);
    });

    test('maintenanceAmount is a real React key, just not the live one', () {
      // It is written by the rent/lease fillMetadata block but has no UI input,
      // which is why Phase 0 moved Flutter off it rather than deleting it.
      expect(kAllReactMetadataKeys.contains('maintenanceAmount'), isTrue);
    });

    test('nested objects and project-tag keys are catalogued', () {
      expect(kNestedObjectMetadataKeys,
          containsAll(<String>['buildingInventory', 'pgHouseRules']));
      expect(kProjectTagMetadataKeys,
          containsAll(<String>['projectId', 'projectName', 'builderName',
            'projectLocation']));
    });

    test('pgHouseRules sub-keys match React verbatim', () {
      expect(kPgHouseRuleKeys, [
        'visitorEntry', 'nonVegFood', 'oppositeGender', 'smoking', 'drinking',
        'loudMusic', 'party',
      ]);
    });
  });

  group('Value aliases (Q13)', () {
    test('every alias TARGET is a canonical React value', () {
      for (final t in kAreaUnitAliases.values) {
        expect(kAreaUnitLabels.containsKey(t), isTrue,
            reason: 'area unit alias points at unknown unit "$t"');
      }
      final canonicalSubtypes = {...kApartmentSubtypes, ...kHouseSubtypes};
      for (final t in kResidentialSubtypeAliases.values) {
        expect(canonicalSubtypes.contains(t), isTrue,
            reason: 'subtype alias points at unknown subtype "$t"');
      }
    });

    test('no alias SOURCE is already canonical (would be a no-op or a bug)', () {
      for (final s in kAreaUnitAliases.keys) {
        expect(kAreaUnitLabels.containsKey(s), isFalse);
      }
      final canonicalSubtypes = {...kApartmentSubtypes, ...kHouseSubtypes};
      for (final s in kResidentialSubtypeAliases.keys) {
        expect(canonicalSubtypes.contains(s), isFalse);
      }
    });

    test('unresolved subtypes pass through untouched, never guessed', () {
      for (final s in kUnresolvedResidentialSubtypes) {
        expect(canonicalResidentialSubtype(s), s);
        expect(kResidentialSubtypeAliases.containsKey(s), isFalse);
      }
    });

    test('aliasing is idempotent', () {
      for (final s in kAreaUnitAliases.keys) {
        expect(canonicalAreaUnit(canonicalAreaUnit(s)), canonicalAreaUnit(s));
      }
      for (final s in kResidentialSubtypeAliases.keys) {
        expect(canonicalResidentialSubtype(canonicalResidentialSubtype(s)),
            canonicalResidentialSubtype(s));
      }
    });

    test('known legacy values map as expected', () {
      expect(canonicalAreaUnit('sq_m'), 'sq_mtr');
      expect(canonicalAreaUnit('sq_yd'), 'sq_yards');
      expect(canonicalAreaUnit('sq_ft'), 'sq_ft');
      expect(canonicalResidentialSubtype('Studio Apartment'),
          'Studio / Service Apartment');
      expect(canonicalResidentialSubtype('Penthouse'), 'Pent House');
      expect(canonicalResidentialSubtype('Flat'), 'Flat');
    });
  });
}
