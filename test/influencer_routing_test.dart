// Spec A — influencer routing.
//
// Six influencer entry points were audited. Three navigated somewhere the user
// could not do what the button said:
//
//   1. influencer_dashboard_screen.dart `_onCreate` → /post-property, feeding a FAB
//      whose semantic label is "Upload video", a button reading "Upload Video" and
//      an empty state reading "Upload Your First Video";
//   2. influencer_quick_actions_widget.dart "Upload Video" → `() {}`;
//   3. profile_tools.dart post_content(video) → /reels, the consumer feed.
//
// The other three are shared, role-blind surfaces (the bottom-nav "+", Home's
// "Post Property" quick action, the Profile screen's "Add Property" tiles) and are
// deliberately unchanged: CreateContent.tsx:379-402 gives an influencer three
// create buttons where every other role gets two, so listing is a capability they
// have. Repointing a button labelled "Post Property" at a video form would both
// remove that capability and lie about the destination.
//
// The gate's own decision table lives in post_property_route_gate_test.dart. What
// this file pins is that each entry point now names the right route.
//
// UPDATE — the "later phase" this file's own comment anticipated
// -----------------------------------------------------------------------
// Analytics/Campaigns/Earnings were "stated rather than fixed": three visible
// buttons that took a tap and did nothing, asserted here only so that gap
// wouldn't go unnoticed. They're fixed now — Analytics calls back to the
// dashboard's own tab, Campaigns is gated on `LaunchFeatures.metaPublishing`
// (present, when enabled) and Earnings was removed outright — full coverage
// of that is `test/influencer_quick_actions_test.dart`; the group below keeps
// only what is still this file's concern, that "Upload Video" names the
// right route.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/screens/home/widgets/quick_actions_section.dart';
import 'package:propcid_app/screens/widgets/influencer_quick_actions_widget.dart';
import 'package:propcid_app/voice_agent/models/tool_context.dart';
import 'package:propcid_app/voice_agent/tools/profile_tools.dart';
import 'package:propcid_app/voice_agent/tools/registry.dart';

/// Pumps [child], recording every named push.
///
/// [size] widens for the Home quick-action rail: it is a horizontal
/// `ListView.builder`, so its fifth tile is built but sits at x = 404 on a phone
/// and cannot be tapped. Five 152 dp tiles plus gaps need ~840 dp.
Future<List<RouteSettings>> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
      onGenerateRoute: (settings) {
        pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

void main() {
  // ── 1. The influencer dashboard's quick actions ─────────────────────────
  group('InfluencerQuickActionsWidget', () {
    testWidgets('"Upload Video" opens the video form', (tester) async {
      // Was `() {}` — it rendered, it took the tap, and nothing happened.
      final pushed = await _pump(
        tester,
        DefaultTextStyle(
          style: const TextStyle(),
          child: InfluencerQuickActionsWidget(onAnalyticsTap: () {}),
        ),
      );

      await tester.tap(find.text('Upload Video'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.influencerVideoFormScreen);
    });
  });

  // ── 2. The shared surfaces stay pointed at the listing wizard ───────────
  group('shared create surfaces', () {
    testWidgets('Home\'s "Post Property" quick action is unchanged', (
      tester,
    ) async {
      // An influencer sees this tile. It must still list a property.
      final pushed = await _pump(
        tester,
        const QuickActionsSection(),
        size: const Size(900, 400),
      );

      await tester.tap(find.text('Post Property'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.postPropertyScreen);
    });
  });

  // ── 3. The voice agent ──────────────────────────────────────────────────
  group('post_content', () {
    setUpAll(registerProfileTools);

    Future<String?> run(String type, String? userType) async {
      String? destination;
      final result = await toolRegistry.execute(
        'post_content',
        {'type': type},
        ToolContext(
          navigate: (route) => destination = route,
          userType: userType,
          userId: 'u-1',
        ),
      );
      return result.success ? destination : null;
    }

    test('an influencer asking to post a video reaches the form', () async {
      // Was '/reels' — a feed with no way to create anything.
      expect(await run('video', 'influencer'), '/influencer-video');
      expect(await run('reel', 'influencer'), '/influencer-video');
    });

    test('a non-influencer is still refused, not redirected', () async {
      // This branch already gated correctly; only its destination was wrong.
      for (final role in ['broker', 'builder', 'individual']) {
        expect(await run('video', role), isNull, reason: 'for $role');
      }
    });

    test(
      'an influencer asking to post a property still gets the wizard',
      () async {
        expect(await run('property', 'influencer'), '/post-property');
      },
    );

    test('the other content types are untouched', () async {
      expect(await run('property', 'broker'), '/post-property');
      expect(await run('article', 'broker'), '/profile');
      expect(await run('property', 'builder'), isNull);
    });
  });
}
