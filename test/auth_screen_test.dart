// Focused, interaction-level verification for AuthScreen — covers real
// keyboard/focus behavior, not just "no overflow".
//
// Deliberately does NOT tap Sign In / Google / Send OTP — those invoke the
// real (frozen) handlers against `AuthProvider`, and the shared
// `FakeAuthService` throws `UnimplementedError` for those specific network
// calls (never faked just to make a presentation test pass). Sign Up *is*
// exercised end-to-end below: `FakeAuthService.signUpWithEmail` is a real,
// safe fake (no `UnimplementedError`), so the confirmation/resend state can
// be verified against an actual tap rather than by only inspecting layout.
// See the redesign report's "Live authentication checks" section for what
// this suite does and does not cover.
//
// Portal parity update: the screen now has two top-level tabs, Mobile and
// Email (Mobile selected by default, matching SignIn.tsx's
// `defaultValue="phone"`), with Sign Up living as a mode switch *inside* the
// Email tab rather than its own tab. Tests that exercise the Sign In form
// must explicitly switch to the Email tab first — it is no longer the
// screen's default content.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/auth/auth_screen.dart';
import 'package:propcid_app/voice_agent/floating_ai_orb_visibility.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/overflow_detector.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // `floatingAiOrbVisible` is process-wide; leaving it flipped after a test
  // that never disposes `AuthScreen` (most of these don't reach the very
  // end of the widget tree's life) would bleed into the next test.
  tearDown(() => floatingAiOrbVisible.value = true);

  Future<FakeAuthService> pumpAuthScreen(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // NOT a manually-constructed `MediaQuery` wrapper: that would freeze
    // `viewInsets` at whatever it was on first pump, so a later
    // `setKeyboardInset` call would never actually reach `AuthScreen`'s
    // `MediaQuery.of(context)`. `textScaleFactorTestValue` composes
    // correctly with the ambient, view-derived `MediaQuery` that Flutter
    // already recomputes on every frame from `tester.view`.
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final authService = FakeAuthService();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(
          authService: authService,
          teamService: FakeTeamService(),
        ),
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    // Settles the entrance FadeTransition/AnimationController.
    await tester.pumpAndSettle();
    return authService;
  }

  /// Switches from the default Mobile tab to the Email tab (Sign In mode,
  /// its own default). Every test that needs the email/password form calls
  /// this first.
  Future<void> goToEmailTab(WidgetTester tester) async {
    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
  }

  /// From the Email tab's Sign In mode, switches to its Sign Up mode via the
  /// in-form "Sign up" link.
  Future<void> switchToSignUpMode(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
  }

  /// Simulates the software keyboard opening/closing — the same
  /// `FakeViewPadding` mechanism used elsewhere in this app's test suite
  /// (e.g. `listing_dimensions_portal_parity_test.dart`).
  void setKeyboardInset(WidgetTester tester, double inset) {
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
  }

  group('Mobile tab is the default (portal parity)', () {
    testWidgets('the Mobile tab is shown first, not Sign In', (tester) async {
      await pumpAuthScreen(tester);

      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('there are exactly two top-level tab segments', (tester) async {
      await pumpAuthScreen(tester);

      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Sign Up'), findsNothing);
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets('the phone form no longer collects a name', (tester) async {
      await pumpAuthScreen(tester);

      expect(find.text('Name (new accounts only)'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Enter your full name'),
        findsNothing,
      );
    });
  });

  group('label/hint fix', () {
    testWidgets(
      'Sign In shows a persistent label above each field, and a distinct hint inside it',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);

        expect(find.text('Welcome back'), findsOneWidget);
        expect(
          find.text('Sign in to continue your property journey.'),
          findsOneWidget,
        );

        expect(find.text('Email or username'), findsOneWidget);
        expect(find.text('Password'), findsOneWidget);

        final emailField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(emailField.decoration?.hintText, 'Enter your email or username');

        final passwordField = tester.widget<TextField>(
          find.byType(TextField).at(1),
        );
        expect(passwordField.decoration?.hintText, 'Enter your password');
        expect(emailField.decoration?.hintText, isNot('Email or username'));
      },
    );
  });

  group('the real logo asset', () {
    testWidgets('renders as an Image.asset with an accessible label', (
      tester,
    ) async {
      await pumpAuthScreen(tester);

      // The hero's background accent is a CachedNetworkImage (a network
      // provider, not an AssetImage) rendered via its own internal `Image`,
      // so this must find the logo among possibly-mixed providers rather
      // than assert every `Image` in the tree is an asset image.
      final images = tester.widgetList<Image>(find.byType(Image));
      final assetImages = images.whereType<Image>().where(
        (image) => image.image is AssetImage,
      );
      expect(
        assetImages,
        isNotEmpty,
        reason: 'expected at least one Image.asset',
      );
      for (final image in assetImages) {
        expect((image.image as AssetImage).assetName, contains('propcid'));
      }

      expect(find.bySemanticsLabel('PropCid'), findsWidgets);
    });
  });

  group('focus traversal (email -> password)', () {
    testWidgets(
      'typing in email, pressing next, and typing in password all work, and both values persist',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);

        final emailFinder = find.byType(TextField).first;
        final passwordFinder = find.byType(TextField).at(1);

        await tester.tap(emailFinder);
        await tester.pump();
        await tester.enterText(emailFinder, 'user@example.com');
        await tester.pump();

        // The keyboard's "Next" action — not a manual tap on the password
        // field — is what should move focus here.
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        // `Focus.of(context)` looks for an ANCESTOR Focus widget; a
        // TextField's own element sits above the internal Focus its
        // EditableText builds, so that lookup throws "no Focus ancestor"
        // here. The FocusNode wired to the field is the right thing to
        // check instead.
        expect(
          tester.widget<TextField>(passwordFinder).focusNode!.hasFocus,
          isTrue,
          reason: '"Next" on email should focus the password field',
        );

        await tester.enterText(passwordFinder, 'secret123');
        await tester.pump();

        expect(find.text('user@example.com'), findsOneWidget);
        expect(
          tester.widget<TextField>(passwordFinder).controller!.text,
          'secret123',
        );
      },
    );

    testWidgets(
      'Password keeps the default action — it must never itself submit the form',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);
        final passwordField = tester.widget<TextField>(
          find.byType(TextField).at(1),
        );
        expect(passwordField.textInputAction, TextInputAction.done);
      },
    );
  });

  group('keyboard-open behavior', () {
    testWidgets(
      'the hero collapses to the compact logo bar once the keyboard opens',
      (tester) async {
        await pumpAuthScreen(tester);
        expect(find.text('Your next home'), findsOneWidget);

        setKeyboardInset(tester, 300);
        await tester.pumpAndSettle();

        expect(find.text('Your next home'), findsNothing);
        expect(find.text('Discover. Explore. Own.'), findsNothing);
        // The logo itself is retained in the compact bar.
        expect(find.bySemanticsLabel('PropCid'), findsWidgets);

        setKeyboardInset(tester, 0);
        await tester.pumpAndSettle();
        expect(find.text('Your next home'), findsOneWidget);
      },
    );

    testWidgets(
      'the focused field stays within the visible viewport once the keyboard opens',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);
        addTearDown(() => tester.view.resetViewInsets());

        final passwordFinder = find.byType(TextField).at(1);
        await tester.tap(passwordFinder);
        await tester.pump();

        setKeyboardInset(tester, 300);
        await tester.pumpAndSettle();

        final fieldBottom = tester.getBottomLeft(passwordFinder).dy;
        const visibleBottom = 844 - 300; // keyboard covers the bottom 300px
        expect(
          fieldBottom,
          lessThanOrEqualTo(visibleBottom.toDouble()),
          reason: 'the focused field must not sit under the keyboard',
        );
      },
    );

    testWidgets(
      'keyboard open/close and tab switching both preserve entered text',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);
        addTearDown(() => tester.view.resetViewInsets());

        await tester.enterText(
          find.byType(TextField).first,
          'stays@example.com',
        );
        await tester.pump();

        setKeyboardInset(tester, 300);
        await tester.pumpAndSettle();
        setKeyboardInset(tester, 0);
        await tester.pumpAndSettle();
        expect(find.text('stays@example.com'), findsOneWidget);

        await tester.tap(find.text('Mobile'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email'));
        await tester.pumpAndSettle();
        expect(find.text('stays@example.com'), findsOneWidget);
      },
    );
  });

  group('assistant overlap', () {
    testWidgets(
      'the floating orb is told to hide while AuthScreen is mounted, and restored on dispose',
      (tester) async {
        expect(floatingAiOrbVisible.value, isTrue);
        await pumpAuthScreen(tester);
        expect(floatingAiOrbVisible.value, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(floatingAiOrbVisible.value, isTrue);
      },
    );

    testWidgets('the inline "Need help?" action is present as a fallback', (
      tester,
    ) async {
      await pumpAuthScreen(tester);
      expect(find.text('Need help?'), findsOneWidget);
    });
  });

  group('tab and mode switching preserves all three forms', () {
    testWidgets('the Email tab defaults to the Sign In form', (tester) async {
      await pumpAuthScreen(tester);
      await goToEmailTab(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('the in-form Sign up link shows the email-only form', (
      tester,
    ) async {
      await pumpAuthScreen(tester);
      await goToEmailTab(tester);
      await switchToSignUpMode(tester);

      // 'Email' also still matches the top tab segment label, so this
      // checks the Sign Up form's own field hint instead of the field
      // label, which would be ambiguous.
      expect(find.text('you@example.com'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('the Mobile tab shows the phone form', (tester) async {
      await pumpAuthScreen(tester);

      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
    });

    testWidgets(
      'the Mobile tab also offers Continue with Google, same as Email',
      (tester) async {
        await pumpAuthScreen(tester);

        await tester.ensureVisible(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(find.text('Continue with Google'), findsOneWidget);
      },
    );

    testWidgets(
      'signing up with a valid email reaches the confirmation/resend state, and resend re-invokes the same call',
      (tester) async {
        final authService = await pumpAuthScreen(tester);
        await goToEmailTab(tester);
        await switchToSignUpMode(tester);

        await tester.enterText(
          find.byType(TextField).first,
          'newuser@example.com',
        );
        await tester.ensureVisible(find.text('Create Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();

        expect(find.text('Check your email'), findsOneWidget);
        expect(find.textContaining('newuser@example.com'), findsOneWidget);
        expect(authService.signUpWithEmailCalls, ['newuser@example.com']);

        await tester.tap(find.text('Resend email'));
        await tester.pumpAndSettle();
        expect(authService.signUpWithEmailCalls, [
          'newuser@example.com',
          'newuser@example.com',
        ]);
      },
    );

    testWidgets(
      '"New to PropCid? Sign up" switches to Sign Up mode without navigating or changing tabs',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);

        expect(find.text('Welcome back'), findsOneWidget);

        await switchToSignUpMode(tester);

        expect(find.text('Create Account'), findsOneWidget);
        expect(find.byType(AuthScreen), findsOneWidget);
      },
    );

    testWidgets('"Already have an account? Sign in" returns to Sign In mode', (
      tester,
    ) async {
      await pumpAuthScreen(tester);
      await goToEmailTab(tester);
      await switchToSignUpMode(tester);
      expect(find.text('Create Account'), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('hero-to-form gap', () {
    testWidgets(
      'the gap between the tagline and the form card is roughly 20-24px',
      (tester) async {
        await pumpAuthScreen(tester, width: 390);

        final taglineBottom = tester
            .getBottomLeft(find.text('Discover. Explore. Own.'))
            .dy;
        final cardTop = tester
            .getTopLeft(find.byKey(const Key('authFormCard')))
            .dy;

        expect(cardTop - taglineBottom, inInclusiveRange(18.0, 26.0));
      },
    );
  });

  group('footer is centered', () {
    testWidgets(
      '"New to PropCid? Sign up" is horizontally centered on screen, not flush left',
      (tester) async {
        await pumpAuthScreen(tester, width: 390);
        await goToEmailTab(tester);

        final screenCenterX = 390 / 2;
        // The row is two adjacent Text widgets ("New to PropCid? " then
        // "Sign up") inside one Wrap — its combined bounding box is what
        // must straddle the screen's centerline. A regression back to a
        // bare (uncentered) `Wrap` would leave this flush against the
        // left 24px inset instead.
        final leftText = tester.getTopLeft(find.text('New to PropCid? '));
        final rightText = tester.getTopRight(find.text('Sign up'));
        final rowCenterX = (leftText.dx + rightText.dx) / 2;

        expect((rowCenterX - screenCenterX).abs(), lessThan(4));
      },
    );

    testWidgets('"Need help?" stays horizontally centered on screen', (
      tester,
    ) async {
      await pumpAuthScreen(tester, width: 390);

      final screenCenterX = 390 / 2;
      // The centered unit is the icon+text *row*, not the text alone — the
      // leading icon (16px) plus its 6px gap sit to the text's left, so
      // the text widget's own center sits right of true center by design.
      final helpRow = find.ancestor(
        of: find.text('Need help?'),
        matching: find.byType(Row),
      );
      final helpRect = tester.getRect(helpRow);

      expect((helpRect.center.dx - screenCenterX).abs(), lessThan(4));
    });
  });

  group('no overflow at the required widths', () {
    for (final width in [320.0, 390.0, 430.0]) {
      testWidgets('Mobile (default) at ${width}px', (tester) async {
        await pumpAuthScreen(tester, width: width);
        expect(overflowingBoxes(tester), isEmpty);
      });

      testWidgets('Sign In at ${width}px', (tester) async {
        await pumpAuthScreen(tester, width: width);
        await goToEmailTab(tester);
        expect(overflowingBoxes(tester), isEmpty);
      });
    }

    testWidgets('Sign Up at 320px', (tester) async {
      await pumpAuthScreen(tester, width: 320);
      await goToEmailTab(tester);
      await switchToSignUpMode(tester);
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('short viewport / keyboard-open / enlarged text', () {
    testWidgets('a short viewport does not overflow', (tester) async {
      await pumpAuthScreen(tester, width: 390, height: 560);
      await goToEmailTab(tester);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('a large bottom inset (simulated keyboard) does not overflow', (
      tester,
    ) async {
      await pumpAuthScreen(tester);
      await goToEmailTab(tester);
      addTearDown(() => tester.view.resetViewInsets());

      setKeyboardInset(tester, 300);
      await tester.pumpAndSettle();

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('enlarged text scaling does not overflow', (tester) async {
      await pumpAuthScreen(tester, width: 390, textScale: 1.3);
      await goToEmailTab(tester);
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('primary controls are reachable without excessive scrolling', () {
    testWidgets(
      'Sign In and the Google button can both be scrolled into view on a typical phone',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);

        await tester.ensureVisible(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Sign In'), findsWidgets);
      },
    );
  });

  group('preserved state and controllers', () {
    testWidgets(
      'entered text survives switching away from and back to the Email tab',
      (tester) async {
        await pumpAuthScreen(tester);
        await goToEmailTab(tester);

        await tester.enterText(
          find.byType(TextField).first,
          'someone@example.com',
        );
        await tester.tap(find.text('Mobile'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email'));
        await tester.pumpAndSettle();

        expect(find.text('someone@example.com'), findsOneWidget);
      },
    );

    testWidgets('password visibility toggle still flips obscureText', (
      tester,
    ) async {
      await pumpAuthScreen(tester);
      await goToEmailTab(tester);

      TextField passwordField() =>
          tester.widget<TextField>(find.byType(TextField).at(1));

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      expect(passwordField().obscureText, isFalse);
    });
  });
}
