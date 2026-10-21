// Layout guard for the V2.1 PremiumLaunchBanner redesign.
//
// The banner packs a lot into a narrow card (2x2 feature grid, split price
// row, chips). This pumps it at the common phone widths and fails on ANY
// framework error — overflow, unbounded constraints, assertion — so a styling
// tweak can't silently start clipping on small devices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/widgets/premium_launch_banner.dart';

void main() {
  // Narrowest common Android, iPhone SE, iPhone 12/13/14, Pixel 7 Pro.
  for (final double width in <double>[320, 360, 375, 390, 412, 430]) {
    testWidgets('PremiumLaunchBanner lays out cleanly at ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final errors = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            // `enabled: true` — the launch-flags pass defaults this card
            // off (see LaunchFeatures.subscriptions); this suite is
            // exercising the card's own layout, unaffected by that pass.
            body: SingleChildScrollView(
              child: PremiumLaunchBanner(enabled: true),
            ),
          ),
        ),
      );
      // Let the entrance + ambient animations advance a few frames.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 900));

      FlutterError.onError = prev;

      expect(
        errors.map((e) => e.exception.toString()).toList(),
        isEmpty,
        reason: 'Framework errors at ${width}px wide',
      );

      // The card must actually render its key content.
      expect(find.textContaining('PropCID Pro'), findsWidgets);
      expect(find.text('Launch Price'), findsOneWidget);
      expect(find.text('Upgrade to Pro'), findsOneWidget);
    });
  }
}
