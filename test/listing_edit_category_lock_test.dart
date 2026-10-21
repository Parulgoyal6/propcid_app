// Portal parity: TypeSelectionStep.tsx locks `propertyType`/`listingType`
// once a listing is being edited (`if (isEdit) return;` before either
// `updateFormData` call) — every later step's field set depends on both, so
// changing them mid-edit would silently orphan already-entered data. Flutter
// previously left `PostPropertyProvider.setCategory`/`setListingIntent`
// unguarded in edit mode; this is a regression guard for the fix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/steps/type_selection_step.dart';

void main() {
  group('category/listing-intent edit lock', () {
    test('a fresh (create-mode) provider still allows changes', () {
      final p = PostPropertyProvider();
      expect(p.isEditMode, isFalse);

      p.setCategory(PropertyCategory.commercial);
      expect(p.category, PropertyCategory.commercial);

      p.setListingIntent(ListingIntent.lease);
      expect(p.listingIntent, ListingIntent.lease);
    });

    test('an edit-mode provider ignores setCategory/setListingIntent', () {
      final p = PostPropertyProvider()
        ..initFromRawData(
          editingPropertyId: 'prop-1',
          propertyRow: const {
            'category': 'residential',
            'property_type': 'rent',
          },
        );
      expect(p.isEditMode, isTrue);
      expect(p.category, PropertyCategory.residential);
      expect(p.listingIntent, ListingIntent.rent);

      p.setCategory(PropertyCategory.commercial);
      expect(
        p.category,
        PropertyCategory.residential,
        reason: 'category must stay locked once a listing is being edited',
      );

      p.setListingIntent(ListingIntent.sell);
      expect(
        p.listingIntent,
        ListingIntent.rent,
        reason: 'listing intent must stay locked once editing',
      );
    });

    Future<PostPropertyProvider> pumpEditModeStep(WidgetTester tester) async {
      final p = PostPropertyProvider()
        ..initFromRawData(
          editingPropertyId: 'prop-1',
          propertyRow: const {
            'category': 'residential',
            'property_type': 'rent',
          },
        );
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: p,
            child: const Scaffold(
              body: SingleChildScrollView(child: TypeSelectionStep()),
            ),
          ),
        ),
      );
      return p;
    }

    testWidgets(
      'tapping a different property-type card in edit mode shows the '
      'locked message and does not change the category',
      (tester) async {
        final p = await pumpEditModeStep(tester);

        await tester.tap(find.text('Commercial'));
        await tester.pump();
        expect(
          find.text('Property type cannot be changed while editing.'),
          findsOneWidget,
        );
        expect(p.category, PropertyCategory.residential);
      },
    );

    testWidgets(
      'tapping a different listing-type card in edit mode shows the '
      'locked message and does not change the listing intent',
      (tester) async {
        final p = await pumpEditModeStep(tester);

        await tester.ensureVisible(find.text('For Sale'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('For Sale'));
        await tester.pump();
        expect(
          find.text('Listing type cannot be changed while editing.'),
          findsOneWidget,
        );
        expect(p.listingIntent, ListingIntent.rent);
      },
    );
  });
}
