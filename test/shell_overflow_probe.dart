// Temporary probe: reproduces the shell RenderFlex overflow and reports which
// RenderFlex and by how much. Deleted after use.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/portal_shell.dart';

void main() {
  for (final size in const [
    Size(390, 844), // iPhone 14
    Size(360, 640), // small Android
    Size(320, 568), // iPhone SE 1
    Size(1280, 800), // web
  ]) {
    testWidgets('progress card @ ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p = PostPropertyProvider()
        ..setCategory(PropertyCategory.residential)
        ..setListingIntent(ListingIntent.rent);

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
          value: p,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: PortalProgressCard(
                  steps: p.visibleSteps,
                  currentIndex: p.currentStep,
                  onStepTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final ex = tester.takeException();
      debugPrint('=== ${size.width}x${size.height}: '
          '${ex == null ? "clean" : ex.toString().split("\n").first}');
      final card = find.byType(PortalProgressCard);
      if (card.evaluate().isNotEmpty) {
        debugPrint('    card height = ${tester.getSize(card).height}');
      }
    });
  }
}
