// Meta publishing dialogs — the three functions property creation, article
// creation and influencer video/reel creation all call automatically once a
// new item is saved: `showPublishEverywhereDialog`, `offerBoostDialog` and
// `showCreateCampaignDialog`.
//
// All three creation flows call these same shared functions (see
// `property_submission_confirmation_screen.dart`'s `_offerPublish`,
// `article_editor_screen.dart`'s `_offerPublish`/`_offerBoost`, and
// `influencer_video_form_screen.dart`'s default publish/boost launchers), so
// proving these three return immediately with Meta publishing disabled
// proves none of the three creation flows can pop either dialog — without
// needing to drive each full creation screen (property save, article
// submit, video upload) end to end.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/screens/social/create_campaign_dialog.dart';
import 'package:propcid_app/screens/social/publish_everywhere_dialog.dart';

Future<void> _pumpHarness(
  WidgetTester tester,
  Future<void> Function() open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              ElevatedButton(onPressed: open, child: const Text('trigger')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('trigger'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showPublishEverywhereDialog returns immediately', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await _pumpHarness(
      tester,
      () => showPublishEverywhereDialog(
        ctx,
        userId: 'u-1',
        contentType: 'property',
        contentId: 'p-1',
        mediaUrls: const [],
      ),
    );

    expect(find.byType(PublishEverywhereDialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('offerBoostDialog returns immediately', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await _pumpHarness(
      tester,
      () => offerBoostDialog(
        ctx,
        userId: 'u-1',
        contentType: 'article',
        contentId: 'a-1',
      ),
    );

    expect(find.text('Boost on Meta ads?'), findsNothing);
    expect(find.byType(CreateCampaignDialog), findsNothing);
  });

  testWidgets('showCreateCampaignDialog returns immediately', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await _pumpHarness(
      tester,
      () => showCreateCampaignDialog(
        ctx,
        userId: 'u-1',
        contentType: 'reel',
        contentId: 'r-1',
      ),
    );

    expect(find.byType(CreateCampaignDialog), findsNothing);
  });
}
