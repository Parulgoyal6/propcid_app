// Influencer dashboard — "Quick Actions" grid.
//
// Two of the original four tiles (Campaigns, Earnings) were `() {}` — a
// visible button that silently did nothing — and Analytics had nowhere to
// go at all. This pins:
//   * Upload Video still opens the influencer video form, unchanged;
//   * Analytics calls back to the dashboard instead of doing nothing;
//   * Campaigns is absent while Meta publishing is disabled (the default)
//     and, when enabled, opens the real Social Campaigns screen — never a
//     dead button either way;
//   * Earnings is gone outright — no placeholder destination invented.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/screens/widgets/influencer_quick_actions_widget.dart';

Future<List<String?>> _pumpWidget(
  WidgetTester tester, {
  required VoidCallback onAnalyticsTap,
  bool? metaPublishingEnabled,
}) async {
  final pushed = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InfluencerQuickActionsWidget(
          onAnalyticsTap: onAnalyticsTap,
          metaPublishingEnabled: metaPublishingEnabled,
        ),
      ),
      onGenerateRoute: (settings) {
        pushed.add(settings.name);
        return MaterialPageRoute(builder: (_) => const SizedBox.shrink());
      },
    ),
  );
  return pushed;
}

void main() {
  testWidgets('Upload Video still opens the influencer video form', (
    tester,
  ) async {
    final pushed = await _pumpWidget(tester, onAnalyticsTap: () {});

    await tester.tap(find.text('Upload Video'));
    await tester.pumpAndSettle();

    expect(pushed, contains(AppConstants.influencerVideoFormScreen));
  });

  testWidgets('Analytics calls back to the dashboard instead of no-op', (
    tester,
  ) async {
    var tapped = false;
    await _pumpWidget(tester, onAnalyticsTap: () => tapped = true);

    await tester.tap(find.text('Analytics'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  group('Campaigns', () {
    testWidgets('is hidden while Meta publishing is disabled (the default)', (
      tester,
    ) async {
      await _pumpWidget(tester, onAnalyticsTap: () {});

      expect(find.text('Campaigns'), findsNothing);
    });

    testWidgets('opens the real Social Campaigns screen once enabled', (
      tester,
    ) async {
      final pushed = await _pumpWidget(
        tester,
        onAnalyticsTap: () {},
        metaPublishingEnabled: true,
      );

      expect(find.text('Campaigns'), findsOneWidget);
      await tester.tap(find.text('Campaigns'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppConstants.socialCampaignsScreen));
    });
  });

  testWidgets('Earnings is never displayed — no placeholder destination', (
    tester,
  ) async {
    await _pumpWidget(tester, onAnalyticsTap: () {});
    await _pumpWidget(
      tester,
      onAnalyticsTap: () {},
      metaPublishingEnabled: true,
    );

    expect(find.text('Earnings'), findsNothing);
  });

  testWidgets('lays out without overflow with two or three tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpWidget(tester, onAnalyticsTap: () {});
    expect(tester.takeException(), isNull);

    await _pumpWidget(
      tester,
      onAnalyticsTap: () {},
      metaPublishingEnabled: true,
    );
    expect(tester.takeException(), isNull);
  });
}
