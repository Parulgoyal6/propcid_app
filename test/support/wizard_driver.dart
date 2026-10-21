import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:propcid_app/core/widgets/wizard_kit.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';
import 'package:propcid_app/screens/post_property/portal_kit.dart';
import 'package:propcid_app/screens/post_property/steps/amenities_step.dart';
import 'package:propcid_app/screens/post_property/steps/basic_info_step.dart';
import 'package:propcid_app/screens/post_property/steps/condition_step.dart';
import 'package:propcid_app/screens/post_property/steps/legal_details_step.dart';
import 'package:propcid_app/screens/post_property/steps/media_contact_step.dart';
import 'package:propcid_app/screens/post_property/steps/pricing_step.dart';
import 'package:propcid_app/screens/post_property/steps/property_dimensions_step.dart';
import 'package:propcid_app/screens/post_property/steps/review_step.dart';
import 'package:propcid_app/screens/post_property/steps/type_selection_step.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// BasicInfoStep builds ProjectTagSelector, which constructs a PropertyService
/// and reads `Supabase.instance` eagerly — without this the whole subtree fails
/// to build and the step looks empty. Dummy credentials are enough; nothing in
/// these tests awaits a network round trip.
Future<void> initWizardTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=');

  await Supabase.initialize(
    url: 'http://localhost:54321',
    anonKey: 'test',
    debug: false,
  );
}

Widget stepWidget(WizardStep step) => switch (step) {
  WizardStep.category => const TypeSelectionStep(),
  WizardStep.basicInfo => const BasicInfoStep(),
  WizardStep.dimensions => const PropertyDimensionsStep(),
  WizardStep.condition => const ConditionStep(),
  WizardStep.amenities => const AmenitiesStep(),
  WizardStep.legal => const LegalDetailsStep(),
  WizardStep.pricing => const PricingStep(),
  WizardStep.media => const MediaContactStep(),
  WizardStep.review => const ReviewStep(),
};

/// Renders [step] against [p] in a tall viewport so nothing is off-screen.
Future<void> pumpStep(
  WidgetTester tester,
  PostPropertyProvider p,
  WizardStep step,
) async {
  tester.view.physicalSize = const Size(420, 9000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider.value(
        value: p,
        child: Scaffold(body: SingleChildScrollView(child: stepWidget(step))),
      ),
    ),
  );
  await tester.pump();
}

/// Fills every control the step renders, the way a user would: type into each
/// text box, pick the first option of each select, tick each checkbox, tap the
/// first chip of each chip group.
///
/// Re-pumps and repeats, because filling one control can reveal another
/// (choosing a furnishing type shows the items list, ticking Immediately hides
/// the date box).
/// Several rules validate format, not just presence — pincode must be 6
/// digits, phone numbers 10, email must parse. Typing a bare "5" everywhere
/// would fail those legitimately and look like an app bug, so pick a value
/// that satisfies the field the box is bound to.
String _valueFor(Element e, TextField w) {
  String label = '';
  e.visitAncestorElements((a) {
    final aw = a.widget;
    if (aw is WizardField) {
      label = aw.label;
      return false;
    }
    if (aw is PortalLabelledField) {
      label = aw.label;
      return false;
    }
    return true;
  });
  final l = label.toLowerCase();
  final hint = (w.decoration?.hintText ?? '').toLowerCase();
  if (l.contains('email') || hint.contains('@')) return 'a@b.com';
  if (l.contains('pincode')) return '560001';
  if (l.contains('phone') ||
      l.contains('whatsapp') ||
      l.contains('alternate') ||
      l.contains('contact number') ||
      w.keyboardType == TextInputType.phone) {
    return '9876543210';
  }
  if (l.contains('pg / property name') || hint.contains('zolo stays')) {
    return 'Test Property';
  }
  if (l.contains('floor no') || l.contains('floor number')) {
    return '1';
  }
  if (l.contains('total floors')) {
    return '2';
  }
  if (w.keyboardType == TextInputType.number) {
    return '1';
  }
  if (l.contains('building name') ||
      l.contains('contact name') ||
      l.contains('owner name') ||
      l.contains('owner / manager name') ||
      hint.contains('enter building name') ||
      hint.contains('your full name') ||
      hint.contains('rahul sharma') ||
      hint.contains('as recorded on the title')) {
    return 'Test User';
  }
  if (l.contains('best time to call') || hint.contains('10 am - 6 pm')) {
    return '10 AM - 6 PM';
  }
  if (l.contains('business type') || hint.contains('it services')) {
    return 'Test Business';
  }
  return '123456';
}

/// A picked photo. The image picker cannot be driven from a widget test, so
/// the media the user would choose is seeded directly.
void seedMedia(PostPropertyProvider p) {
  if (p.mediaItems.isEmpty) {
    p.addMediaItem(XFile('test/fixtures/photo.jpg'), 'interior');
  }
}

Future<void> fillVisibleControls(
  WidgetTester tester,
  PostPropertyProvider p,
  WizardStep step,
) async {
  if (step == WizardStep.media) seedMedia(p);
  for (var round = 0; round < 4; round++) {
    // Text inputs.
    for (final e in find.byType(TextField).evaluate().toList()) {
      try {
        if (!e.mounted) continue;

        final widget = e.widget;
        if (widget is! TextField) continue;
        if (widget.controller?.text.isNotEmpty ?? false) continue;

        final fieldFinder = find.byWidget(widget);
        if (fieldFinder.evaluate().isEmpty) continue;

        await tester.enterText(fieldFinder, _valueFor(e, widget));
        await tester.pump();
      } catch (_) {
        // Dynamic PG fields may be replaced after a provider rebuild.
        // A later round will discover and fill the mounted replacements.
      }
    }

    // Portal selects — tap the trigger, then the first option in the sheet.
    for (final e in find.byType(PortalSelect).evaluate().toList()) {
      final w = e.widget as PortalSelect;
      if ((w.value ?? '').isNotEmpty) continue;
      try {
        await tester.tap(find.byWidget(w), warnIfMissed: false);
        await tester.pumpAndSettle();
        final opt = find.byType(ListTile);
        if (opt.evaluate().isNotEmpty) {
          await tester.tap(opt.first, warnIfMissed: false);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(5, 5)); // dismiss
          await tester.pumpAndSettle();
        }
      } catch (_) {}
    }

    // Chip groups — tap the first chip of each.
    for (final e in find.byType(WizardChipGroup).evaluate().toList()) {
      final w = e.widget as WizardChipGroup;
      if ((w.selected ?? '').isNotEmpty) continue;
      final chips = find.descendant(
        of: find.byWidget(w),
        matching: find.byType(WizardChoiceChip),
      );
      if (chips.evaluate().isEmpty) continue;
      try {
        await tester.tap(chips.first, warnIfMissed: false);
        await tester.pump();
      } catch (_) {}
    }

    // Multi-select chip groups — tap the first chip.
    for (final e in find.byType(WizardMultiChipGroup).evaluate().toList()) {
      final w = e.widget as WizardMultiChipGroup;
      if (w.selected.isNotEmpty) continue;
      final chips = find.descendant(
        of: find.byWidget(w),
        matching: find.byType(WizardChoiceChip),
      );
      if (chips.evaluate().isEmpty) continue;
      try {
        await tester.tap(chips.first, warnIfMissed: false);
        await tester.pump();
      } catch (_) {}
    }

    // App checkbox tiles (e.g. Condition step's Available From -> Immediately).
    for (final e in find.byType(WizardCheckboxTile).evaluate().toList()) {
      final w = e.widget as WizardCheckboxTile;
      if (w.value) continue;
      try {
        await tester.tap(find.byWidget(w), warnIfMissed: false);
        await tester.pump();
      } catch (_) {}
    }

    // Portal checkboxes (e.g. Available From -> Immediately).
    for (final e in find.byType(PortalCheckbox).evaluate().toList()) {
      final w = e.widget as PortalCheckbox;
      if (w.value) continue;
      try {
        await tester.tap(find.byWidget(w), warnIfMissed: false);
        await tester.pump();
      } catch (_) {}
    }

    // The step watches the provider, so a plain pump surfaces any control the
    // previous round unlocked. Re-pumping the whole tree here would detach the
    // focus nodes of the fields just typed into.
    await tester.pump();
  }

  // Set last, like a real user resolving the map pin after (or instead of)
  // typing the address by hand: location/map bug fix, this step's address
  // field now clears any already-set coordinates on every edit (the old pin
  // no longer describes freshly-typed text) — setting these before the text
  // loop above typed into that same field used to leave them in place only
  // because nothing ever reacted to the edit.
  if (step == WizardStep.basicInfo) {
    if (p.latitude == null) {
      p.setLatitude(28.7041);
    }
    if (p.longitude == null) {
      p.setLongitude(77.1025);
    }
    await tester.pump();
  }
}
