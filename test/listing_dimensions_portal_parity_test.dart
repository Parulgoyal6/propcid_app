// Step 3 portal parity: the field order, labels and required markers Flutter
// renders must match `PropertyDimensionsStep.tsx` branch for branch.
//
// Labels are asserted in render order, so a reordered, renamed, dropped or
// invented field fails here rather than in review.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/portal_kit.dart';
import 'package:propcid_app/screens/post_property/steps/property_dimensions_step.dart';

import 'support/overflow_detector.dart';

void main() {
  /// Every field label on the step, in render order, with a trailing `*` on the
  /// ones the portal marks required.
  Future<List<String>> labelsOf(
    WidgetTester tester,
    PostPropertyProvider p,
  ) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: p,
          child: const Scaffold(
            body: SingleChildScrollView(child: PropertyDimensionsStep()),
          ),
        ),
      ),
    );
    await tester.pump();
    return [
      for (final e in find.byType(PortalLabelledField).evaluate())
        () {
          final w = e.widget as PortalLabelledField;
          return w.required ? '${w.label} *' : w.label;
        }(),
    ];
  }

  /// The bare `<h4>` block headings, in render order.
  List<String> headingsOf(WidgetTester tester) => [
    for (final e in find.byType(PortalBlockHeading).evaluate())
      (e.widget as PortalBlockHeading).title,
  ];

  testWidgets('land rent — LandArea, LandDimensions(isRent), AvailableFrom', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.land)
      ..setListingIntent(ListingIntent.rent);
    expect(await labelsOf(tester, p), [
      'Total Land Area *',
      'Land Use / Master Plan', // rent only
      'Front *', 'Back *', 'Right *', 'Left *',
      // No trailing '*': deliberately optional on this app only, per
      // explicit product direction — see listing_validation_rules.dart's
      // own comment on this field.
      'Khasra Number',
      'FSI/FAR Allowed',
      'Floor Allowed',
      'Height Restriction',
      'Soil Type *',
      'Available From *',
    ]);
    expect(headingsOf(tester), ['Land Specification']);
  });

  testWidgets('land sell — no Land Use / Master Plan', (tester) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.land)
      ..setListingIntent(ListingIntent.sell);
    expect(
      await labelsOf(tester, p),
      isNot(contains('Land Use / Master Plan')),
    );
    expect((await labelsOf(tester, p)).first, 'Total Land Area *');
  });

  testWidgets('residential apartment subtypes', (tester) async {
    for (final subtype in [
      'Flat',
      'Independent / Builder Floor',
      'Studio / Service Apartment',
    ]) {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.rent)
        ..setResidentialSubType(subtype);
      expect(await labelsOf(tester, p), [
        'Total Area *',
        'Carpet Area',
        'BHK Type *',
        'Bedrooms *',
        'Bathrooms *',
        'Balconies *',
        'Floor No *',
        'Total Floors *',
        'Property Condition *',
        'Available From *',
      ], reason: subtype);
    }
  });

  testWidgets('residential house subtypes — Plot + Build Up, no Floor No', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.residential)
      ..setListingIntent(ListingIntent.sell)
      ..setResidentialSubType('Villa / Kothi');
    expect(await labelsOf(tester, p), [
      'Plot Area *',
      'Build Up Area',
      'Carpet Area',
      'BHK Type *',
      'Bedrooms *',
      'Bathrooms *',
      'Balconies *',
      'Total Floors *',
      'Property Condition *',
      'Available From *',
    ]);
  });

  testWidgets('an unresolved residential subtype takes the house branch', (
    tester,
  ) async {
    // Apartment / Row House / Hostel Building / Residential Plot are preserved
    // unmapped by decision; the portal treats anything outside
    // `residentialappartment` as a house, and so must Flutter.
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.residential)
      ..setListingIntent(ListingIntent.sell)
      ..setResidentialSubType('Row House');
    expect((await labelsOf(tester, p)).first, 'Plot Area *');
  });

  testWidgets('commercial — building block then area block', (tester) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.commercial)
      ..setListingIntent(ListingIntent.rent);
    expect(await labelsOf(tester, p), [
      'Building Name *',
      'Building Number *',
      'Building Type *',
      'Total Floors *',
      'Plot Area *',
      'Super Built-up Area *',
    ]);
    expect(headingsOf(tester), [
      'Building Level Details',
      'Area Details',
      'Floor-wise Inventory Management',
    ]);
    // The portal renders no AvailableFrom for commercial.
    expect(await labelsOf(tester, p), isNot(contains('Available From *')));
  });

  testWidgets(
    'commercial — an extreme Total Floors builds lazily instead of all at once',
    (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.rent);
      await labelsOf(tester, p);

      p.setBuildingInventoryValue('totalFloorsBuilding', '1000');
      await tester.pump();

      // The first floor sits inside the fixed-height viewport and is always
      // built; a floor near the far end of 1000 must never have been built
      // at all — proof the list is genuinely virtualized (a
      // `ListView.builder` inside a bounded box), not a `Column` that builds
      // every floor regardless of what is actually on screen. Floor index 1
      // labels as "Ground Floor" (portal's `getFloorLabel`), so that's what
      // renders, not "Floor 1".
      expect(find.text('Ground Floor'), findsOneWidget);
      expect(find.text('Floor 998'), findsNothing);
    },
  );

  testWidgets('commercial — Total Floors cannot be typed past 3 digits', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.commercial)
      ..setListingIntent(ListingIntent.rent);
    await labelsOf(tester, p);

    final field = find.byType(PortalTextField).at(2); // Total Floors
    await tester.enterText(field, '1000');
    // LengthLimitingTextInputFormatter(3) truncates the keystroke itself —
    // "1000" can never reach the provider at all, not just get rejected
    // later at Continue.
    expect(p.buildingInventoryText('totalFloorsBuilding'), '100');
  });

  testWidgets('pg — Area then PG Structure & Capacity', (tester) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.pg)
      ..setListingIntent(ListingIntent.rent);
    expect(await labelsOf(tester, p), [
      'Total Area *',
      'Carpet Area',
      'Total Floors *',
      'Facing',
      'Total Rooms',
    ]);
    expect(headingsOf(tester), ['PG Structure & Capacity']);
  });

  testWidgets('pg — Floor-wise Room Details appears once floors are set', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.pg)
      ..setListingIntent(ListingIntent.rent);
    await labelsOf(tester, p);
    // `if (numFloors === 0) return null`
    expect(headingsOf(tester), isNot(contains('Floor-wise Room Details')));

    p.setTotalFloors('3');
    await tester.pump();
    expect(headingsOf(tester), contains('Floor-wise Room Details'));
  });

  testWidgets(
    'pg — an extreme Total Floors builds lazily instead of all at once',
    (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.pg)
        ..setListingIntent(ListingIntent.rent);
      await labelsOf(tester, p);

      p.setTotalFloors('1000');
      await tester.pump();

      // Same proof as the commercial case below: only what the fixed-height
      // viewport can actually show gets built, not all 1000 floors.
      expect(find.text('Floor 1'), findsOneWidget);
      expect(find.text('Floor 999'), findsNothing);
    },
  );

  testWidgets('pg — Total Floors cannot be typed past 3 digits', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.pg)
      ..setListingIntent(ListingIntent.rent);
    await labelsOf(tester, p);

    final field = find.byType(PortalTextField).at(2); // Total Floors
    await tester.enterText(field, '1000');
    expect(p.totalFloors, '100');
  });

  testWidgets('others — Area only', (tester) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.other)
      ..setListingIntent(ListingIntent.sell);
    expect(await labelsOf(tester, p), ['Total Area *', 'Carpet Area']);
    expect(headingsOf(tester), isEmpty);
  });

  group('availableFrom is one value, as React stores it', () {
    test('unanswered reads blank, so the listing rule still fires', () {
      final p = PostPropertyProvider();
      expect(p.availableFromValue, '');
    });

    test('Immediately reads as the literal React writes', () {
      final p = PostPropertyProvider()..setAvailableImmediately(true);
      expect(p.availableFromValue, 'Immediately');
      expect(p.availableFrom, isNull);
    });

    test('a date clears Immediately and formats as yyyy-MM-dd', () {
      final p = PostPropertyProvider()
        ..setAvailableImmediately(true)
        ..setAvailableFrom(DateTime(2026, 3, 9));
      expect(p.availableImmediately, isFalse);
      expect(p.availableFromValue, '2026-03-09');
    });

    test('choosing Immediately after a date drops the date', () {
      final p = PostPropertyProvider()
        ..setAvailableFrom(DateTime(2026, 3, 9))
        ..setAvailableImmediately(true);
      expect(p.availableFrom, isNull);
      expect(p.availableFromValue, 'Immediately');
    });
  });

  // The value+unit rows are the only side-by-side layout left after the
  // portal's `md:grid-cols-N` collapse, so they are where a narrow phone would
  // overflow. 320 is the narrowest device this app targets.
  group('no overflow at 320px', () {
    final cases = <String, PostPropertyProvider Function()>{
      'land rent': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.rent),
      'residential apartment': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.rent)
        ..setResidentialSubType('Flat'),
      'residential house': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell)
        ..setResidentialSubType('Villa / Kothi'),
      'commercial': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.rent),
      'pg': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.pg)
        ..setListingIntent(ListingIntent.rent)
        ..setTotalFloors('3'),
      'others': () => PostPropertyProvider()
        ..setCategory(PropertyCategory.other)
        ..setListingIntent(ListingIntent.sell),
    };

    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        tester.view.physicalSize = const Size(320, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider.value(
              value: entry.value(),
              child: const Scaffold(
                body: SingleChildScrollView(child: PropertyDimensionsStep()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(overflowingBoxes(tester), isEmpty);
      });
    }
  });

  testWidgets('commercial Super Built-up Area keeps `area` in step', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.commercial)
      ..setListingIntent(ListingIntent.rent);
    await labelsOf(tester, p);

    final field = find.byType(PortalTextField).at(4); // Super Built-up Area
    await tester.enterText(field, '1800');
    expect(p.text('superBuiltUpArea'), '1800');
    expect(p.area, '1800');
  });
}
