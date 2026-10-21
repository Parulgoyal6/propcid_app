// T2 validation-parity guard.
//
// migration-specification Task 2: "table-driven tests per category x listingType
// asserting the same steps pass/fail as React for identical input."
//
// The rule table is a direct port of propertyListingRules.ts, so these tests
// assert the *guards* — which rules fire for which category/listingType — since
// that is where a port silently diverges. The engine internals (isBlank, the
// numeric coercion, the regexes) are pinned separately in
// listing_validators_parity_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_validation_rules.dart';

/// Rule fields that fire for the given category/listingType with empty data,
/// evaluated ungated so the comparison is against React's table, not against
/// what Flutter can currently fill.
Set<String> firingFields(
  String step,
  PropertyCategory category,
  ListingIntent intent,
) {
  final p = PostPropertyProvider()
    ..setCategory(category)
    ..setListingIntent(intent);
  return validatePropertyStep(
    step,
    ListingFormData(p),
    onlyCollectable: false,
  ).map((i) => i.field).toSet();
}

void main() {
  setUp(() => WidgetsFlutterBinding.ensureInitialized());

  group('Step visibility of rules by category', () {
    test('land gets land dimensions, never bedrooms or soil-free fields', () {
      final f = firingFields(
        'Dimensions',
        PropertyCategory.land,
        ListingIntent.sell,
      );
      expect(
        f,
        containsAll(<String>[
          'front',
          'back',
          'right',
          'left',
          'soilType',
          'area',
          'availableFrom',
        ]),
      );
      // fsiFarAllowed/floorAllowed/heightRestriction are collected but have
      // no rule at all in propertyListingRules.ts for Land — optional there.
      expect(f, isNot(contains('fsiFarAllowed')));
      // surveyNumber (Khasra number) is required on the portal but
      // deliberately optional on this app only, per explicit product
      // direction — see listing_validation_rules.dart's own comment.
      expect(f, isNot(contains('surveyNumber')));
      expect(f, isNot(contains('floorAllowed')));
      expect(f, isNot(contains('heightRestriction')));
      expect(f, isNot(contains('bedrooms')));
      expect(f, isNot(contains('bathrooms')));
      expect(f, isNot(contains('carpetArea')));
      expect(f, isNot(contains('bhkType')));
    });

    test('residential gets BHK block, never land dimensions', () {
      final f = firingFields(
        'Dimensions',
        PropertyCategory.residential,
        ListingIntent.sell,
      );
      expect(
        f,
        containsAll(<String>[
          'bhkType',
          'bedrooms',
          'bathrooms',
          'balconies',
          'carpetArea',
          'totalFloors',
          'propertyCondition',
          'area',
          'availableFrom',
        ]),
      );
      expect(f, isNot(contains('soilType')));
      expect(f, isNot(contains('surveyNumber')));
    });

    test('commercial does NOT require plain area (it has no such input)', () {
      // propertyListingRules.ts:94 — commercial mirrors superBuiltUpArea into
      // area, so requiring `area` would be an error with no field to fix it.
      final f = firingFields(
        'Dimensions',
        PropertyCategory.commercial,
        ListingIntent.sell,
      );
      expect(f, isNot(contains('area')));
      expect(
        f,
        containsAll(<String>[
          'buildingName',
          'buildingCode',
          'buildingType',
          'totalFloorsBuilding',
          'plotArea',
          'superBuiltUpArea',
        ]),
      );
    });

    test('PG requires facing and carpet area, not BHK', () {
      final f = firingFields(
        'Dimensions',
        PropertyCategory.pg,
        ListingIntent.rent,
      );
      expect(f, contains('facing'));
      expect(f, contains('carpetArea'));
      expect(f, contains('totalFloors'));
      expect(f, isNot(contains('bhkType')));
      // availableFrom is land/residential only on this step.
      expect(f, isNot(contains('availableFrom')));
    });

    test('others requires carpet area but no category-specific block', () {
      final f = firingFields(
        'Dimensions',
        PropertyCategory.other,
        ListingIntent.sell,
      );
      expect(f, contains('carpetArea'));
      expect(f, contains('area'));
      expect(f, isNot(contains('soilType')));
      expect(f, isNot(contains('bedrooms')));
      expect(f, isNot(contains('buildingName')));
    });
  });

  // Not a React port — added on explicit request as a real ceiling on "Total
  // Floors", on top of the rendering-safety limits
  // PropertyDimensionsStep's floor-wise editors already impose on themselves.
  group('Total Floors ceiling (163) blocks Continue on Dimensions', () {
    String? messageFor(String field, List<ListingIssue> issues) {
      for (final issue in issues) {
        if (issue.field == field) return issue.message;
      }
      return null;
    }

    test('PG: 163 passes, 164 is rejected', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.pg)
        ..setListingIntent(ListingIntent.rent)
        ..setTotalFloors('163');
      expect(
        messageFor(
          'totalFloors',
          validatePropertyStep(
            'Dimensions',
            ListingFormData(p),
            onlyCollectable: false,
          ),
        ),
        isNull,
      );

      p.setTotalFloors('164');
      expect(
        messageFor(
          'totalFloors',
          validatePropertyStep(
            'Dimensions',
            ListingFormData(p),
            onlyCollectable: false,
          ),
        ),
        'Total floors cannot exceed 163.',
      );
    });

    test('Commercial: 163 passes, 164 is rejected', () {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.commercial)
        ..setListingIntent(ListingIntent.rent)
        ..setBuildingInventoryValue('totalFloorsBuilding', '163');
      expect(
        messageFor(
          'totalFloorsBuilding',
          validatePropertyStep(
            'Dimensions',
            ListingFormData(p),
            onlyCollectable: false,
          ),
        ),
        isNull,
      );

      p.setBuildingInventoryValue('totalFloorsBuilding', '164');
      expect(
        messageFor(
          'totalFloorsBuilding',
          validatePropertyStep(
            'Dimensions',
            ListingFormData(p),
            onlyCollectable: false,
          ),
        ),
        'Total floors in building cannot exceed 163.',
      );
    });
  });

  group('landUseMasterPlan is rent-only for land (Q7)', () {
    test('required when renting land', () {
      final f = firingFields(
        'Dimensions',
        PropertyCategory.land,
        ListingIntent.rent,
      );
      expect(f, contains('landUseMasterPlan'));
    });

    test('NOT required when selling or leasing land', () {
      for (final intent in [ListingIntent.sell, ListingIntent.lease]) {
        final f = firingFields('Dimensions', PropertyCategory.land, intent);
        expect(
          f,
          isNot(contains('landUseMasterPlan')),
          reason: 'should not fire for ${intent.name}',
        );
      }
    });
  });

  group('Apartment vs house branching', () {
    ListingFormData withSubtype(String subtype) {
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.rent)
        ..setResidentialSubType(subtype);
      return ListingFormData(p);
    }

    Set<String> fields(String step, String subtype) => validatePropertyStep(
      step,
      withSubtype(subtype),
      onlyCollectable: false,
    ).map((i) => i.field).toSet();

    test('apartment subtype requires floorNo and societyCharges', () {
      final dims = fields('Dimensions', 'Flat');
      expect(dims, contains('floorNo'));
      expect(dims, isNot(contains('builtUpArea')));

      final pricing = fields('Pricing', 'Flat');
      expect(pricing, contains('societyCharges'));
      expect(pricing, isNot(contains('maintenanceCharges')));
    });

    test('house subtype requires builtUpArea and maintenanceCharges', () {
      final dims = fields('Dimensions', 'Villa / Kothi');
      expect(dims, contains('builtUpArea'));
      expect(dims, isNot(contains('floorNo')));

      final pricing = fields('Pricing', 'Villa / Kothi');
      expect(pricing, contains('maintenanceCharges'));
      expect(pricing, isNot(contains('societyCharges')));
    });

    test('a LEGACY subtype string falls into the house branch', () {
      // 'Studio Apartment' is Flutter's legacy spelling; the canonical value is
      // 'Studio / Service Apartment'. T1 aliases it on read, but if an
      // un-aliased value ever reaches the rules it is treated as a house —
      // which is exactly why the alias matters.
      final dims = fields('Dimensions', 'Studio Apartment');
      expect(dims, contains('builtUpArea'));

      final canonical = fields('Dimensions', 'Studio / Service Apartment');
      expect(canonical, isNot(contains('builtUpArea')));
      expect(canonical, contains('floorNo'));
    });
  });

  group('Pricing rules by listing type', () {
    Set<String> pricing(PropertyCategory c, ListingIntent i) =>
        firingFields('Pricing', c, i);

    test('sell requires ratePerArea except for PG', () {
      expect(
        pricing(PropertyCategory.residential, ListingIntent.sell),
        contains('ratePerArea'),
      );
      expect(
        pricing(PropertyCategory.pg, ListingIntent.sell),
        isNot(contains('ratePerArea')),
      );
    });

    test('PG rent uses per-bed rent instead of price', () {
      final f = pricing(PropertyCategory.pg, ListingIntent.rent);
      expect(f, contains('monthlyRentPerBed'));
      expect(f, isNot(contains('price')));
      expect(f, containsAll(<String>['foodCharges', 'laundryCharges']));
    });

    test('PG lease DOES require price (only rent/sell are exempt)', () {
      // applies: !(isPg && listingType !== 'lease')
      final f = pricing(PropertyCategory.pg, ListingIntent.lease);
      expect(f, contains('price'));
    });

    test('PG sell requires sale price and occupancy, not lockInPeriod', () {
      final f = pricing(PropertyCategory.pg, ListingIntent.sell);
      expect(f, containsAll(<String>['totalSalePrice', 'occupancyRate']));
      expect(f, isNot(contains('lockInPeriod')));
    });

    test('rent/lease require deposit; sell does not', () {
      expect(
        pricing(PropertyCategory.residential, ListingIntent.rent),
        contains('securityDeposit'),
      );
      expect(
        pricing(PropertyCategory.residential, ListingIntent.sell),
        isNot(contains('securityDeposit')),
      );
    });

    test('commercial lease terms only for lease, ROI only for sell', () {
      const leaseTerms = <String>[
        'leaseDuration',
        'leaseEscalationPercent',
        'camCharges',
        'fitOutPeriod',
      ];
      final lease = pricing(PropertyCategory.commercial, ListingIntent.lease);
      expect(lease, containsAll(leaseTerms));
      expect(lease, isNot(contains('roiEstimate')));

      // The Pricing step hides Commercial Lease Terms on a rent listing, so
      // none of its fields may be required there.
      final rent = pricing(PropertyCategory.commercial, ListingIntent.rent);
      for (final f in leaseTerms) {
        expect(rent, isNot(contains(f)));
      }
      expect(rent, isNot(contains('roiEstimate')));

      final sell = pricing(PropertyCategory.commercial, ListingIntent.sell);
      expect(sell, containsAll(<String>['roiEstimate', 'currentRentalIncome']));
      expect(sell, isNot(contains('camCharges')));
    });

    test('land never requires maintenanceCharges on rent', () {
      final f = pricing(PropertyCategory.land, ListingIntent.rent);
      expect(f, isNot(contains('maintenanceCharges')));
    });

    test(
      'tokenAmount is required for every combination; brokerage never is',
      () {
        for (final c in PropertyCategory.values) {
          for (final i in ListingIntent.values) {
            final f = pricing(c, i);
            expect(f, contains('tokenAmount'), reason: '${c.name}/${i.name}');
            // Brokerage is optional for every user/category.
            expect(
              f,
              isNot(contains('brokerage')),
              reason: '${c.name}/${i.name}',
            );
          }
        }
      },
    );
  });

  group('Other steps', () {
    test('amenities rule fires for residential and others only', () {
      expect(
        firingFields(
          'Amenities',
          PropertyCategory.residential,
          ListingIntent.sell,
        ),
        contains('amenities'),
      );
      expect(
        firingFields('Amenities', PropertyCategory.other, ListingIntent.sell),
        contains('amenities'),
      );
      expect(
        firingFields('Amenities', PropertyCategory.pg, ListingIntent.rent),
        contains('pgAmenities'),
      );
      expect(
        firingFields('Amenities', PropertyCategory.land, ListingIntent.sell),
        isEmpty,
      );
    });

    test('legal step is land ownership + PG quiet hours only', () {
      expect(
        firingFields('Legal', PropertyCategory.land, ListingIntent.sell),
        containsAll(<String>['ownershipType', 'ownerName']),
      );
      expect(
        firingFields('Legal', PropertyCategory.pg, ListingIntent.rent),
        contains('quietHours'),
      );
      expect(
        firingFields('Legal', PropertyCategory.residential, ListingIntent.sell),
        isEmpty,
      );
    });

    test('media/contact rules are category-independent except PG extras', () {
      final res = firingFields(
        'Media',
        PropertyCategory.residential,
        ListingIntent.sell,
      );
      expect(
        res,
        containsAll(<String>[
          'mediaFiles',
          'contactName',
          'contactPhone',
          'whatsappNumber',
          'bestTimeToCall',
        ]),
      );
      expect(res, isNot(contains('ownerManagerName')));
      // Both deliberately optional on this app only (not required when
      // blank), per explicit product direction — see
      // listing_validation_rules.dart's own comment on each field.
      expect(res, isNot(contains('contactEmail')));
      expect(res, isNot(contains('hashtags')));

      final pg = firingFields('Media', PropertyCategory.pg, ListingIntent.rent);
      expect(pg, contains('ownerManagerName'));
      // alternateNumber's own rule in propertyListingRules.ts is permanently
      // disabled (`applies: () => false`) — it never fires for any category,
      // PG included, even though the field is collected.
      expect(pg, isNot(contains('alternateNumber')));
    });

    test('a complete 10-digit whatsappNumber passes format validation', () {
      // Regression guard: whatsappNumber's rule was a custom regex with a
      // typo (`RegExp(r'^d{10}$')`, missing the `\` before `d`), which
      // matched only the literal string "dddddddddd" and rejected every
      // real phone number unconditionally — "Please complete: WhatsApp
      // number" fired even with a correctly filled-in field. Now uses
      // `validWhatsappNumber` (exactly 10 digits, matching this field's
      // own digits-only, max-10 text input).
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell)
        ..setWhatsappNumber('9689589896');

      final issues = validatePropertyStep(
        'Media',
        ListingFormData(p),
        onlyCollectable: false,
      );

      expect(issues.map((i) => i.field), isNot(contains('whatsappNumber')));
    });

    test('an incomplete whatsappNumber (fewer than 10 digits) fails format '
        'validation', () {
      // Bug report: the field's own text input is digits-only and capped
      // at 10 characters, but its rule reused `validPhone`'s 8-15 range
      // (meant for a free-text field with "+91 98765 43210" punctuation)
      // — so an 8- or 9-digit entry passed as "valid" even though a real
      // WhatsApp number is always exactly 10 digits.
      for (final incomplete in ['96895898', '968958989']) {
        final p = PostPropertyProvider()
          ..setCategory(PropertyCategory.residential)
          ..setListingIntent(ListingIntent.sell)
          ..setWhatsappNumber(incomplete);

        final issues = validatePropertyStep(
          'Media',
          ListingFormData(p),
          onlyCollectable: false,
        );

        expect(
          issues.map((i) => i.field),
          contains('whatsappNumber'),
          reason:
              '"$incomplete" (${incomplete.length} digits) should not '
              'pass as a complete WhatsApp number',
        );
      }
    });
  });

  group('Enforcement gate', () {
    test(
      'every rule field the app collects is enforced identically gated or not',
      () {
        // The map pin used to be the one example of a rule that must be
        // evaluated (parity with React) but never block, because no input
        // collected it yet. LocationPickerMap / AddressAutocompleteField now
        // set latitude/longitude, so gated and ungated results are identical —
        // see "the not-yet-collectable set is down to the map pin" below.
        final p = PostPropertyProvider()
          ..setCategory(PropertyCategory.residential)
          ..setListingIntent(ListingIntent.sell);

        final gated = validatePropertyStep(
          'Basic Info',
          ListingFormData(p),
        ).map((i) => i.field).toSet();
        final ungated = validatePropertyStep(
          'Basic Info',
          ListingFormData(p),
          onlyCollectable: false,
        ).map((i) => i.field).toSet();

        expect(gated, ungated);
        expect(
          gated,
          containsAll(<String>['title', 'city', 'state', 'latitude']),
        );
      },
    );

    test('the not-yet-collectable set is now empty', () {
      // This list shrank with every category phase, then the map pin — the
      // last rule field with no matching input — closed when the address
      // field's autocomplete + the map picker both started setting
      // latitude/longitude.
      expect(kFieldsNotYetCollectable, isEmpty);
    });
  });

  group('Grandfathering', () {
    test('new listings are validated in full', () {
      final p = PostPropertyProvider();
      expect(p.grandfatheredBlankFields, isEmpty);
      expect(p.isStepValid(0), isFalse); // category/listingType missing
    });

    test('fields blank at load time are exempt for that edit session', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'sell',
          'title': 'Old listing',
          'metadata': <String, dynamic>{},
        },
      );

      // The row has no description/city/etc., so those were blank on load and
      // must not block re-saving it.
      expect(p.grandfatheredBlankFields, contains('description'));
      expect(p.grandfatheredBlankFields, contains('city'));
      expect(
        p.isStepValid(1),
        isTrue,
        reason: 'pre-existing blanks must not block an edit',
      );
    });

    test('a field the user fills is validated normally again', () {
      final p = PostPropertyProvider();
      p.initFromRawData(
        editingPropertyId: 'p1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'sell',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.grandfatheredBlankFields, contains('pincode'));

      // While still blank, the required check is suppressed.
      expect(
        p.issuesForStep(1).map((i) => i.field),
        isNot(contains('pincode')),
      );

      // Once the user types something, the FORMAT check applies again —
      // grandfathering exempts "you must supply a value", not validation
      // itself. A 2-digit pincode is invalid on the web too.
      p.setPincode('12');
      expect(p.issuesForStep(1).map((i) => i.field), contains('pincode'));

      // ...and a valid one clears it.
      p.setPincode('560001');
      expect(
        p.issuesForStep(1).map((i) => i.field),
        isNot(contains('pincode')),
      );
    });
  });

  group('Provider wiring', () {
    test('step getters and canGoNext are rules-driven', () {
      final p = PostPropertyProvider();
      expect(p.isStep1Valid, isFalse);
      expect(p.canGoNext, isFalse);

      p
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell);
      expect(p.isStep1Valid, isTrue);
      expect(p.canGoNext, isTrue);
    });

    test('Amenities and Legal are no longer unconditionally valid', () {
      // isStep5Valid / isStep6Valid used to `return true` outright.
      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell);
      expect(p.isStep5Valid, isFalse, reason: 'amenities now required');

      final land = PostPropertyProvider()
        ..setCategory(PropertyCategory.land)
        ..setListingIntent(ListingIntent.sell);
      // T8 gave ownershipType/ownerName real inputs, so Legal now blocks for
      // land instead of being gated clean.
      expect(land.isStep6Valid, isFalse);
      land
        ..setText('ownershipType', 'Freehold')
        ..setText('ownerName', 'A. Sharma');
      expect(land.isStep6Valid, isTrue);
    });

    test('firstInvalidStep points at the earliest problem', () {
      final p = PostPropertyProvider();
      expect(p.firstInvalidStep, 0);

      p
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.sell);
      expect(p.firstInvalidStep, 1);
    });
  });

  // Location/map bug fix — a resolved map pin must actually BE one, not
  // merely present. The existing 'latitude' rule above only checks
  // non-null; this is the stricter check layered on top of it.
  group('Map location validity', () {
    PostPropertyProvider baseProvider() => PostPropertyProvider()
      ..setCategory(PropertyCategory.residential)
      ..setListingIntent(ListingIntent.sell)
      ..setTitle('Modern 3BHK')
      ..setDescription('A description long enough to pass.')
      ..setLocation('MG Road')
      ..setCity('Pune')
      ..setState('Maharashtra');

    test('a genuinely resolved pin raises no location issue', () {
      final p = baseProvider()
        ..setLatitude(18.5204)
        ..setLongitude(73.8567);
      final issues = validatePropertyStep('Basic Info', ListingFormData(p));
      expect(issues.map((i) => i.field), isNot(contains('latitude')));
    });

    test('no pin at all is still just the existing "required" message', () {
      final p = baseProvider();
      final issues = validatePropertyStep('Basic Info', ListingFormData(p));
      final issue = issues.firstWhere((i) => i.field == 'latitude');
      expect(issue.message, contains('is required'));
    });

    test('a stale (0, 0) pair is rejected even though both are non-null', () {
      final p = baseProvider()
        ..setLatitude(0)
        ..setLongitude(0);
      final issues = validatePropertyStep('Basic Info', ListingFormData(p));
      final issue = issues.firstWhere((i) => i.field == 'latitude');
      expect(issue.message, isNot(contains('is required')));
      expect(issue.message, contains('valid location'));
    });

    test('an out-of-range latitude is rejected', () {
      final p = baseProvider()
        ..setLatitude(123.0)
        ..setLongitude(73.8567);
      final issues = validatePropertyStep('Basic Info', ListingFormData(p));
      expect(issues.map((i) => i.field), contains('latitude'));
    });

    test('a corrupted partial pair (only one coordinate set) is rejected', () {
      final p = baseProvider()..setLatitude(18.5204);
      // longitude left null — a real pin never resolves just one half.
      final issues = validatePropertyStep('Basic Info', ListingFormData(p));
      expect(issues.map((i) => i.field), contains('latitude'));
    });
  });
}
