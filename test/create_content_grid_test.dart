// "Create Content" grid — the first tile's label.
//
// A builder's "Add Property" tile actually opens the project wizard
// (`PostPropertyRouteGate` swaps it server-side-of-the-UI, see
// post_property_route_gate.dart), so the label was out of step with what it
// opens. `propertyTileLabel` lets the Profile screen say "Add Project" for a
// builder without touching the callback/navigation at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/screens/profile/widgets/create_content_grid.dart';

void main() {
  testWidgets('defaults to "Add Property" when no label is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CreateContentGrid(onAddProperty: () {})),
      ),
    );
    expect(find.text('Add Property'), findsOneWidget);
    expect(find.text('Add Project'), findsNothing);
  });

  testWidgets('shows the overridden label when one is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateContentGrid(
            onAddProperty: () {},
            propertyTileLabel: 'Add Project',
          ),
        ),
      ),
    );
    expect(find.text('Add Project'), findsOneWidget);
    expect(find.text('Add Property'), findsNothing);
  });

  testWidgets(
    'tapping the tile still fires onAddProperty regardless of label',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateContentGrid(
              onAddProperty: () => tapped = true,
              propertyTileLabel: 'Add Project',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add Project'));
      expect(tapped, isTrue);
    },
  );
}
