// Pins `isValidCoordinatePair` — the shared rule every location/map bug fix
// in this app (property/project listing validation, the property detail
// page's map + "Get Directions" gate) relies on to tell a real, resolved
// pin apart from an unset, corrupted, or `(0, 0)` default one.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/utils/geo_utils.dart';

void main() {
  group('isValidCoordinatePair', () {
    test('a real, in-range pair is valid', () {
      expect(isValidCoordinatePair(18.5204, 73.8567), isTrue);
    });

    test('the physical range boundaries themselves are valid', () {
      expect(isValidCoordinatePair(90, 180), isTrue);
      expect(isValidCoordinatePair(-90, -180), isTrue);
      expect(isValidCoordinatePair(0, 45), isTrue); // lat 0 alone is fine
      expect(isValidCoordinatePair(45, 0), isTrue); // lng 0 alone is fine
    });

    test('both null is rejected', () {
      expect(isValidCoordinatePair(null, null), isFalse);
    });

    test('a partial pair (only one coordinate present) is rejected', () {
      expect(isValidCoordinatePair(18.5204, null), isFalse);
      expect(isValidCoordinatePair(null, 73.8567), isFalse);
    });

    test('non-finite values are rejected', () {
      expect(isValidCoordinatePair(double.nan, 73.8567), isFalse);
      expect(isValidCoordinatePair(18.5204, double.nan), isFalse);
      expect(isValidCoordinatePair(double.infinity, 73.8567), isFalse);
      expect(isValidCoordinatePair(18.5204, double.negativeInfinity), isFalse);
    });

    test('out-of-range latitude is rejected', () {
      expect(isValidCoordinatePair(90.1, 73.8567), isFalse);
      expect(isValidCoordinatePair(-90.1, 73.8567), isFalse);
    });

    test('out-of-range longitude is rejected', () {
      expect(isValidCoordinatePair(18.5204, 180.1), isFalse);
      expect(isValidCoordinatePair(18.5204, -180.1), isFalse);
    });

    test(
      '(0, 0) — "Null Island", the default/unresolved value — is rejected',
      () {
        expect(isValidCoordinatePair(0, 0), isFalse);
      },
    );
  });
}
