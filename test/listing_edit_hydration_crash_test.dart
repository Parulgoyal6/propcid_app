// P0 regression guard: initFromRawData() must never throw on a malformed
// field, and must never let one malformed field abort hydration of every
// field assigned after it.
//
// Real-device logs proved the actual bug: a legacy string boolean in
// `metadata.solarBackup` hit `as bool?` at what was line 1398
// (`_solarPower = (meta['solarBackup'] ?? meta['solarPower']) as bool? ??
// false;`), threw `type 'String' is not a subtype of type 'bool?'`, and
// silently blanked every field assigned after it — including fields that
// have nothing to do with solar power (owner name, ownership type,
// brokerage, contact info, hashtags), because they're simply never reached.
// This is why the bug looked "random" across categories: whichever bool/
// numeric field happened to be stored as a string in a given row decided
// where hydration stopped.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';

void main() {
  group(
    'initFromRawData is failure-resistant to legacy string bool/number values',
    () {
      test(
        'a string boolean anywhere in metadata does not abort hydration of later fields',
        () {
          final provider = PostPropertyProvider();

          // Every boolean/numeric field initFromRawData reads, deliberately
          // stored as a legacy string value instead of a real JSON bool/number —
          // this is exactly the shape a hard `as bool?`/`as num?` cast throws on.
          provider.initFromRawData(
            editingPropertyId: 'prop-1',
            propertyRow: {
              'id': 'prop-1',
              'category': 'land',
              'property_type': 'sell',
              'title': 'Legacy row with string booleans',
              'description': 'desc',
              'location': 'loc',
              'latitude': '12.34', // string, not num
              'longitude': '56.78', // string, not num
              'price': '1000000',
              'area': '1500',
              'area_unit': 'sq_ft',
              'hashtags': ['plot'],
              'is_negotiable':
                  'true', // string, not bool — this alone used to crash
              'metadata': {
                'solarBackup':
                    'false', // the exact field that crashed on-device
                'gasPipeline': '1',
                'internetAvailability': 'yes',
                'guardRoom': 'no',
                'reraRegistered': 0,
                'saleDeed': 'TRUE',
                'registryCopy': '',
                'nocAvailable': 1,
                'encumbranceFree': 'false',
                'loanApproved': 'true',
                'propertyApproved': 'yes',
                'priceNegotiable': 'true',
                'allInclusivePriceToggle': '1',
                'taxGovtChargesIncluded': 'no',
                'loanAvailability': 'yes',
                // Fields AFTER the ones above, in source order — these are what
                // used to come back blank once the cast above threw.
                'ownerName': 'Rahul Gandhi',
                'ownershipType': 'Co-Operative Society',
                'brokerage': '1%',
                'tokenAmount': '10000',
                'contactName': 'Komal',
              },
            },
            subtableRow: {
              'property_id': 'prop-1',
              'furnished': 'true', // string, not bool
              'boundary_wall': 'yes', // string, not bool
              'soil_type': 'Chalky Soil',
            },
            contactRow: {
              'property_id': 'prop-1',
              'contact_phone': '9876543210',
              'contact_email': 'seller@example.com',
            },
          );

          // Must not have thrown to get here. Every field, including the ones
          // that come after the crash point in source order, must be populated.
          expect(provider.latitude, 12.34);
          expect(provider.longitude, 56.78);
          expect(provider.priceNegotiable, true);
          expect(provider.text('ownerName'), 'Rahul Gandhi');
          expect(provider.text('ownershipType'), 'Co-Operative Society');
          expect(provider.brokerage, '1%');
          expect(provider.bookingAmount, '10000');
          expect(provider.contactPhone, '9876543210');
          expect(provider.contactEmail, 'seller@example.com');
          expect(provider.hashtags, '#plot');
          expect(provider.text('soilType'), 'Chalky Soil');
          expect(provider.boolVal('boundary'), true);
        },
      );

      test(
        'empty-string and null booleans/numbers fall back to their defaults, not a crash',
        () {
          final provider = PostPropertyProvider();

          provider.initFromRawData(
            editingPropertyId: 'prop-2',
            propertyRow: {
              'id': 'prop-2',
              'category': 'residential',
              'property_type': 'sell',
              'title': 't',
              'description': 'd',
              'location': 'l',
              'latitude': '', // blank string
              'longitude': null,
              'price': '100',
              'area': '100',
              'area_unit': 'sq_ft',
              'hashtags': <String>[],
              'is_negotiable': '', // blank string
              'metadata': {'solarBackup': '', 'gasPipeline': null},
            },
            subtableRow: {
              'property_id': 'prop-2',
              'furnished': '', // blank string
            },
          );

          expect(provider.latitude, isNull);
          expect(provider.longitude, isNull);
          expect(provider.priceNegotiable, false);
        },
      );
    },
  );
}
