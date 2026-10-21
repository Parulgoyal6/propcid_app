// The floating AI orb previously stayed visible and tappable behind its own
// open VoiceAgentPanel, so a repeated tap opened another panel on top of the
// first, and again — effectively unlimited stacked panels ("as many tabs as
// he wants"). It must now disappear for as long as its own panel is open,
// and reappear once the panel is dismissed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/app_navigator.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/voice_agent/floating_ai_orb_visibility.dart';
import 'package:propcid_app/voice_agent/providers/voice_agent_provider.dart';
import 'package:propcid_app/voice_agent/widgets/floating_ai_orb.dart';
import 'package:propcid_app/voice_agent/widgets/voice_agent_panel.dart';

import 'support/fake_auth_service.dart';

void main() {
  tearDown(() => floatingAiOrbVisible.value = true);

  // `FloatingAiOrb` is one permanent widget in the tree (mounted once in the
  // Stack below) whose own `build()` returns `SizedBox.shrink()` while
  // hidden — so `find.byType(FloatingAiOrb)` matches it either way. The
  // orb's icon only exists in the tree while it's actually painting itself,
  // so that (not the widget type) is the correct "is it visible" probe.
  Finder orbIcon() => find.byIcon(Icons.support_agent_rounded);

  Future<void> pumpOrb(WidgetTester tester) async {
    final authProvider = AuthProvider(
      authService: FakeAuthService(),
      teamService: FakeTeamService(),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<VoiceAgentProvider>(
            create: (_) => VoiceAgentProvider(authProvider),
          ),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          home: const Scaffold(body: Stack(children: [FloatingAiOrb()])),
        ),
      ),
    );
    // Not `pumpAndSettle()`: the orb's breathe/orbit controllers `repeat()`
    // forever by design, so it would never return.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('tapping the orb opens the panel and hides the orb', (
    tester,
  ) async {
    await pumpOrb(tester);
    expect(floatingAiOrbVisible.value, isTrue);
    expect(orbIcon(), findsOneWidget);

    await tester.tap(orbIcon());
    await tester.pump(const Duration(milliseconds: 300));

    expect(floatingAiOrbVisible.value, isFalse);
    expect(find.byType(VoiceAgentPanel), findsOneWidget);
    expect(orbIcon(), findsNothing);
  });

  testWidgets(
    'a repeated tap while the panel is open cannot stack a second one — '
    'the orb icon is gone, so there is nothing left to tap',
    (tester) async {
      await pumpOrb(tester);

      await tester.tap(orbIcon());
      // Not `pumpAndSettle()`: the orb's breathe/orbit controllers `repeat()`
      // forever by design, so it would never return.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VoiceAgentPanel), findsOneWidget);

      // What the bug actually was: tapping the (still visible) orb again
      // opened a second panel. With the orb hidden, there is no icon left
      // to receive that second tap in the first place.
      expect(orbIcon(), findsNothing);
    },
  );

  testWidgets('dismissing the panel restores the orb', (tester) async {
    await pumpOrb(tester);

    await tester.tap(orbIcon());
    await tester.pump(const Duration(milliseconds: 300));
    expect(floatingAiOrbVisible.value, isFalse);

    Navigator.of(tester.element(find.byType(VoiceAgentPanel))).pop();
    await tester.pump(const Duration(milliseconds: 300));

    expect(floatingAiOrbVisible.value, isTrue);
    expect(orbIcon(), findsOneWidget);
    expect(find.byType(VoiceAgentPanel), findsNothing);
  });
}
