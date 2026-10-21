// Regression guard for ReelModel's area precision/unit fix.
//
// Before: `sqft` was parsed with `int.tryParse`, which returns null outright
// for a decimal string ("1200.5") — silently dropping the area for both a
// linked property with a decimal area AND a manually-entered one (the
// manual Reel form's own "Area" field explicitly allows decimals). `areaUnit`
// was a fixed `'Sq.ft'` getter regardless of what a LINKED property's real
// unit actually was.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/reel_model.dart';

void main() {
  group('ReelModel — linked property', () {
    test('a decimal linked-property area is not dropped', () {
      final reel = ReelModel.fromSupabase({
        'id': 'r-1',
        'title': 'A reel',
        'description': '',
        'video_url': 'https://example.com/v.mp4',
        'video_type': 'property_listing',
        '_property': {'area': '2.75', 'area_unit': 'acres'},
      });

      expect(reel.sqft, 3); // rounded, unchanged legacy field
      expect(reel.areaValue, 2.75);
      expect(reel.areaLabel, '2.75');
      expect(reel.areaUnit, 'Acres');
    });

    test('a linked property with no override unit still reads "Sq.ft"', () {
      final reel = ReelModel.fromSupabase({
        'id': 'r-1',
        'title': 'A reel',
        'description': '',
        'video_url': 'https://example.com/v.mp4',
        'video_type': 'property_listing',
        '_property': {'area': '1200'},
      });

      expect(reel.areaUnit, 'Sq.ft');
    });
  });

  group('ReelModel — manually-entered listing video', () {
    test('a decimal manual area is not dropped (form allows decimals)', () {
      final reel = ReelModel.fromSupabase({
        'id': 'r-1',
        'title': 'A reel',
        'description': '',
        'video_url': 'https://example.com/v.mp4',
        'video_type': 'property_listing',
        'property_location': 'Manual Location',
        'property_area': '1200.5',
      });

      expect(reel.areaValue, 1200.5);
      expect(reel.areaLabel, '1200.5');
      // Manual entries have no unit picker anywhere in the upload form —
      // always sq.ft by that form's own convention, unaffected by a linked
      // property's unit.
      expect(reel.areaUnit, 'Sq.ft');
    });

    test('manual data is never influenced by a stray linked-property unit', () {
      final reel = ReelModel.fromSupabase({
        'id': 'r-1',
        'title': 'A reel',
        'description': '',
        'video_url': 'https://example.com/v.mp4',
        'video_type': 'property_listing',
        'property_location': 'Manual Location',
        'property_area': '5',
        // Even if a _property join were present, hasManualListing must win
        // outright for area/unit — mirrors the portal's own precedence.
        '_property': {'area': '999', 'area_unit': 'acres'},
      });

      expect(reel.areaValue, 5);
      expect(reel.areaUnit, 'Sq.ft');
    });
  });
}
