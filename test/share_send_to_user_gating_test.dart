// "Send to a user" gating across the three share sheets.
//
// The portal only allows it for property and video shares — `canSendToUser`
// in ShareToSocial.tsx is `data.type === 'property' || data.type === 'video'`
// — never for project. These tests lock in that same gate on mobile: the
// button shows for Property/Reel only when a user is signed in, and never at
// all for Project, matching the portal's own behavior exactly rather than
// inventing a richer project share.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/reel_model.dart';
import 'package:propcid_app/screens/project/widgets/share_project_sheet.dart';
import 'package:propcid_app/screens/property_detail/widgets/share_property_sheet.dart';
import 'package:propcid_app/screens/reels/widgets/share_reel_sheet.dart';

ReelModel _reel() => ReelModel.fromSupabase({
  'id': 'v-1',
  'title': 'Sea View 3BHK',
  'description': '',
  'video_url': 'https://cdn.test/v-1.mp4',
});

void main() {
  group('Property share sheet', () {
    testWidgets('shows "Send to a user" when signed in', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return ElevatedButton(
                  onPressed: () => showSharePropertySheet(
                    ctx,
                    propertyId: 'p-1',
                    title: 'Sea View 3BHK',
                    currentUserId: 'u-1',
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Send to a user'), findsOneWidget);
    });

    testWidgets('hides "Send to a user" when signed out', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return ElevatedButton(
                  onPressed: () => showSharePropertySheet(
                    ctx,
                    propertyId: 'p-1',
                    title: 'Sea View 3BHK',
                    currentUserId: null,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Send to a user'), findsNothing);
    });
  });

  group('Reel share sheet', () {
    testWidgets('shows "Send to a user" when signed in', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return ElevatedButton(
                  onPressed: () => showShareReelSheet(
                    ctx,
                    reel: _reel(),
                    currentUserId: 'u-1',
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Send to a user'), findsOneWidget);
    });

    testWidgets('hides "Send to a user" when signed out', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return ElevatedButton(
                  onPressed: () => showShareReelSheet(
                    ctx,
                    reel: _reel(),
                    currentUserId: null,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Send to a user'), findsNothing);
    });
  });

  group('Project share sheet', () {
    testWidgets('never shows "Send to a user" — the portal has no such '
        'option for projects either', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return ElevatedButton(
                  onPressed: () => showShareProjectSheet(
                    ctx,
                    projectId: 'proj-1',
                    title: 'Green Valley Heights',
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Share Project'), findsOneWidget);
      expect(find.text('Send to a user'), findsNothing);
    });
  });
}
