// Location/map bug fix — the property wizard's Basic Info step must forget
// a previously-resolved map pin the moment the address text is hand-edited
// (requirement 3), matching the exact reasoning `ProjectBasicInfoStep`
// mirrors for the project wizard (see add_project_wizard_test.dart's own
// "map location" group for the validation-level half of this fix).
//
// `LocationPickerMap`/`AddressAutocompleteField` embed a real `GoogleMap`/
// hit Google's Places API respectively — neither is driven here. This test
// exercises the one thing that doesn't need either: typing into the
// Property Address `TextField` the same way a user would, after a
// coordinate pair was already set (simulating a prior successful pick),
// and confirming the provider's stored coordinates are cleared as a result.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

import 'support/wizard_driver.dart';

/// The Property Address field is the one `TextField` whose decoration hint
/// names it — `AddressAutocompleteField` has no other identifying type of
/// its own from outside its file.
const String _addressHint =
    'Type to search property address (Google Maps auto-complete)...';

Finder _addressField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == _addressHint,
);

void main() {
  setUpAll(initWizardTestEnv);

  testWidgets(
    'editing the address after a pin was dropped clears the stored coordinates',
    (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell);

      await pumpStep(tester, p, WizardStep.basicInfo);

      // Simulate a location already resolved (map tap or autocomplete, from
      // an earlier session or a restored draft).
      p
        ..setLatitude(28.7041)
        ..setLongitude(77.1025);
      await tester.pump();
      expect(p.latitude, isNotNull);
      expect(p.longitude, isNotNull);

      expect(_addressField(), findsOneWidget);
      await tester.enterText(_addressField(), 'A totally different address');
      await tester.pump();

      expect(
        p.latitude,
        isNull,
        reason: 'the old pin no longer describes the edited address',
      );
      expect(p.longitude, isNull);
    },
  );

  testWidgets('typing when no pin was ever set does not crash or set one', (
    tester,
  ) async {
    final p = PostPropertyProvider()
      ..setCategory(PropertyCategory.residential)
      ..setListingIntent(ListingIntent.sell);

    await pumpStep(tester, p, WizardStep.basicInfo);
    expect(p.latitude, isNull);

    await tester.enterText(_addressField(), 'MG Road');
    await tester.pump();

    expect(p.latitude, isNull);
    expect(p.longitude, isNull);
    expect(p.location, 'MG Road');
    expect(tester.takeException(), isNull);
  });
}
