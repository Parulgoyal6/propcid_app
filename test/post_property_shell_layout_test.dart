// The wizard shell must lay out without overflow on every viewport the app
// targets — phone through desktop web — on every step and category.
//
// The shell previously stacked the full 9-row vertical stepper above the form
// with `mainAxisSize.max`, which let the Progress card consume the whole
// viewport and overflowed by 41px at 320x568.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';
import 'package:propcid_app/screens/post_property/portal_shell.dart';
import 'package:propcid_app/screens/post_property/post_property_screen.dart';
import 'package:propcid_app/screens/post_property/steps/type_selection_step.dart';

import 'support/overflow_detector.dart';

void main() {
  const viewports = <String, Size>{
    'iPhone SE': Size(320, 568),
    'small Android': Size(360, 640),
    'iPhone 14': Size(390, 844),
    'tablet portrait': Size(768, 1024),
    'tablet landscape': Size(1024, 768),
    'desktop web': Size(1280, 800),
    'wide web': Size(1920, 1080),
  };

  Future<void> pumpShell(WidgetTester tester, Size size,
      {PropertyCategory category = PropertyCategory.commercial,
      int step = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = PostPropertyProvider()
      ..setCategory(category)
      ..setListingIntent(ListingIntent.rent);
    for (var i = 0; i < step; i++) {
      p.goToStep(i + 1);
    }

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: p,
        child: const PostPropertyWizardView(
          stepLabels: PostPropertyScreen.stepLabels,
          stepHeadings: PostPropertyScreen.stepHeadings,
        ),
      ),
    ));
    await tester.pump();
    // The screen ends with `.animate().fadeIn(300ms)`; let it finish so the
    // test does not tear down with a pending timer.
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('no overflow', () {
    for (final entry in viewports.entries) {
      testWidgets('${entry.key} ${entry.value.width.toInt()}x'
          '${entry.value.height.toInt()}', (tester) async {
        await pumpShell(tester, entry.value);
        expect(tester.takeException(), isNull);
        expect(overflowingBoxes(tester), isEmpty);
      });
    }

    // Commercial is the longest wizard (8 steps + review); land the shortest.
    for (final category in [
      PropertyCategory.commercial,
      PropertyCategory.residential,
      PropertyCategory.land,
      PropertyCategory.pg,
      PropertyCategory.other,
    ]) {
      testWidgets('${category.name} on the smallest phone', (tester) async {
        await pumpShell(tester, const Size(320, 568), category: category);
        expect(tester.takeException(), isNull);
        expect(overflowingBoxes(tester), isEmpty);
      });
    }
  });

  // The footer swaps Continue for Publish on the last step, and each step
  // renders a different form, so every step is checked on the tightest screen.
  group('every step is clean on the smallest phone', () {
    for (var step = 0;
        step < visibleStepsFor(PropertyCategory.commercial).length;
        step++) {
      testWidgets('step ${step + 1}', (tester) async {
        await pumpShell(tester, const Size(320, 568), step: step);
        expect(tester.takeException(), isNull);
        expect(overflowingBoxes(tester), isEmpty);
      });
    }
  });

  testWidgets('mobile shows the compact progress card, not the full stepper',
      (tester) async {
    await pumpShell(tester, const Size(390, 844));
    final card = tester.widget<PortalProgressCard>(
        find.byType(PortalProgressCard));
    expect(card.compact, isTrue);
    // The card must leave the form the majority of the screen.
    expect(tester.getSize(find.byType(PortalProgressCard)).height,
        lessThan(120));
  });

  testWidgets('web shows the full stepper beside the form', (tester) async {
    await pumpShell(tester, const Size(1280, 800));
    final card = tester.widget<PortalProgressCard>(
        find.byType(PortalProgressCard));
    expect(card.compact, isFalse);

    // Side by side, not stacked: the form starts to the right of the panel.
    final panel = tester.getRect(find.byType(PortalProgressCard));
    final form = tester.getRect(find.byType(TypeSelectionStep));
    expect(form.left, greaterThan(panel.right - 1),
        reason: 'form should render beside the progress panel');
  });

  testWidgets('the form area scrolls rather than overflowing', (tester) async {
    await pumpShell(tester, const Size(320, 568));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -200));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(overflowingBoxes(tester), isEmpty);
  });
}
