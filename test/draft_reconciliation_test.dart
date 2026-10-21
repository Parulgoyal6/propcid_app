// Verifies the Phase 1 "canonical verified identity wins over a restored
// draft" requirement for Builder, Broker and Influencer registration, under
// BOTH possible orderings of the two independent async loads each screen's
// initState kicks off (RegistrationDraftStore.load() and
// IdentityVerificationProvider.ensureLoaded()):
//
//   1. draft resolves first, canonical status arrives later
//   2. canonical status is already loaded, draft resolves later
//
// Order 2 is the one that exposed a real bug during this check: each
// screen's `_restoreDraft()` unconditionally overwrote the email/mobile/
// countryCode controllers from the draft, with nothing to re-apply
// reconciliation afterward if identity status had already loaded and
// already been applied earlier. Fixed by having `_restoreDraft()` call
// `_onIdentityStatusChanged()` again at its end, unconditionally — these
// tests pin that fix down.
//
// Uses `signInFakeUser` (test/support/fake_supabase_session.dart) so
// `Supabase.instance.client.auth.currentUser` and RegistrationDraftStore's
// per-user SharedPreferences key both work with no real backend, and
// `@visibleForTesting` debug getters on each screen's State (added
// specifically to make this checkable) to read the private controllers
// that drive the final-save payload without filling out the entire wizard
// to reach the review step.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/identity_status.dart';
import 'package:propcid_app/providers/identity_verification_provider.dart';
import 'package:propcid_app/screens/profile_completion/broker_registration/broker_registration_screen.dart';
import 'package:propcid_app/screens/profile_completion/builder_registration/builder_registration_screen.dart';
import 'package:propcid_app/screens/profile_completion/influencer_registration/influencer_registration_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_identity_verification.dart';
import 'support/fake_supabase_session.dart';

const _userId = 'user-aaaa';
const _staleEmail = 'stale@example.com';
const _staleMobile = '1111111111';
const _canonicalEmail = 'real@example.com';
const _canonicalPhone = '9876543210';

Future<void> _seedDraft(String draftKeyBase, Map<String, dynamic> formData) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    '${draftKeyBase}_$_userId',
    jsonEncode({
      'formData': formData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }),
  );
}

Widget _wrap(Widget child, IdentityVerificationProvider identityProvider) {
  return ChangeNotifierProvider<IdentityVerificationProvider>.value(
    value: identityProvider,
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await signInFakeUser(_userId, email: 'legacy@propcid.app');
  });

  tearDown(() async {
    await signOutFakeUser();
  });

  /// Table-driven across the three registration screens — identical
  /// `_restoreDraft`/`_onIdentityStatusChanged` wiring in each, per the
  /// Phase 1 audit, so one shared check covers all three.
  final screens =
      <String, ({String draftKeyBase, Type screenType, Widget Function() build})>{
        'Builder': (
          draftKeyBase: 'builder_registration_draft',
          screenType: BuilderRegistrationScreen,
          build: () => const BuilderRegistrationScreen(),
        ),
        'Broker': (
          draftKeyBase: 'broker_registration_draft',
          screenType: BrokerRegistrationScreen,
          build: () => const BrokerRegistrationScreen(),
        ),
        'Influencer': (
          draftKeyBase: 'influencer_registration_draft',
          screenType: InfluencerRegistrationScreen,
          build: () => const InfluencerRegistrationScreen(),
        ),
      };

  for (final entry in screens.entries) {
    final screenName = entry.key;
    final draftKeyBase = entry.value.draftKeyBase;
    final screenType = entry.value.screenType;
    final buildScreen = entry.value.build;

    group('$screenName — draft resolves before identity status', () {
      testWidgets(
        'the canonical value overrides the stale draft once status arrives',
        (tester) async {
          await _seedDraft(draftKeyBase, {
            'email': _staleEmail,
            'mobileNumber': _staleMobile,
            'countryCode': '+1',
          });

          final statusCompleter = Completer<IdentityStatus>();
          final fakeService = FakeIdentityVerificationService()
            ..statusFuture = statusCompleter.future;
          final provider = IdentityVerificationProvider(
            service: fakeService,
            sessionGuard: FakeIdentitySessionGuard(_userId),
          )..syncUser(_userId);

          await tester.pumpWidget(_wrap(buildScreen(), provider));
          // Lets the draft's SharedPreferences read resolve; identity
          // status is still pending (statusCompleter not yet completed).
          await tester.pump();
          await tester.pump();
          await tester.pump();

          dynamic state() => tester.state(find.byType(screenType));
          expect(
            state().debugEmailForTest,
            _staleEmail,
            reason: 'the draft should have applied before status resolves',
          );
          expect(state().debugMobileForTest, _staleMobile);

          statusCompleter.complete(
            const IdentityStatus(
              email: _canonicalEmail,
              emailVerified: true,
              phone: _canonicalPhone,
              phoneVerified: true,
            ),
          );
          await tester.pumpAndSettle();

          expect(state().debugEmailForTest, _canonicalEmail);
          expect(state().debugMobileForTest, _canonicalPhone);
          expect(state().debugCountryCodeForTest, '+91');
        },
      );
    });

    group('$screenName — identity status resolves before the draft', () {
      testWidgets(
        'the canonical value is not later clobbered by a slow draft restore',
        (tester) async {
          await _seedDraft(draftKeyBase, {
            'email': _staleEmail,
            'mobileNumber': _staleMobile,
            'countryCode': '+1',
          });

          final fakeService = FakeIdentityVerificationService()
            ..statusResult = const IdentityStatus(
              email: _canonicalEmail,
              emailVerified: true,
              phone: _canonicalPhone,
              phoneVerified: true,
            );
          final provider = IdentityVerificationProvider(
            service: fakeService,
            sessionGuard: FakeIdentitySessionGuard(_userId),
          )..syncUser(_userId);
          // Status is already loaded BEFORE the screen is even created —
          // the screen's own initState-time `ensureLoaded()` call will be a
          // no-op, and its synchronous `_onIdentityStatusChanged()` call
          // applies the canonical value immediately, before the async
          // draft restore has had any chance to run at all.
          await provider.ensureLoaded();

          await tester.pumpWidget(_wrap(buildScreen(), provider));
          // Lets the (slower, because it runs after status was already
          // applied) draft restore fully resolve too.
          await tester.pumpAndSettle();

          dynamic state() => tester.state(find.byType(screenType));
          expect(
            state().debugEmailForTest,
            _canonicalEmail,
            reason:
                'a draft that resolves after status was already applied must not overwrite it',
          );
          expect(state().debugMobileForTest, _canonicalPhone);
          expect(state().debugCountryCodeForTest, '+91');
        },
      );
    });
  }
}
