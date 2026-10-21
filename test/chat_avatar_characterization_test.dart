// Characterization test for `ChatAvatar` — written against the CURRENT,
// unmodified widget, before any Module 2 image-decode experiment touches it.
//
// Module 0 of docs/PERFORMANCE_OPTIMIZATION_PLAN.md requires characterization
// tests to exist and pass against the unmodified application before any
// future optimization begins. `ChatAvatar` is one of the two candidate
// surfaces named in that plan's narrowed Module 2 first experiment.
//
// This test pins, as of this commit:
//   - the rendered (display) size is exactly `size` x `size`, regardless of
//     whether an avatar URL is present — this must never change, only the
//     *decode* size may change in a future experiment;
//   - the initials fallback renders when there is no avatar URL;
//   - when an avatar URL is present, a `CachedNetworkImage` is used with
//     `fit: BoxFit.cover` and `width`/`height` equal to `size`;
//   - today, `CachedNetworkImage.memCacheWidth`/`memCacheHeight` are both
//     null (no decode-size cap exists yet) — this is the deliberate "before"
//     state; a future experiment is expected to change these two fields and
//     nothing else, so this assertion documents exactly what "before" means.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/screens/messaging/widgets/chat_avatar.dart';

void main() {
  group('ChatAvatar characterization (pre-Module-2)', () {
    testWidgets('fallback: renders initials at the default 48x48 size '
        'when there is no avatar URL', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAvatar(avatarUrl: null, initials: 'AB'),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ChatAvatar)), const Size(48, 48));
      expect(find.text('AB'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('fallback: renders initials at a custom size when the '
        'avatar URL is an empty string', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAvatar(avatarUrl: '', initials: 'CD', size: 64),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ChatAvatar)), const Size(64, 64));
      expect(find.text('CD'), findsOneWidget);
    });

    testWidgets(
      'with an avatar URL: renders a CachedNetworkImage at exactly the '
      'requested display size, with no decode-size cap set today',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ChatAvatar(
                avatarUrl: 'https://example.invalid/avatar.png',
                initials: 'EF',
                size: 56,
              ),
            ),
          ),
        );

        // Display size must stay 56x56 regardless of any future decode-size
        // change — this is the dimension a future experiment must not alter.
        expect(tester.getSize(find.byType(ChatAvatar)), const Size(56, 56));

        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.imageUrl, 'https://example.invalid/avatar.png');
        expect(image.fit, BoxFit.cover);
        expect(image.width, 56);
        expect(image.height, 56);

        // The "before" state this characterization pins: no decode-size cap
        // exists yet. A future Module 2 experiment on this widget is expected
        // to set these two fields (DPR-aware) and change nothing else about
        // this widget's observable structure.
        expect(image.memCacheWidth, isNull);
        expect(image.memCacheHeight, isNull);
      },
    );
  });
}
