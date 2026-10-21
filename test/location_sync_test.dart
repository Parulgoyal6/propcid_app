// Pins `decideLocationSync` — the pure decision logic behind
// `LocationPickerMap.didUpdateWidget`, extracted specifically so this
// branching is testable without a real `GoogleMap` platform view (not
// available in a widget test in this environment). Production behavior is
// unchanged: `LocationPickerMap` itself just calls this function and acts
// on the three-way result.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/widgets/location_picker_map.dart';

void main() {
  group('decideLocationSync', () {
    test('no prior and no new coordinates — nothing to do', () {
      final action = decideLocationSync(
        oldLat: null,
        oldLng: null,
        newLat: null,
        newLng: null,
        currentSelectedLat: null,
        currentSelectedLng: null,
      );
      expect(action, LocationSyncAction.none);
    });

    test(
      'a first resolved location (autocomplete fills in after mount) moves the pin',
      () {
        final action = decideLocationSync(
          oldLat: null,
          oldLng: null,
          newLat: 18.5204,
          newLng: 73.8567,
          currentSelectedLat: null,
          currentSelectedLng: null,
        );
        expect(action, LocationSyncAction.moveTo);
      },
    );

    test('a second, different resolved location also moves the pin', () {
      final action = decideLocationSync(
        oldLat: 18.5204,
        oldLng: 73.8567,
        newLat: 19.0760,
        newLng: 72.8777,
        currentSelectedLat: 18.5204,
        currentSelectedLng: 73.8567,
      );
      expect(action, LocationSyncAction.moveTo);
    });

    test('identical old and new coordinates do nothing — no repeated animation '
        'for an unrelated rebuild', () {
      final action = decideLocationSync(
        oldLat: 18.5204,
        oldLng: 73.8567,
        newLat: 18.5204,
        newLng: 73.8567,
        currentSelectedLat: 18.5204,
        currentSelectedLng: 73.8567,
      );
      expect(action, LocationSyncAction.none);
    });

    test('coordinates explicitly cleared while the map still shows the old pin '
        'clears it', () {
      final action = decideLocationSync(
        oldLat: 18.5204,
        oldLng: 73.8567,
        newLat: null,
        newLng: null,
        currentSelectedLat: 18.5204,
        currentSelectedLng: 73.8567,
      );
      expect(action, LocationSyncAction.clear);
    });

    test('coordinates cleared, but the user already moved the pin themselves '
        '(a tap in progress) — do not undo their own selection', () {
      final action = decideLocationSync(
        oldLat: 18.5204,
        oldLng: 73.8567,
        newLat: null,
        newLng: null,
        // The user tapped a different point before the parent's clear
        // arrived — `_selected` no longer matches the old prop pair.
        currentSelectedLat: 19.0760,
        currentSelectedLng: 72.8777,
      );
      expect(action, LocationSyncAction.none);
    });

    test('nothing was ever set and still is not — no-op, not a clear', () {
      final action = decideLocationSync(
        oldLat: null,
        oldLng: null,
        newLat: null,
        newLng: null,
        currentSelectedLat: null,
        currentSelectedLng: null,
      );
      expect(action, LocationSyncAction.none);
    });

    test('a partial old pair (corrupted/in-flight) with nothing new is treated '
        'as "nothing to clear" rather than guessing', () {
      final action = decideLocationSync(
        oldLat: 18.5204,
        oldLng: null,
        newLat: null,
        newLng: null,
        currentSelectedLat: null,
        currentSelectedLng: null,
      );
      expect(action, LocationSyncAction.none);
    });
  });

  group('decideLocationSync never implies calling onLocationSelected', () {
    test('the return type carries no callback/value a caller could mistake '
        'for "the user selected something" — only an action to perform', () {
      // Structural guarantee, not a runtime one: every possible result is
      // one of exactly three enum values, none of which carry
      // coordinates or any other payload a caller could forward to
      // onLocationSelected. A caller can only switch on the action and
      // move/clear the local pin — there is nothing here to feed back
      // into "the user picked a location".
      expect(LocationSyncAction.values, [
        LocationSyncAction.none,
        LocationSyncAction.moveTo,
        LocationSyncAction.clear,
      ]);
    });
  });
}
