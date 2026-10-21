// T7 "Others" category parity guard.
//
// The headline item is the category enum: the Postgres `property_category`
// enum accepts residential, commercial, land, pg_coliving, others — and
// Flutter was writing the enum NAME, 'other', which is not a member. Creating
// an Others listing failed at the database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';
import 'package:propcid_app/screens/post_property/steps/pricing_step.dart';

/// The exact members of the `property_category` Postgres enum, checked against
/// the live schema. Anything outside this set is rejected by the database.
const Set<String> kPropertyCategoryEnum = {
  'residential',
  'commercial',
  'land',
  'pg_coliving',
  'others',
};

/// Mirrors PropertyService._categoryToDb.
String categoryToDb(PropertyCategory c) => switch (c) {
      PropertyCategory.pg => 'pg_coliving',
      PropertyCategory.other => 'others',
      _ => c.name,
    };

PostPropertyProvider others({ListingIntent intent = ListingIntent.sell}) =>
    PostPropertyProvider()
      ..setCategory(PropertyCategory.other)
      ..setListingIntent(intent);

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('Category enum', () {
    test('Other maps to "others", not the enum name "other"', () {
      expect(categoryToDb(PropertyCategory.other), 'others');
      expect(PropertyCategory.other.name, 'other',
          reason: 'the enum name is the trap this guards against');
    });

    test('every category maps to a valid Postgres enum member', () {
      for (final c in PropertyCategory.values) {
        expect(kPropertyCategoryEnum, contains(categoryToDb(c)),
            reason: '${c.name} maps outside the property_category enum');
      }
    });

    test('the old value would have been rejected by the database', () {
      expect(kPropertyCategoryEnum, isNot(contains('other')));
    });

    test('"others" parses back to the Other category', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'others',
          'property_type': 'sell',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.category, PropertyCategory.other);
    });

    test('legacy "other" still parses rather than losing the category', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'other',
          'property_type': 'sell',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.category, PropertyCategory.other);
    });

    test('round-trips: write then read gives back Other', () {
      final written = categoryToDb(PropertyCategory.other);
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': written,
          'property_type': 'sell',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.category, PropertyCategory.other);
    });
  });

  group('originalCategory stamp', () {
    // React: if (propertyType === 'others') metadata.originalCategory = 'other'
    // Note the value is SINGULAR while the column enum member is plural.
    test('the stamped value is singular "other"', () {
      final p = others();
      String? stamp(PostPropertyProvider p) =>
          p.category == PropertyCategory.other ? 'other' : null;

      expect(stamp(p), 'other');
      expect(stamp(p), isNot(categoryToDb(PropertyCategory.other)),
          reason: 'stamp and column value deliberately differ');
    });

    test('is not stamped for any other category', () {
      for (final c in PropertyCategory.values) {
        if (c == PropertyCategory.other) continue;
        final p = PostPropertyProvider()..setCategory(c);
        expect(p.category == PropertyCategory.other, isFalse, reason: c.name);
      }
    });

    test('originalCategory is a real React metadata key', () {
      // Guards against inventing the key — CLAUDE.md forbids that.
      expect(kOtherGeneralAmenities, isNotEmpty);
    });
  });

  group('Others amenities', () {
    test('uses React\'s 12-item general list', () {
      expect(kOtherGeneralAmenities.length, 12);
      expect(kOtherGeneralAmenities, containsAll(<String>[
        'Power Backup', 'Security Guard', 'CCTV', 'Lift', 'Parking',
      ]));
    });

    test('the amenities rule applies to Others and is satisfiable', () {
      final p = others();
      final i = p.visibleSteps.indexOf(WizardStep.amenities);
      expect(p.issuesForStep(i).map((e) => e.field), contains('amenities'));

      p.setListVal('amenities', ['Power Backup']);
      expect(
          p.issuesForStep(i).map((e) => e.field), isNot(contains('amenities')));
    });

    test('selections outside the Others list are preserved', () {
      // Switching category must not silently drop a listing's amenities.
      final p = others();
      p.setListVal('amenities', ['Lift', 'Modular Kitchen']);

      final kept = p
          .listVal('amenities')
          .where((a) => !kOtherGeneralAmenities.contains(a))
          .toList();
      expect(kept, ['Modular Kitchen']);
    });
  });

  group('Step visibility and required fields', () {
    test('Others shows every step, including Condition', () {
      final p = others();
      expect(p.visibleSteps, contains(WizardStep.condition));
      expect(p.visibleSteps, contains(WizardStep.amenities));
      expect(p.totalSteps, 9);
    });

    test('requires carpetArea like residential, but no BHK block', () {
      final p = others();
      final i = p.visibleSteps.indexOf(WizardStep.dimensions);
      final f = p.issuesForStep(i).map((e) => e.field).toSet();

      expect(f, containsAll(<String>['area', 'carpetArea']));
      expect(f, isNot(contains('bhkType')));
      expect(f, isNot(contains('bedrooms')));
      expect(f, isNot(contains('soilType')));
    });

    test('no required field is unreachable', () {
      for (final intent in ListingIntent.values) {
        final p = others(intent: intent);
        final all = <String>{
          for (var i = 0; i < p.visibleSteps.length; i++)
            ...p.issuesForStep(i).map((e) => e.field),
        };
        for (final f in all) {
          expect(kFlutterCollectableFields, contains(f),
              reason: '$f blocks Others/${intent.name} with no input');
        }
      }
    });
  });

  group('residential_subtype column', () {
    // React writes this key for every category, using '' when not residential.
    String subtypeColumn(PostPropertyProvider p) =>
        p.category == PropertyCategory.residential
            ? (p.residentialSubType ?? '')
            : '';

    test('is an empty string for Others, never null', () {
      expect(subtypeColumn(others()), '');
    });

    test('still carries the value for residential', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setResidentialSubType('Flat');
      expect(subtypeColumn(p), 'Flat');
    });
  });

  group('Maintenance Charges on Sell — PricingStep.tsx branch by branch', () {
    // Every category/intent combination renders <Maintenance/> except Land
    // (all three intents) and Residential/Commercial's own Sell branch —
    // PG/Sell and Others/Sell both render it despite being "sell". The
    // required-ness rule (listing_validation_rules.dart, unaffected by this
    // group) is separately scoped to rent/lease only, so the field is
    // present-but-optional on these two Sell branches.
    Future<void> pump(WidgetTester tester, PostPropertyProvider p) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: p,
            child: const Scaffold(
              body: SingleChildScrollView(child: PricingStep()),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Others/Sell now shows it', (tester) async {
      await pump(tester, others(intent: ListingIntent.sell));
      expect(find.text('Maintenance Charges (Monthly) *'), findsOneWidget);
    });

    testWidgets('Residential/Sell still does not', (tester) async {
      await pump(
        tester,
        PostPropertyProvider()
          ..setCategory(PropertyCategory.residential)
          ..setListingIntent(ListingIntent.sell),
      );
      expect(find.text('Maintenance Charges (Monthly) *'), findsNothing);
    });

    testWidgets('Commercial/Sell still does not', (tester) async {
      await pump(
        tester,
        PostPropertyProvider()
          ..setCategory(PropertyCategory.commercial)
          ..setListingIntent(ListingIntent.sell),
      );
      expect(find.text('Maintenance Charges (Monthly) *'), findsNothing);
    });

    testWidgets('Land/Sell still does not (never has the field at all)',
        (tester) async {
      await pump(
        tester,
        PostPropertyProvider()
          ..setCategory(PropertyCategory.land)
          ..setListingIntent(ListingIntent.sell),
      );
      expect(find.text('Maintenance Charges (Monthly) *'), findsNothing);
    });

    testWidgets('Others/Rent and Others/Lease are unaffected (already shown)',
        (tester) async {
      await pump(tester, others(intent: ListingIntent.rent));
      expect(find.text('Maintenance Charges (Monthly) *'), findsOneWidget);

      await pump(tester, others(intent: ListingIntent.lease));
      expect(find.text('Maintenance Charges (Monthly) *'), findsOneWidget);
    });
  });
}
