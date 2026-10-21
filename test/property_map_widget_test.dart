// Location/map bug fix — PropertyMapWidget must not crash when its
// coordinates change after the widget already mounted (the property detail
// screen's cached-then-authoritative data swap). The actual camera
// animation can't be observed here (no real GoogleMap platform view in a
// widget test), but `didUpdateWidget` running safely — including when the
// map controller hasn't been created yet, since GoogleMap's platform view
// never actually initializes in this test environment — is itself the
// regression this guards: a null controller must never throw.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/widgets/property_map_widget.dart';

void main() {
  testWidgets('coordinates changing after mount does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PropertyMapWidget(
          latitude: 18.5204,
          longitude: 73.8567,
          title: 'Sea View 3BHK',
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The cached-to-authoritative swap: same widget slot, new coordinates.
    await tester.pumpWidget(
      const MaterialApp(
        home: PropertyMapWidget(
          latitude: 19.0760,
          longitude: 72.8777,
          title: 'Sea View 3BHK',
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('identical coordinates on rebuild do not throw either', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PropertyMapWidget(
          latitude: 18.5204,
          longitude: 73.8567,
          title: 'Sea View 3BHK',
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(
        home: PropertyMapWidget(
          latitude: 18.5204,
          longitude: 73.8567,
          title: 'Sea View 3BHK — renamed',
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
