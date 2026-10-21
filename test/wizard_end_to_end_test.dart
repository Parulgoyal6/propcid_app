// End-to-end walkthrough of the Post Property wizard for every category x
// listing type: fill each step through its real controls, Continue, Back, reach
// Review, and confirm Publish is reachable.
//
// This is the regression guard for the two blocked flows found in manual
// testing — land/sell stuck on Pricing (no price input existed) and
// commercial/rent stuck on Condition (no Available From input existed) — plus
// the same class of defect on the eleven other combinations.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';
import 'package:propcid_app/screens/post_property/steps/review_step.dart';

import 'support/wizard_driver.dart';

void main() {
  setUpAll(initWizardTestEnv);

  for (final cat in PropertyCategory.values) {
    for (final intent in ListingIntent.values) {
      testWidgets('${cat.name} / ${intent.name} completes end to end',
          (tester) async {
        final p = PostPropertyProvider()
          ..setCategory(cat)
          ..setListingIntent(intent);

        final steps = p.visibleSteps;
        expect(p.currentStep, 0);

        for (var i = 0; i < steps.length; i++) {
          expect(p.currentStep, i,
              reason: 'should be on step ${i + 1} (${steps[i].name})');

          await pumpStep(tester, p, steps[i]);
          await fillVisibleControls(tester, p, steps[i]);

          // Every requirement on this step must be satisfiable from its own
          // controls — this is what "Continue does not advance" looked like.
          expect(p.issuesForStep(i), isEmpty,
              reason: 'step ${i + 1} (${steps[i].name}) of ${cat.name}/'
                  '${intent.name} still blocks on '
                  '${p.issuesForStep(i).map((e) => e.field).toList()}');

          if (i == steps.length - 1) break;

          // Continue.
          expect(p.canGoNext, isTrue,
              reason: 'Continue blocked on step ${i + 1}');
          p.nextStep();
          expect(p.currentStep, i + 1, reason: 'Continue did not advance');
        }

        // Last visible step is Review, and it renders.
        expect(steps.last, WizardStep.review);
        expect(p.isLastStep, isTrue);
        await pumpStep(tester, p, WizardStep.review);
        expect(find.byType(ReviewStep), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Publish is reachable: nothing anywhere in the wizard still blocks.
        expect(p.firstInvalidStep, isNull,
            reason: 'Publish blocked by step '
                '${p.firstInvalidStep} — ${p.allStepIssues}');

        // Back walks all the way to step 1.
        for (var i = steps.length - 1; i > 0; i--) {
          p.previousStep();
          expect(p.currentStep, i - 1, reason: 'Back did not move from $i');
        }
        expect(p.currentStep, 0);
      });
    }
  }

  group('validation is not weakened', () {
    testWidgets('an empty step still blocks Continue', (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.rent);

      // Step 1 is satisfied by the category and listing type alone, so it
      // advances; step 2 (Basic Info) is empty and must not.
      p.nextStep();
      expect(p.currentStep, 1);
      expect(p.canGoNext, isFalse);
      p.nextStep();
      expect(p.currentStep, 1,
          reason: 'Continue must not advance off an incomplete Basic Info');
    });

    testWidgets('Available From still required on the Condition step',
        (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.rent);
      final conditionIndex = p.visibleSteps.indexOf(WizardStep.condition);
      await pumpStep(tester, p, WizardStep.condition);
      await fillVisibleControls(tester, p, WizardStep.condition);
      expect(p.issuesForStep(conditionIndex), isEmpty);

      // Clearing it must block the step again.
      p.setAvailableImmediately(false);
      p.setAvailableFrom(null);
      expect(
        p.issuesForStep(conditionIndex).map((e) => e.field),
        contains('availableFrom'),
      );
    });

    testWidgets('the price field still required on Pricing', (tester) async {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.sell);
      final pricingIndex = p.visibleSteps.indexOf(WizardStep.pricing);
      await pumpStep(tester, p, WizardStep.pricing);
      await fillVisibleControls(tester, p, WizardStep.pricing);
      expect(p.issuesForStep(pricingIndex), isEmpty);

      p.setPrice('');
      expect(
        p.issuesForStep(pricingIndex).map((e) => e.field),
        contains('price'),
      );
    });

    test('the price box writes React\'s three mirrored fields', () {
      // PricingStep.tsx:44 writes price, expectedPrice and leaseAmount from
      // the one input.
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.sell)
        ..setPrice('2500000')
        ..setText('expectedPrice', '2500000')
        ..setText('leaseAmount', '2500000');
      expect(p.price, '2500000');
      expect(p.text('expectedPrice'), '2500000');
      expect(p.text('leaseAmount'), '2500000');
    });
  });
}
