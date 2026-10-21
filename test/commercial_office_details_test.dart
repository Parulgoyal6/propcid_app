// Commercial → Step 3 → Floor-wise Inventory → Office Details.
//
// `_officeCard`'s expanded section only ever covered the 5 base office
// fields (Office Name, Office Number, Contact Person, Phone Number, Monthly
// Rent) and explicitly did not collect the portal's 8 facility-inventory
// sub-sections (Space Inventory, Washroom Details, Pantry & Food
// Facilities, Power & Utilities, Security Inventory, IT Inventory,
// Furniture Inventory, Parking Allocation). This file verifies those 8
// sub-sections now render, write through `setBuildingOfficeField` with the
// exact field names the portal uses (PropertyDimensionsStep.tsx:1234-1553),
// and preserve values already present on an office created on the web.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/portal_kit.dart';
import 'package:propcid_app/screens/post_property/steps/property_dimensions_step.dart';

void main() {
  /// One floor, one office, expanded — the state every test in this file
  /// needs before any of the 8 sub-sections are reachable.
  Future<PostPropertyProvider> pumpExpandedOffice(
    WidgetTester tester, {
    Map<String, dynamic>? office,
  }) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.commercial)
      ..setListingIntent(ListingIntent.rent);
    p.setBuildingInventoryValue('totalFloorsBuilding', '1');
    p.setBuildingNumberOfCompanies(1, 1);
    if (office != null) {
      for (final entry in office.entries) {
        p.setBuildingOfficeField(1, 0, entry.key, entry.value);
      }
    }

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

    final officeHeader = find.text('Office 1');
    await tester.ensureVisible(officeHeader);
    // `ensureVisible` only starts an animated scroll — without settling it,
    // the tap below computes its hit-test offset from the pre-scroll
    // position, missing the (now-moved) target entirely.
    await tester.pumpAndSettle();
    await tester.tap(officeHeader);
    await tester.pump();

    return p;
  }

  /// Every field label under a sub-section heading, in render order —
  /// mirrors `listing_dimensions_portal_parity_test.dart`'s `labelsOf`.
  List<String> labelledFieldLabels(WidgetTester tester) => [
    for (final e in find.byType(PortalLabelledField).evaluate())
      (e.widget as PortalLabelledField).label,
  ];

  List<String> checkboxLabels(WidgetTester tester) => [
    for (final e in find.byType(PortalCheckbox).evaluate())
      (e.widget as PortalCheckbox).label,
  ];

  group('all 8 facility sub-sections render once an office is expanded', () {
    testWidgets('sub-section headings are all present', (tester) async {
      await pumpExpandedOffice(tester);

      for (final heading in const [
        'Space Inventory',
        'Washroom Details',
        'Pantry & Food Facilities',
        'Power & Utilities',
        'Security Inventory',
        'IT Inventory',
        'Furniture Inventory',
        'Parking Allocation',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
    });

    testWidgets(
      'every field label the portal renders for these sections is present',
      (tester) async {
        await pumpExpandedOffice(tester);

        final labels = labelledFieldLabels(tester);
        final checkboxes = checkboxLabels(tester);

        // Space Inventory
        expect(checkboxes, contains('Reception'));
        expect(
          labels,
          containsAll(['Total Workstations', 'Cabin Count', 'Conference Room']),
        );
        // Washroom Details
        expect(
          labels,
          containsAll([
            'Male Washroom Count',
            'Female Washroom Count',
            'Common Washroom Count',
          ]),
        );
        // Pantry & Food Facilities
        expect(checkboxes, containsAll(['Pantry Available', 'Cafeteria']));
        expect(
          labels,
          containsAll([
            'Coffee Machines',
            'Water Dispensers',
            'Dining Seating',
          ]),
        );
        // Power & Utilities
        expect(checkboxes, contains('Power Backup'));
        // Security Inventory
        expect(checkboxes, containsAll(['Biometric Access', 'RFID Access']));
        expect(labels, contains('CCTV Cameras'));
        // IT Inventory
        expect(checkboxes, contains('Video Conferencing'));
        expect(
          labels,
          containsAll([
            'Desktops',
            'Laptops',
            'Monitors',
            'Printers',
            'Servers',
          ]),
        );
        // Furniture Inventory
        expect(
          labels,
          containsAll([
            'Executive Chairs',
            'Staff Chairs',
            'Visitor Chairs',
            'Work Tables',
            'Conference Tables',
            'Storage Cabinets',
          ]),
        );
        // Parking Allocation
        expect(
          labels,
          containsAll([
            'Reserved Car Parking',
            'Reserved Bike Parking',
            'EV Parking Slots',
          ]),
        );
      },
    );

    testWidgets('the 5 pre-existing base fields are unaffected', (
      tester,
    ) async {
      await pumpExpandedOffice(tester);

      final labels = labelledFieldLabels(tester);
      expect(
        labels,
        containsAll([
          'Office Name',
          'Office Number',
          'Contact Person',
          'Phone Number',
          'Monthly Rent',
        ]),
      );
    });
  });

  group('Office Name and Office Number keep the portal\'s character rules', () {
    // `find.textContaining`, not `find.text`: "Office Name" renders with a
    // trailing " *" (it's `required: true`), which an exact match misses.
    Finder fieldFor(String label) => find.descendant(
      of: find.ancestor(
        of: find.textContaining(label),
        matching: find.byType(PortalLabelledField),
      ),
      matching: find.byType(TextField),
    );

    testWidgets('Office Name strips digits, keeping only letters/spaces', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final field = fieldFor('Office Name');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Acme 123 Corp');
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['companyName'], 'Acme  Corp');
    });

    testWidgets('Office Number strips letters, keeping only digits', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final field = fieldFor('Office Number');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'A10B1');
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['officeNumber'], '101');
    });
  });

  group('new fields write through setBuildingOfficeField correctly', () {
    testWidgets('typing a count field writes the exact portal field name', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final desktopsField = find.ancestor(
        of: find.text('Desktops'),
        matching: find.byType(PortalLabelledField),
      );
      await tester.ensureVisible(desktopsField);
      await tester.pumpAndSettle();
      final textField = find.descendant(
        of: desktopsField,
        matching: find.byType(TextField),
      );
      await tester.enterText(textField, '7');
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['desktopCount'], '7');
    });

    testWidgets('a count field strips non-digit input, matching /\\D/g', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final field = find.ancestor(
        of: find.text('CCTV Cameras'),
        matching: find.byType(PortalLabelledField),
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final textField = find.descendant(
        of: field,
        matching: find.byType(TextField),
      );
      await tester.enterText(textField, '4a5b');
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['cctvCameraCount'], '45');
    });

    testWidgets('toggling a checkbox writes a bool under its own field name', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final checkbox = find.ancestor(
        of: find.text('Biometric Access'),
        matching: find.byType(PortalCheckbox),
      );
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['biometricAccess'], true);
    });

    testWidgets('editing one new field leaves the base fields intact', (
      tester,
    ) async {
      final p = await pumpExpandedOffice(tester);

      final nameField = find.ancestor(
        // Rendered as "Office Name *" — `required: true` appends the
        // marker at render time, so an exact `find.text` match would find
        // nothing.
        of: find.textContaining('Office Name'),
        matching: find.byType(PortalLabelledField),
      );
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: nameField, matching: find.byType(TextField)),
        'Acme Corp',
      );
      await tester.pump();

      final laptopsField = find.ancestor(
        of: find.text('Laptops'),
        matching: find.byType(PortalLabelledField),
      );
      await tester.ensureVisible(laptopsField);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: laptopsField, matching: find.byType(TextField)),
        '12',
      );
      await tester.pump();

      final companies =
          (p.buildingInventory['floors'] as List).first['companies'] as List;
      expect(companies.first['companyName'], 'Acme Corp');
      expect(companies.first['laptopCount'], '12');
    });
  });

  group('edit-mode: pre-filled facility fields hydrate and are preserved', () {
    testWidgets(
      'an office created on the web with facility data shows it, not blank',
      (tester) async {
        await pumpExpandedOffice(
          tester,
          office: {
            'companyName': 'Web Created Co',
            'desktopCount': '9',
            'biometricAccess': true,
            'executiveChairs': '3',
          },
        );

        expect(find.text('9'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        final biometricCheckbox = tester.widget<PortalCheckbox>(
          find.ancestor(
            of: find.text('Biometric Access'),
            matching: find.byType(PortalCheckbox),
          ),
        );
        expect(biometricCheckbox.value, isTrue);
      },
    );

    testWidgets(
      'a facility field this form still does not expose survives an edit untouched',
      (tester) async {
        // e.g. Board Room / dedicated DG backup — dead in the portal's own
        // UI too (see property_dimensions_step.dart's class doc comment),
        // so `_officeCard` never renders them, but `setBuildingOfficeField`
        // must not drop them from the map when some *other* field is edited.
        final p = await pumpExpandedOffice(
          tester,
          office: {'boardRoomCount': '2', 'companyName': 'Old Name'},
        );

        final nameField = find.ancestor(
          // Rendered as "Office Name *" — `required: true` appends the
          // marker at render time, so an exact `find.text` match would find
          // nothing.
          of: find.textContaining('Office Name'),
          matching: find.byType(PortalLabelledField),
        );
        await tester.ensureVisible(nameField);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: nameField, matching: find.byType(TextField)),
          'New Name',
        );
        await tester.pump();

        final companies =
            (p.buildingInventory['floors'] as List).first['companies'] as List;
        expect(companies.first['companyName'], 'New Name');
        expect(companies.first['boardRoomCount'], '2');
      },
    );
  });
}
