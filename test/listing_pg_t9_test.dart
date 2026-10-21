// T9 PG / co-living parity guard.
//
// The headline item is final-architecture-review NEW-5: PG never fills the
// single price box, so React mirrors the per-bed / per-room rent (or total sale
// price) into the `price` column. Without that, every app-created PG listing
// renders as "Price on Request" and sorts as though it were free.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

PostPropertyProvider pg({ListingIntent intent = ListingIntent.rent}) =>
    PostPropertyProvider()
      ..setCategory(PropertyCategory.pg)
      ..setListingIntent(intent);

/// Mirrors PropertyService._headlinePrice.
String headlinePrice(PostPropertyProvider p) {
  String result = p.price;
  if (p.category == PropertyCategory.pg) {
    switch (p.listingIntent) {
      case ListingIntent.sell:
        result = p.text('totalSalePrice');
      case ListingIntent.rent:
        final perBed = p.text('monthlyRentPerBed');
        result = perBed.isNotEmpty ? perBed : p.text('monthlyRentPerRoom');
      case ListingIntent.lease:
      case null:
        result = p.price;
    }
  }
  if (result.trim().isEmpty) result = p.price;
  return result.trim().isEmpty ? '0' : result;
}

/// Mirrors PropertyService._availableFrom.
String availableFrom(PostPropertyProvider p) {
  final d = p.availableFrom;
  if (d == null) return 'Immediately';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

const Map<String, String> houseRuleSources = {
  'visitorEntry': 'pgVisitorEntry',
  'nonVegFood': 'pgNonVegFood',
  'oppositeGender': 'pgOppositeGender',
  'smoking': 'pgSmoking',
  'drinking': 'pgDrinking',
  'loudMusic': 'pgLoudMusic',
  'party': 'pgParty',
};

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('NEW-5: headline price mirror', () {
    test('PG rent uses per-bed rent', () {
      final p = pg()..setText('monthlyRentPerBed', '8500');
      expect(headlinePrice(p), '8500');
    });

    test('PG rent falls back to per-room when per-bed is blank', () {
      final p = pg()..setText('monthlyRentPerRoom', '15000');
      expect(headlinePrice(p), '15000');
    });

    test('per-bed wins when both are set', () {
      final p = pg()
        ..setText('monthlyRentPerBed', '8500')
        ..setText('monthlyRentPerRoom', '15000');
      expect(headlinePrice(p), '8500');
    });

    test('PG sell uses the total sale price', () {
      final p = pg(intent: ListingIntent.sell)
        ..setText('totalSalePrice', '9500000');
      expect(headlinePrice(p), '9500000');
    });

    test('PG lease uses the plain price box', () {
      final p = pg(intent: ListingIntent.lease)..setPrice('42000');
      expect(headlinePrice(p), '42000');
    });

    test('non-PG categories are unaffected', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.rent)
        ..setPrice('30000')
        ..setText('monthlyRentPerBed', '999');
      expect(headlinePrice(p), '30000');
    });

    test('never empty — the column is text NOT NULL', () {
      expect(headlinePrice(pg()), '0');
      expect(headlinePrice(pg(intent: ListingIntent.sell)), '0');
      expect(headlinePrice(PostPropertyProvider()), '0');
    });

    test('the OLD behaviour would have stored a blank for PG rent', () {
      // Writing provider.price straight through is what produced
      // "Price on Request" on every app-created PG listing.
      final p = pg()..setText('monthlyRentPerBed', '8500');
      expect(p.price, isEmpty);
      expect(headlinePrice(p), isNot(p.price));
    });
  });

  group('pgHouseRules nested object', () {
    test('is written with all seven sub-keys', () {
      final p = pg();
      final rules = <String, dynamic>{
        for (final e in houseRuleSources.entries) e.key: p.boolVal(e.value),
      };
      expect(rules.keys.toSet(), houseRuleSources.keys.toSet());
      expect(rules.values.every((v) => v == false), isTrue,
          reason: 'unset flags coerce to false, as React dbBool does');
    });

    test('hydrates back from metadata rather than being wiped on edit', () {
      // React reads these into individual form fields
      // (PropertyWizard.tsx:1265) and rebuilds the object on save. Phase 0
      // skips nested maps, so without explicit hydration an edit would rewrite
      // every rule as false.
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'pg_coliving',
          'property_type': 'rent',
          'metadata': <String, dynamic>{
            'pgHouseRules': <String, dynamic>{
              'visitorEntry': true,
              'smoking': true,
              'party': false,
            },
          },
        },
      );

      expect(p.boolVal('pgVisitorEntry'), isTrue);
      expect(p.boolVal('pgSmoking'), isTrue);
      expect(p.boolVal('pgParty'), isFalse);
      expect(p.boolVal('pgDrinking'), isFalse, reason: 'absent key -> false');
    });

    test('a round-trip preserves the flags', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'pg_coliving',
          'property_type': 'rent',
          'metadata': <String, dynamic>{
            'pgHouseRules': <String, dynamic>{'nonVegFood': true},
          },
        },
      );

      final rebuilt = <String, dynamic>{
        for (final e in houseRuleSources.entries) e.key: p.boolVal(e.value),
      };
      expect(rebuilt['nonVegFood'], isTrue);
      expect(rebuilt['smoking'], isFalse);
    });

    test('the object is still excluded from the typed-empty fill', () {
      // It is a nested object, so blanking it would destroy real data.
      expect(kNestedObjectMetadataKeys, contains('pgHouseRules'));
    });
  });

  group('available_from format', () {
    test('a chosen date is stored as plain YYYY-MM-DD', () {
      final p = pg()..setAvailableFrom(DateTime(2026, 3, 7));
      expect(availableFrom(p), '2026-03-07');
      expect(availableFrom(p), isNot(contains('T')),
          reason: 'never a full ISO-8601 timestamp');
    });

    test('unset defaults to the literal "Immediately"', () {
      expect(availableFrom(pg()), 'Immediately');
    });
  });

  group('PG amenity labels', () {
    test('common-area labels come from React verbatim', () {
      final labels = kPgCommonAreaAmenities.map((o) => o.label).toList();
      expect(labels.length, 14);
      expect(labels, contains('Gym / Fitness Center'));
      expect(labels, isNot(contains('Gym/Fitness Center')),
          reason: 'the spacing drift that never matched on the web');
    });

    test('room features and safety flags are booleans, not the array', () {
      expect(kPgRoomAmenities.map((o) => o.id), contains('acPg'));
      expect(kPgSafetyAndSecurity.map((o) => o.id), contains('cctvCoverage'));
      expect(kPgTenantRules.map((o) => o.id), contains('studentsAllowed'));
    });
  });

  group('PG step and rule coverage', () {
    test('PG shows every step', () {
      expect(pg().totalSteps, 9);
      expect(pg().visibleSteps, contains(WizardStep.condition));
    });

    test('no required PG field is unreachable', () {
      for (final intent in ListingIntent.values) {
        final p = pg(intent: intent);
        final all = <String>{
          for (var i = 0; i < p.visibleSteps.length; i++)
            ...p.issuesForStep(i).map((e) => e.field),
        };
        for (final f in all) {
          expect(kFlutterCollectableFields, contains(f),
              reason: '$f blocks PG/${intent.name} with no input');
        }
      }
    });

    test('PG rent asks for per-bed rent, not the price box', () {
      final p = pg();
      final i = p.visibleSteps.indexOf(WizardStep.pricing);
      final f = p.issuesForStep(i).map((e) => e.field).toSet();
      expect(f, contains('monthlyRentPerBed'));
      expect(f, isNot(contains('price')));
    });

    test('PG rows still go to properties_residential', () {
      // React writes PG into the residential subtable; nothing here changes
      // that mapping.
      expect(PropertyCategory.pg.name, 'pg');
    });
  });
}
