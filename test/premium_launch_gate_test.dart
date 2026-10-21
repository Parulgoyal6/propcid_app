// Premium launch bottom sheet — the one-time upsell Home shows via
// `PremiumLaunchBottomSheet.showOnce`, called unconditionally from
// `HomeScreen.initState`.
//
// With subscriptions disabled (the default), `showOnce` must return before
// ever showing the sheet — and, just as important, before marking the
// one-time session gate as shown, so re-enabling the feature later still
// gets its first real showing rather than finding the gate already burned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/widgets/premium_launch_bottom_sheet.dart';

void main() {
  testWidgets('does not show the sheet, and does not burn the one-time gate', (
    tester,
  ) async {
    expect(
      LaunchOfferSessionGate.canShow,
      isTrue,
      reason: 'starting assumption for this test',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PremiumLaunchBottomSheet.showOnce(context),
              child: const Text('open home'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open home'));
    await tester.pumpAndSettle();

    expect(find.byType(PremiumLaunchBottomSheet), findsNothing);
    expect(
      LaunchOfferSessionGate.canShow,
      isTrue,
      reason:
          'a disabled build must not spend the one-time gate showing '
          'nothing',
    );
  });
}
