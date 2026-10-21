// Public profile — the Collab/Requested button.
//
// `PublicProfileScreen._canCollaborate` now returns false unconditionally
// while paid collaborations are disabled, which the button's own call site
// (`onCollaborate: _canCollaborate(profile) ? () => _collaborate(profile)
// : null`) turns into a null `onCollaborate`. This pins the half of that
// contract `ProfileStickyActionBar` (the real, shared widget both branches
// render through) is responsible for: a null `onCollaborate` must render no
// Collab/Requested button at all, paired with a positive control (a
// non-null `onCollaborate`) proving the button can render at all, so the
// negative case isn't just an unrelated rendering bug.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/screens/profile/widgets/public_profile_sticky_bar.dart';
import 'package:propcid_app/services/profile_connection_service.dart';

Widget _bar({required VoidCallback? onCollaborate}) {
  return MaterialApp(
    home: Scaffold(
      body: ProfileStickyActionBar(
        isSelf: false,
        viewerSignedIn: true,
        connectionStatus: ProfileConnectionStatus.none,
        statusLoading: false,
        onShare: () {},
        onMessage: () {},
        onCollaborate: onCollaborate,
      ),
    ),
  );
}

void main() {
  testWidgets('no Collab/Requested button when onCollaborate is null', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(onCollaborate: null));

    expect(find.text('Collab'), findsNothing);
    expect(find.text('Requested'), findsNothing);
    // The Message label only becomes "Chat" alongside a live collaborate
    // action — with it null, it reads as plain "Message".
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('the button does render when onCollaborate is set', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(onCollaborate: () {}));

    expect(find.text('Collab'), findsOneWidget);
  });
}
