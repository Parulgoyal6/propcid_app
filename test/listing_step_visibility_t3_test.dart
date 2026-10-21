// T3 step-visibility parity guard.
//
// Ports PropertyWizard.tsx:1350:
//
//   const stepsRaw = [
//     Category, Basic Info, Dimensions,
//     ...(!isLand && !isResidential ? [Condition] : []),
//     ...(!isLand ? [Amenities] : []),
//     Legal, Pricing, Media
//   ];
//
// Flutter appends its own Review step, which React has no equivalent for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('Visible steps per category', () {
    test('land hides BOTH Condition and Amenities', () {
      expect(visibleStepsFor(PropertyCategory.land), [
        WizardStep.category,
        WizardStep.basicInfo,
        WizardStep.dimensions,
        WizardStep.legal,
        WizardStep.pricing,
        WizardStep.media,
        WizardStep.review,
      ]);
    });

    test('residential hides Condition but keeps Amenities', () {
      expect(visibleStepsFor(PropertyCategory.residential), [
        WizardStep.category,
        WizardStep.basicInfo,
        WizardStep.dimensions,
        WizardStep.amenities,
        WizardStep.legal,
        WizardStep.pricing,
        WizardStep.media,
        WizardStep.review,
      ]);
    });

    test('commercial, PG and others show every step', () {
      for (final c in [
        PropertyCategory.commercial,
        PropertyCategory.pg,
        PropertyCategory.other,
      ]) {
        expect(visibleStepsFor(c), [
          WizardStep.category,
          WizardStep.basicInfo,
          WizardStep.dimensions,
          WizardStep.condition,
          WizardStep.amenities,
          WizardStep.legal,
          WizardStep.pricing,
          WizardStep.media,
          WizardStep.review,
        ], reason: c.name);
      }
    });

    test('step counts match React (excluding Flutter-only Review)', () {
      int reactSteps(PropertyCategory? c) =>
          visibleStepsFor(c).where((s) => s != WizardStep.review).length;

      expect(reactSteps(PropertyCategory.land), 6);
      expect(reactSteps(PropertyCategory.residential), 7);
      expect(reactSteps(PropertyCategory.commercial), 8);
      expect(reactSteps(PropertyCategory.pg), 8);
      expect(reactSteps(PropertyCategory.other), 8);
    });

    test('no category yet offers every step', () {
      // React never hits this state (its form data defaults to residential),
      // so there is nothing to mirror; the guards simply evaluate with neither
      // predicate true.
      expect(visibleStepsFor(null).length, 9);
    });
  });

  group('Provider integration', () {
    test('totalSteps tracks the category', () {
      final p = PostPropertyProvider();
      expect(p.totalSteps, 9);

      p.setCategory(PropertyCategory.land);
      expect(p.totalSteps, 7); // 6 React steps + Review

      p.setCategory(PropertyCategory.residential);
      expect(p.totalSteps, 8);

      p.setCategory(PropertyCategory.commercial);
      expect(p.totalSteps, 9);
    });

    test('currentWizardStep resolves through the visible list', () {
      final p = PostPropertyProvider()..setCategory(PropertyCategory.land);

      // Index 3 is Condition for commercial but Legal for land.
      expect(p.visibleSteps[3], WizardStep.legal);
      expect(visibleStepsFor(PropertyCategory.commercial)[3],
          WizardStep.condition);
    });

    test('currentStep is clamped when the step list shrinks', () {
      // Mirrors React's clamp at PropertyWizard.tsx:1364.
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.sell);

      p.debugSetCurrentStep(8); // Review, the last step of the long flow
      expect(p.currentStep, 8);

      // Switching to land drops two steps; the index must follow.
      p.setCategory(PropertyCategory.land);
      expect(p.totalSteps, 7);
      expect(p.currentStep, lessThanOrEqualTo(6));
      expect(() => p.currentWizardStep, returnsNormally);
    });

    test('goToWizardStep targets identity, not position', () {
      final p = PostPropertyProvider()..setCategory(PropertyCategory.land);
      p.debugSetCurrentStep(5); // Media for land

      p.goToWizardStep(WizardStep.legal);
      expect(p.currentWizardStep, WizardStep.legal);

      // A step hidden for this category is a no-op rather than a wrong jump.
      final before = p.currentStep;
      p.goToWizardStep(WizardStep.condition);
      expect(p.currentStep, before);
    });
  });

  group('Hidden steps cannot block progress', () {
    test('land is never asked for Condition or Amenities rules', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.sell);

      // Neither step is in the flow, so no index maps to their rule sets.
      final keys = p.visibleSteps.map(ruleKeyForStep).toSet();
      expect(keys, isNot(contains('Condition')));
      expect(keys, isNot(contains('Amenities')));

      // And the identity-based getters report them valid by vacuity.
      expect(p.isStep4Valid, isTrue); // condition
      expect(p.isStep5Valid, isTrue); // amenities
    });

    test('residential still enforces Amenities but not Condition', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell);

      final keys = p.visibleSteps.map(ruleKeyForStep).toSet();
      expect(keys, isNot(contains('Condition')));
      expect(keys, contains('Amenities'));

      expect(p.isStep4Valid, isTrue); // condition hidden -> vacuous
      expect(p.isStep5Valid, isFalse); // amenities required
    });

    test('commercial enforces both', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.sell);

      final keys = p.visibleSteps.map(ruleKeyForStep).toSet();
      expect(keys, containsAll(<String>['Condition', 'Amenities']));
    });

    test('firstInvalidStep indexes the visible list', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.sell);

      final int? first = p.firstInvalidStep;
      expect(first, isNotNull);
      // Whatever it points at must be a step that actually exists in the flow.
      expect(first, lessThan(p.totalSteps));
      expect(p.visibleSteps[first!], WizardStep.basicInfo);
    });
  });

  group('Review step summary', () {
    test('rule keys cover every visible step except Review', () {
      for (final c in PropertyCategory.values) {
        for (final s in visibleStepsFor(c)) {
          final key = ruleKeyForStep(s);
          if (s == WizardStep.review) {
            expect(key, isNull);
          } else {
            expect(key, isNotNull, reason: '${c.name}/${s.name}');
            expect(kPropertyStepRules.containsKey(key), isTrue);
          }
        }
      }
    });
  });
}
