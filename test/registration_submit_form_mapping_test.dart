// Guards the single highest-risk defect in the Phase 2 registration-submit
// migration: a typo'd or missing key in the `form` map each screen sends to
// its backend endpoint. The backend's own `REQUIRED_FIELDS` arrays (read
// directly from builder/broker/influencer-registration-submit/index.ts) are
// reproduced here as plain constants, and each screen's extracted
// `buildSubmitFormForTest()` (added for exactly this purpose) is asserted to
// contain every one of them, by name.
//
// This does NOT exercise field VALUES (that needs the full wizard filled in
// via its UI, a much larger undertaking for three ~2000-line screens with no
// prior test coverage) — only that the key set the backend's validator reads
// from is exactly the key set these screens actually send.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/identity_verification_provider.dart';
import 'package:propcid_app/screens/profile_completion/broker_registration/broker_registration_screen.dart';
import 'package:propcid_app/screens/profile_completion/builder_registration/builder_registration_screen.dart';
import 'package:propcid_app/screens/profile_completion/influencer_registration/influencer_registration_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_identity_verification.dart';
import 'support/fake_supabase_session.dart';

// From backend/functions/builder-registration-submit/index.ts REQUIRED_FIELDS.
const _builderRequired = [
  'fullName',
  'email',
  'mobileNumber',
  'gender',
  'dob',
  'username',
  'companyName',
  'companyType',
  'gstNumber',
  'panNumber',
  'yearsOfExperience',
  'areasOfExpertise',
  'languagesKnown',
  'aboutCompany',
  'officeAddress',
  'city',
  'state',
  'pincode',
  'gstCertificateUrl',
  'panCardUrl',
  'aadhaarCardUrl',
  'aadhaarCardBackUrl',
  'registrationProofUrl',
];

// From backend/functions/broker-registration-submit/index.ts REQUIRED_FIELDS.
const _brokerRequired = [
  'fullName',
  'email',
  'mobileNumber',
  'gender',
  'dob',
  'username',
  'yearsOfExperience',
  'areasOfExpertise',
  'languagesKnown',
  'aboutBroker',
  'officeAddress',
  'city',
  'state',
  'pincode',
  'aadhaarCardUrl',
  'aadhaarCardBackUrl',
  'panCardUrl',
];

// From backend/functions/influencer-registration-submit/index.ts REQUIRED_FIELDS.
const _influencerRequired = [
  'fullName',
  'email',
  'mobileNumber',
  'gender',
  'dob',
  'username',
  'category',
  'primaryContentPlatform',
  'yearsOfExperience',
  'audienceType',
  'bio',
  'languagesKnown',
  'officeAddress',
  'city',
  'state',
  'pincode',
  'instagramUsername',
  'instagramFollowers',
  'youtubeChannelLink',
  'youtubeSubscribers',
  'facebookPageLink',
  'whatsappNumber',
  'contentTypes',
  'preferredPromotionTypes',
  'aadhaarCardUrl',
  'aadhaarCardBackUrl',
  'panCardUrl',
];

const _userId = 'user-aaaa';

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

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<IdentityVerificationProvider>(
      create: (_) => IdentityVerificationProvider(
        service: FakeIdentityVerificationService(),
        sessionGuard: FakeIdentitySessionGuard(_userId),
      )..syncUser(_userId),
      child: MaterialApp(home: child),
    );
  }

  testWidgets(
    "Builder's submitted form contains every field builder-registration-submit requires",
    (tester) async {
      await tester.pumpWidget(wrap(const BuilderRegistrationScreen()));
      await tester.pumpAndSettle();

      final state =
          tester.state(find.byType(BuilderRegistrationScreen)) as dynamic;
      final form = state.buildSubmitFormForTest('Test Person') as Map;

      for (final field in _builderRequired) {
        expect(
          form.containsKey(field),
          isTrue,
          reason: 'builder-registration-submit requires "$field" but the Flutter form map omits it',
        );
      }
    },
  );

  testWidgets(
    "Broker's submitted form contains every field broker-registration-submit requires",
    (tester) async {
      await tester.pumpWidget(wrap(const BrokerRegistrationScreen()));
      await tester.pumpAndSettle();

      final state =
          tester.state(find.byType(BrokerRegistrationScreen)) as dynamic;
      final form = state.buildSubmitFormForTest() as Map;

      for (final field in _brokerRequired) {
        expect(
          form.containsKey(field),
          isTrue,
          reason: 'broker-registration-submit requires "$field" but the Flutter form map omits it',
        );
      }
    },
  );

  testWidgets(
    "Influencer's submitted form contains every field influencer-registration-submit requires",
    (tester) async {
      await tester.pumpWidget(wrap(const InfluencerRegistrationScreen()));
      await tester.pumpAndSettle();

      final state =
          tester.state(find.byType(InfluencerRegistrationScreen)) as dynamic;
      final form = state.buildSubmitFormForTest() as Map;

      for (final field in _influencerRequired) {
        expect(
          form.containsKey(field),
          isTrue,
          reason: 'influencer-registration-submit requires "$field" but the Flutter form map omits it',
        );
      }
    },
  );
}
