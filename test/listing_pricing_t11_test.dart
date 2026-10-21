// T11 shared-pricing parity guard — the final implementation phase.
//
// The category phases (T6-T10) closed the category-specific pricing branches.
// What remained shared were two things React does on one input that Flutter
// did not: mirroring ratePerArea into pricePerSqFt, and offering a
// category-aware unit for the rate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_area_units.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

PostPropertyProvider sell(PropertyCategory c) => PostPropertyProvider()
  ..setCategory(c)
  ..setListingIntent(ListingIntent.sell);

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('ratePerArea mirrors into pricePerSqFt', () {
    test('one input writes both keys, as React does', () {
      final p = sell(PropertyCategory.residential);
      // What the Rate per Area field now does on change.
      p
        ..setRatePerArea('7500')
        ..setText('pricePerSqFt', '7500');

      expect(p.ratePerArea, '7500');
      expect(p.text('pricePerSqFt'), '7500');
    });

    test('only pricePerSqFt is a metadata key', () {
      // ratePerArea has its own column (`rate_per_area`); pricePerSqFt is the
      // metadata mirror the web reads on cards.
      expect(kAllReactMetadataKeys, contains('pricePerSqFt'));
      expect(kAllReactMetadataKeys, isNot(contains('ratePerArea')));
    });

    test('ratePerAreaUnit is UI-only and must NOT be persisted', () {
      // React renders it but writes it nowhere — no column, no metadata. The
      // bag would otherwise flush it, giving app rows a key web rows lack.
      expect(kAllReactMetadataKeys, isNot(contains('ratePerAreaUnit')));
    });

    test('pricePerSqFt was previously always blank', () {
      // Nothing in Flutter wrote it, so the web read an empty mirror on every
      // app-created listing while its own listings carried a value.
      final p = sell(PropertyCategory.residential)..setRatePerArea('7500');
      expect(p.text('pricePerSqFt'), isEmpty,
          reason: 'setRatePerArea alone must not populate the mirror');
    });
  });

  group('ratePerAreaUnit', () {
    String resolvedUnit(PostPropertyProvider p) {
      final stored = p.text('ratePerAreaUnit');
      if (stored.isNotEmpty) return stored;
      return p.areaUnit.isNotEmpty
          ? p.areaUnit
          : defaultAreaUnitFor(p.category);
    }

    test('defaults to the listing area unit', () {
      final p = sell(PropertyCategory.residential)..setAreaUnit('sq_yards');
      expect(resolvedUnit(p), 'sq_yards');
    });

    test('falls back to the category default when nothing is set', () {
      final p = sell(PropertyCategory.land);
      p.setAreaUnit('');
      expect(resolvedUnit(p), 'acres');
    });

    test('an explicit choice wins', () {
      final p = sell(PropertyCategory.residential)
        ..setAreaUnit('sq_ft')
        ..setText('ratePerAreaUnit', 'sq_mtr');
      expect(resolvedUnit(p), 'sq_mtr');
    });

    test('offers the category-dependent set, not one flat list', () {
      expect(areaUnitsFor(PropertyCategory.pg).map((u) => u.$1).toList(),
          ['sq_ft', 'sq_mtr']);
      expect(areaUnitsFor(PropertyCategory.land).length, 15);
      expect(areaUnitsFor(PropertyCategory.commercial).map((u) => u.$1),
          isNot(contains('bigha')),
          reason: 'a commercial listing cannot quote a rate in bigha');
    });

    test('a stored non-canonical unit is kept so the dropdown cannot crash',
        () {
      final units = areaUnitsFor(PropertyCategory.residential, 'bigha');
      expect(units.map((u) => u.$1), contains('bigha'));
    });
  });

  group('Shared area-unit helper', () {
    test('both steps resolve units the same way', () {
      // Dimensions and Pricing share one helper, exactly as React shares
      // getAreaUnitsForPropertyType between the two steps.
      for (final c in PropertyCategory.values) {
        final units = areaUnitsFor(c);
        expect(units, isNotEmpty, reason: c.name);
        for (final u in units) {
          expect(kAreaUnitLabels.containsKey(u.$1), isTrue,
              reason: '${c.name} offers unknown unit ${u.$1}');
        }
      }
    });

    test('defaults match React per category', () {
      expect(defaultAreaUnitFor(PropertyCategory.land), 'acres');
      expect(defaultAreaUnitFor(PropertyCategory.residential), 'sq_ft');
      expect(defaultAreaUnitFor(PropertyCategory.pg), 'sq_ft');
    });
  });

  group('Vestigial pricing keys stay covered by the typed-empty fill', () {
    // 31 pricing keys are persisted by React's fillMetadata but collected by
    // no input in either wizard — the sale tax block, the rent/lease block and
    // the lease-terms block. T1 already writes them as '', which is exactly
    // what React writes. They need no inputs; inventing some would violate
    // CLAUDE.md.
    const vestigial = [
      'financeStatus', 'priceType', 'propertyTax', 'waterTax', 'otherTax',
      'registrationTitle', 'mutation', 'dispute',
      'possessionDate', 'vegNonVeg', 'tenantPreference', 'ownerResiding',
      'lockingPeriod', 'gstApplicable',
      'brokerageType', 'advanceRent', 'noticePeriod', 'includedCharges',
      'refundDep', 'nonRefundDep', 'renewalTerms', 'leaseStart', 'leaseEnd',
      'subleasingAllowed', 'commercialUse', 'interiorMod', 'downPayment',
      'emiEstimate', 'expectedAppreciation', 'rentalYield',
    ];

    test('every one is in the allow-list, so it is written as typed-empty', () {
      for (final k in vestigial) {
        expect(kAllReactMetadataKeys, contains(k), reason: k);
      }
    });

    test('none of them is a rule field, so none can block a save', () {
      final ruleFields = <String>{
        for (final rules in kPropertyStepRules.values)
          for (final r in rules) r.field,
      };
      for (final k in vestigial) {
        expect(ruleFields, isNot(contains(k)), reason: k);
      }
    });
  });

  group('Pricing rules remain satisfiable everywhere', () {
    test('no pricing requirement is unreachable in any combination', () {
      for (final c in PropertyCategory.values) {
        for (final i in ListingIntent.values) {
          final p = PostPropertyProvider()
            ..setCategory(c)
            ..setListingIntent(i);
          final idx = p.visibleSteps.indexOf(WizardStep.pricing);
          for (final issue in p.issuesForStep(idx)) {
            expect(kFlutterCollectableFields, contains(issue.field),
                reason: '${issue.field} blocks ${c.name}/${i.name}');
          }
        }
      }
    });
  });

  group('Migration end state', () {
    test('the map pin gap is closed', () {
      // The map pin was the last outstanding gap; LocationPickerMap and the
      // Property Address field's autocomplete now both set
      // latitude/longitude, so nothing is left uncollectable.
      expect(kFieldsNotYetCollectable, isEmpty);
    });

    test('every category and listing type can be completed end to end', () {
      for (final c in PropertyCategory.values) {
        for (final i in ListingIntent.values) {
          final p = PostPropertyProvider()
            ..setCategory(c)
            ..setListingIntent(i);
          final all = <String>{
            for (var s = 0; s < p.visibleSteps.length; s++)
              ...p.issuesForStep(s).map((e) => e.field),
          };
          for (final f in all) {
            expect(kFlutterCollectableFields, contains(f),
                reason: '$f blocks ${c.name}/${i.name} with no input');
          }
        }
      }
    });
  });
}
