// Price parsing — the canonical parser backing display, budget filtering
// and price sorting alike (see lib/core/utils/listing_price_parser.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/core/utils/listing_price_parser.dart';

void main() {
  group('parseListingPrice', () {
    test('plain rupee amount', () {
      expect(parseListingPrice('4500000'), 4500000);
    });

    test('decimal numeric amount', () {
      expect(parseListingPrice('4500000.50'), 4500000.5);
    });

    test('a raw num is accepted directly', () {
      expect(parseListingPrice(12000000), 12000000);
      expect(parseListingPrice(12000000.0), 12000000.0);
    });

    test('Indian comma grouping', () {
      expect(parseListingPrice('45,00,000'), 4500000);
    });

    test('₹ prefix with Indian comma grouping', () {
      expect(parseListingPrice('₹95,00,000'), 9500000);
    });

    test('Lakh suffix, spaced', () {
      expect(parseListingPrice('85 Lakh'), 8500000);
    });

    test('L suffix, no space', () {
      expect(parseListingPrice('85L'), 8500000);
    });

    test('Lac suffix', () {
      expect(parseListingPrice('85 Lac'), 8500000);
    });

    test('Cr suffix, spaced decimal', () {
      expect(parseListingPrice('1.2 Cr'), 12000000);
    });

    test('crore, full word, lowercase', () {
      expect(parseListingPrice('1.2 crore'), 12000000);
    });

    test('upper/lowercase and extra whitespace variations', () {
      expect(parseListingPrice('  1.2   CR  '), 12000000);
      expect(parseListingPrice('85 LAKH'), 8500000);
      expect(parseListingPrice('85lakh'), 8500000);
    });

    test('null is unknown', () {
      expect(parseListingPrice(null), isNull);
    });

    test('blank string is unknown', () {
      expect(parseListingPrice(''), isNull);
      expect(parseListingPrice('   '), isNull);
    });

    test('zero is unknown, never a valid price', () {
      expect(parseListingPrice('0'), isNull);
      expect(parseListingPrice(0), isNull);
      expect(parseListingPrice(0.0), isNull);
    });

    test('negative is unknown', () {
      expect(parseListingPrice('-5000'), isNull);
      expect(parseListingPrice(-5000), isNull);
    });

    test('"Contact for price" is unknown', () {
      expect(parseListingPrice('Contact for price'), isNull);
      expect(parseListingPrice('CONTACT FOR PRICE'), isNull);
    });

    test('malformed text is unknown', () {
      expect(parseListingPrice('asdf'), isNull);
      expect(parseListingPrice('1.2.3.4'), isNull);
      expect(parseListingPrice('N/A'), isNull);
      expect(parseListingPrice('-'), isNull);
    });
  });

  group('resolveEffectivePrice', () {
    test('a valid price is preferred over price_min', () {
      final row = {'price': '45,00,000', 'price_min': 9999999};
      expect(resolveEffectivePrice(row), 4500000);
    });

    test('price_min is used only when the headline price is invalid', () {
      final row = {'price': 'Contact for price', 'price_min': 7500000};
      expect(resolveEffectivePrice(row), 7500000);
    });

    test('an invalid/zero price_min never masks a valid price', () {
      final row = {'price': '45,00,000', 'price_min': 0};
      expect(resolveEffectivePrice(row), 4500000);
    });

    test('both invalid resolves to unknown', () {
      final row = {'price': 'Contact for price', 'price_min': 0};
      expect(resolveEffectivePrice(row), isNull);
    });

    test('missing keys resolve to unknown, not a crash', () {
      expect(resolveEffectivePrice(<String, dynamic>{}), isNull);
    });
  });
}
