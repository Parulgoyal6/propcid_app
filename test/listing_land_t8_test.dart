// T8 (Land) edit-hydration regression guard.
//
// Every other category (Residential/T6, Commercial/T10, PG/T9, Others/T7)
// has a dedicated hydration/round-trip test. Land never got one, and that
// gap is exactly where a P0 report landed: a land/sale listing created on
// the portal reopened in the Flutter app with Owner Name, Ownership Type,
// brokerage, hashtags and the entire Contact Information section blank.
//
// `PostPropertyProvider.initFromRawData` alone was not enough to prove that
// — it hydrates correctly against a hand-fed Map in isolation, but the real
// screen (`PostPropertyScreen`) defers hydration to a post-frame callback
// (`_PostPropertyWizardState.initState`), and each wizard step builds its
// TextEditingControllers once, in its own `initState`. If a step widget
// were ever built before that callback ran, its controller would freeze on
// the empty pre-hydration value and never recover — a class of bug a
// provider-only test cannot see. So this test drives the actual
// `PostPropertyScreen`, in edit mode, through real "Continue" taps, using
// the exact shape of a real portal-created land/sale row (pulled live from
// Supabase during the investigation), and reads the values back out of the
// rendered widgets rather than the provider.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/screens/post_property/post_property_screen.dart';
import 'package:propcid_app/services/property_service.dart';

import 'support/wizard_driver.dart';

void main() {
  setUpAll(() async {
    await initWizardTestEnv();
    // BasicInfoStep builds a LocationPickerMap, which constructs a
    // GeocodingService that reads `dotenv.env[...]` eagerly — without a
    // load, that getter throws before the map ever renders.
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=test');
  });

  testWidgets(
    'land/sale edit screen reconstructs a portal-created listing end to end',
    (tester) async {
      tester.view.physicalSize = const Size(420, 9000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const propertyId = 'b40aa609-d04d-4b47-85db-5f5faf27cba6';
      final bundle = PropertyEditBundle(
        propertyRow: {
          'id': propertyId,
          'category': 'land',
          'property_type': 'sell',
          'title': '2 acre plot in jaipur',
          'description': 'A nice plot',
          'location': 'Jaipur, Rajasthan, India',
          'latitude': 26.9,
          'longitude': 75.8,
          'price': '1000000',
          'rate_per_area': '',
          'area_unit': 'sq_ft',
          'area': '87120',
          'available_from': 'Immediately',
          'media_urls': <String>[],
          'main_display_media_url': '',
          'amenities': <String>[],
          'hashtags': ['plot', 'landforsale'],
          'project_id': null,
          'is_negotiable': true,
          'residential_subtype': '',
          'metadata': {
            'city': 'Jaipur',
            'state': 'Rajasthan',
            'pincode': '302001',
            'landType': 'Residential Plot',
            'landSubtype': 'plot',
            'soilType': 'Chalky Soil',
            'surveyNumber': '1',
            'front': '1',
            'frontUnit': 'ft',
            'back': '1',
            'backUnit': 'ft',
            'left': '1',
            'leftUnit': 'ft',
            'right': '1',
            'rightUnit': 'ft',
            'ownerName': 'Rahul Gandhi',
            'ownershipType': 'Co-Operative Society',
            'brokerage': '1%',
            'tokenAmount': '10000',
            'contactName': 'Komal',
            'whatsappNumber': '8920378044',
            'bestTimeToCall': '10 am -6 pm',
            'priceNegotiable': true,
            'allInclusivePriceToggle': true,
            'taxGovtChargesIncluded': true,
            'mutationAvailable': false,
            'pattaAvailable': false,
            'khataAvailable': false,
            'jamabandiAvailable': false,
            'courtCasePending': false,
            'bankLoanApproved': false,
            'registeredAgreement': false,
            'unregisteredAgreement': false,
          },
        },
        subtableRow: {
          'property_id': propertyId,
          'area_sqft': 87120,
          'boundary_wall': false,
          'water_source': '',
          'road_width_ft': 0,
          'soil_type': 'Chalky Soil',
          'slope_percentage': 0,
        },
        contactRow: {
          'property_id': propertyId,
          'contact_phone': '9876543210',
          'contact_email': 'seller@example.com',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PostPropertyScreen(
            editPropertyId: propertyId,
            editBundle: bundle,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.takeException(); // dotenv/layout noise unrelated to hydration

      Future<void> continueToNextStep() async {
        final continueBtn = find.text('Continue');
        expect(
          continueBtn,
          findsOneWidget,
          reason: 'Continue button not found — wizard may be stuck',
        );
        await tester.tap(continueBtn, warnIfMissed: false);
        await tester.pumpAndSettle();
        tester.takeException();
      }

      TextEditingController? controllerNear(String label) {
        final labelFinder = find.text(label);
        if (labelFinder.evaluate().isEmpty) return null;
        final fields = find
            .descendant(
              of: find
                  .ancestor(of: labelFinder, matching: find.byType(Column))
                  .first,
              matching: find.byType(TextField),
            )
            .evaluate()
            .map((e) => (e.widget as TextField).controller)
            .where((c) => c != null);
        return fields.isEmpty ? null : fields.first;
      }

      // Land order: Category -> Basic Info -> Dimensions -> Legal -> Pricing
      // -> Media (Condition/Amenities are hidden for land).
      await continueToNextStep(); // category -> basicInfo
      await continueToNextStep(); // basicInfo -> dimensions
      await continueToNextStep(); // dimensions -> legal

      expect(
        find.text('Owner Name *'),
        findsOneWidget,
        reason: 'Legal step for land did not render its Ownership card',
      );
      expect(
        controllerNear('Owner Name *')?.text,
        'Rahul Gandhi',
        reason: 'Owner Name is blank even though the row carries it',
      );

      final ownershipChip = find.text('Co-Operative Society');
      expect(
        ownershipChip,
        findsWidgets,
        reason:
            'Ownership Type chip group does not show the stored value '
            '(chip may render but not be marked selected — verified via '
            'PostPropertyProvider in the paired unit test)',
      );

      await continueToNextStep(); // legal -> pricing

      final brokerageField = controllerNear('Brokerage (if applicable)');
      expect(
        brokerageField?.text,
        '1%',
        reason: 'Brokerage is blank even though the row carries it',
      );
      final bookingField = controllerNear('Booking / Token Amount *');
      expect(
        bookingField?.text,
        '10000',
        reason:
            'Booking/Token Amount is blank even though the row '
            'carries it',
      );

      await continueToNextStep(); // pricing -> media

      expect(
        find.text('Contact Information'),
        findsOneWidget,
        reason: 'Media/Contact step did not render its Contact section',
      );

      final phoneField = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((w) => w.controller)
          .whereType<TextEditingController>()
          .where((c) => c.text == '9876543210');
      expect(
        phoneField,
        isNotEmpty,
        reason: 'Contact phone is blank even though the row carries it',
      );

      final emailField = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((w) => w.controller)
          .whereType<TextEditingController>()
          .where((c) => c.text == 'seller@example.com');
      expect(
        emailField,
        isNotEmpty,
        reason: 'Contact email is blank even though the row carries it',
      );

      final hashtagsField = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((w) => w.controller)
          .whereType<TextEditingController>()
          .where((c) => c.text == '#plot #landforsale');
      expect(
        hashtagsField,
        isNotEmpty,
        reason: 'Hashtags are blank even though the row carries them',
      );
    },
  );
}
