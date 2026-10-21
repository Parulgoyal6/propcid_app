// Phase 3 — Edit Profile write-path parity.
//
// The highest-consequence bug available in this migration is a non-merging
// `social_media` write: the column holds ~35 keys written by four different flows,
// and replacing it destroys everything this screen does not model. Second is a
// half-written column pair, which makes the two platforms disagree about the same
// profile. Third is sending a trigger-guarded column, which produces a save that
// reports success and changes nothing.
//
// All three are asserted here, plus the legacy-preservation contract from approved
// decision 5.1.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/profile_options.dart';
import 'package:propcid_app/core/validation/profile_validators.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/edit_profile_provider.dart';
import 'package:propcid_app/services/profile_write_service.dart';
import 'package:propcid_app/services/user_profile_service.dart';

class _FakeProfileService extends UserProfileService {
  _FakeProfileService(this.profile);
  final UserProfile? profile;

  @override
  Future<UserProfile?> fetchOwn(String userId) async => profile;
}

/// Captures the payload instead of writing it.
class _CapturingWriteService extends ProfileWriteService {
  Map<String, dynamic>? columns;
  Map<String, dynamic>? socialExisting;
  Map<String, dynamic>? socialChanges;
  int citySyncs = 0;

  @override
  Future<void> saveProfile({
    required String userId,
    required Map<String, dynamic> columns,
    required Map<String, dynamic> socialMediaExisting,
    required Map<String, dynamic> socialMediaChanges,
  }) async {
    this.columns = columns;
    socialExisting = socialMediaExisting;
    socialChanges = socialMediaChanges;
  }

  @override
  Future<void> syncCityPreference({
    required String userId,
    required String city,
  }) async {
    citySyncs++;
  }

  /// The merged map the real service would have sent.
  Map<String, dynamic> get mergedSocial => ProfileWriteService.mergeSocialMedia(
        socialExisting ?? const {},
        socialChanges ?? const {},
      );
}

UserProfile _row(String role, {Map<String, dynamic> social = const {}}) =>
    UserProfile.fromMap(<String, dynamic>{
      'user_id': 'u-1',
      'display_name': 'Asha Menon',
      'user_type': role,
      'phone': '+919876543210',
      'social_media': social,
    });

Future<({EditProfileProvider provider, _CapturingWriteService writer})> _load(
  String role, {
  Map<String, dynamic> social = const {},
  Map<String, dynamic> extraRow = const {},
}) async {
  final row = extraRow.isEmpty
      ? _row(role, social: social)
      : UserProfile.fromMap(<String, dynamic>{
          'user_id': 'u-1',
          'display_name': 'Asha Menon',
          'user_type': role,
          'social_media': social,
          ...extraRow,
        });

  final writer = _CapturingWriteService();
  final provider = EditProfileProvider(
    profileService: _FakeProfileService(row),
    writeService: writer,
  );
  await provider.load('u-1');
  // Brokers can't save with fewer than 50 words in About, so give every
  // broker fixture a valid one unless the row already carries a bio.
  if (role == 'broker' && provider.bio.text.trim().isEmpty) {
    provider.bio.text = _kFiftyWordBio;
  }
  return (provider: provider, writer: writer);
}

/// Exactly EditProfileProvider.kMinAboutBrokerWords words.
final String _kFiftyWordBio = List.filled(
  EditProfileProvider.kMinAboutBrokerWords,
  'word',
).join(' ');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  group('social_media is merged, never replaced', () {
    test('keys this screen does not model survive a save', () async {
      final ctx = await _load('builder', social: {
        // Written by the portal or a wizard; no input on this screen.
        'rera_certificate_url': 'https://x/rera.pdf',
        'registration_proof_url': 'https://x/proof.pdf',
        'bank_details': {'gst_number': '11AAAAA1111A1Z1'},
        'some_future_key': 'keep me',
      });

      ctx.provider.fullName.text = 'Asha Menon';
      ctx.provider.phone.text = '9876543210';
      expect(await ctx.provider.save(), isNull);

      final merged = ctx.writer.mergedSocial;
      expect(merged['rera_certificate_url'], 'https://x/rera.pdf');
      expect(merged['registration_proof_url'], 'https://x/proof.pdf');
      expect(merged['bank_details'], isNotNull);
      expect(merged['some_future_key'], 'keep me');
    });

    test('mergeSocialMedia keeps existing keys and overwrites named ones', () {
      final merged = ProfileWriteService.mergeSocialMedia(
        {'a': 1, 'b': 2},
        {'b': 3, 'c': 4},
      );
      expect(merged, {'a': 1, 'b': 3, 'c': 4});
    });

    test('the existing map passed to the writer is the stored one', () async {
      final ctx = await _load('broker', social: {'kept': 'yes'});
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      await ctx.provider.save();
      expect(ctx.writer.socialExisting!['kept'], 'yes');
    });
  });

  group('trigger-guarded columns are never sent', () {
    test('the payload omits all four', () async {
      for (final role in ['builder', 'broker', 'influencer', 'individual']) {
        final ctx = await _load(role);
        ctx.provider.fullName.text = 'Asha';
        ctx.provider.phone.text = '9876543210';
        await ctx.provider.save();

        for (final column in kTriggerGuardedColumns) {
          expect(
            ctx.writer.columns!.containsKey(column),
            isFalse,
            reason: '$role payload must not contain $column',
          );
        }
      }
    });

    test('stripGuarded removes them even if a builder adds one', () {
      final stripped = ProfileWriteService.stripGuarded({
        'display_name': 'x',
        'user_type': 'builder',
        'approval_status': 'approved',
        'is_blocked': false,
        'user_role': 'admin',
      });
      expect(stripped.keys, ['display_name']);
    });
  });

  group('paired columns are written together', () {
    test('all five pairs carry the same value', () async {
      final ctx = await _load('broker');
      final p = ctx.provider;
      p.fullName.text = 'Asha';
      p.phone.text = '9876543210';
      p.reraNumber.text = 'MH123';
      p.website.text = 'example.com';
      p.bio.text = _kFiftyWordBio;
      p.city.text = 'Mumbai';
      p.yearsExperience.text = '7';

      await p.save();
      final c = ctx.writer.columns!;

      expect(c['rera_number'], c['license_number']);
      expect(c['website'], c['website_url']);
      expect(c['bio'], c['company_description']);
      expect(c['city'], c['work_city']);
      expect(c['years_of_experience'], c['years_experience']);
      expect(c['years_of_experience'], 7);
    });

    test('an individual writes only the basic columns', () async {
      final ctx = await _load('individual');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      await ctx.provider.save();

      final c = ctx.writer.columns!;
      expect(c.keys.toSet(), {'display_name', 'phone', 'username'});
      // EditProfile.tsx:426 gates the business block on the other three roles.
      expect(c.containsKey('company_name'), isFalse);
      expect(c.containsKey('city'), isFalse);
    });
  });

  group('legacy values are preserved (decision 5.1)', () {
    test('a wizard-written content type stays selected after load', () async {
      // 'Vlogs' and 'Podcasts' exist only in the Flutter wizard's vocabulary.
      final ctx = await _load('influencer', social: {
        'content_types': ['Vlogs', 'Reels', 'Podcasts'],
      });
      expect(ctx.provider.contentTypes, ['Vlogs', 'Reels', 'Podcasts']);
    });

    test('saving without touching them keeps every legacy value', () async {
      final ctx = await _load('influencer', social: {
        'content_types': ['Vlogs', 'Podcasts'],
        'preferred_promotion_types': ['Giveaways'],
      });
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      await ctx.provider.save();

      final merged = ctx.writer.mergedSocial;
      expect(merged['content_types'], ['Vlogs', 'Podcasts']);
      expect(merged['preferred_promotion_types'], ['Giveaways']);
    });

    test('a legacy value is removed only by an explicit toggle', () async {
      final ctx = await _load('influencer', social: {
        'content_types': ['Vlogs', 'Reels'],
      });
      ctx.provider.toggleChip(ProfileChipGroup.contentTypes, 'Vlogs');
      expect(ctx.provider.contentTypes, ['Reels']);
    });

    test('mergeSelection appends unknown values after the canonical ones', () {
      final chips = mergeSelection(kContentTypeOptions, ['Vlogs', 'Reels']);
      expect(chips.take(kContentTypeOptions.length), kContentTypeOptions);
      expect(chips.last, 'Vlogs');
      expect(chips.where((c) => c == 'Reels').length, 1,
          reason: 'a value already canonical must not be duplicated');
    });

    test('isLegacyValue distinguishes the two vocabularies', () {
      expect(isLegacyValue(kContentTypeOptions, 'Vlogs'), isTrue);
      expect(isLegacyValue(kContentTypeOptions, 'Reels'), isFalse);
    });

    test('a legacy single-select value stays selected', () async {
      // 'Proprietorship' is wizard-only; the React list has four other values.
      final ctx = await _load('builder', social: {
        'company_type': 'Proprietorship',
      });
      expect(ctx.provider.companyType, 'Proprietorship');
      expect(
        mergeSingle(kCompanyTypeOptions, 'Proprietorship'),
        containsAll(<String>[...kCompanyTypeOptions, 'Proprietorship']),
      );
    });
  });

  group('addCustomChip (custom language entry)', () {
    test('adds a value outside the canonical list', () async {
      final ctx = await _load('influencer');
      ctx.provider.addCustomChip(ProfileChipGroup.languagesKnown, 'Bhojpuri');
      expect(ctx.provider.languagesKnown, ['Bhojpuri']);
      expect(isLegacyValue(kLanguageOptions, 'Bhojpuri'), isTrue);
    });

    test('trims whitespace', () async {
      final ctx = await _load('influencer');
      ctx.provider.addCustomChip(ProfileChipGroup.languagesKnown, '  Tulu  ');
      expect(ctx.provider.languagesKnown, ['Tulu']);
    });

    test('a blank value is a no-op', () async {
      final ctx = await _load('influencer');
      ctx.provider.addCustomChip(ProfileChipGroup.languagesKnown, '   ');
      expect(ctx.provider.languagesKnown, isEmpty);
    });

    test('an already-selected value is a no-op, never a removal', () async {
      final ctx = await _load('influencer', social: {
        'languages_known': ['Tulu'],
      });
      ctx.provider.addCustomChip(ProfileChipGroup.languagesKnown, 'Tulu');
      expect(ctx.provider.languagesKnown, ['Tulu']);
    });

    test('a custom language persists on save, like any other selection', () async {
      final ctx = await _load('influencer');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      ctx.provider.addCustomChip(ProfileChipGroup.languagesKnown, 'Bhojpuri');
      await ctx.provider.save();
      expect(ctx.writer.mergedSocial['languages_known'], ['Bhojpuri']);
    });
  });

  group('decision 5.2 — newly editable fields', () {
    test('broker property_types is written as a column', () async {
      final ctx = await _load('broker', extraRow: {
        'property_types': ['Residential'],
      });
      expect(ctx.provider.propertyTypes, ['Residential']);

      ctx.provider.toggleChip(ProfileChipGroup.propertyTypes, 'Commercial');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      await ctx.provider.save();

      expect(ctx.writer.columns!['property_types'], ['Residential', 'Commercial']);
    });

    test('property_types is not written for other roles', () async {
      for (final role in ['builder', 'influencer', 'individual']) {
        final ctx = await _load(role);
        ctx.provider.fullName.text = 'Asha';
        ctx.provider.phone.text = '9876543210';
        await ctx.provider.save();
        expect(ctx.writer.columns!.containsKey('property_types'), isFalse,
            reason: role);
      }
    });

    test('portfolio links round-trip as an array, one per line', () async {
      final ctx = await _load('influencer', social: {
        'portfolio_links': ['https://a.com', 'https://b.com'],
      });
      expect(ctx.provider.portfolioLinks.text, 'https://a.com\nhttps://b.com');

      ctx.provider.portfolioLinks.text = 'https://a.com\n\nhttps://c.com\n';
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      await ctx.provider.save();

      expect(ctx.writer.mergedSocial['portfolio_links'],
          ['https://a.com', 'https://c.com']);
    });

    test('previous collaborations round-trip the same way', () async {
      final ctx = await _load('influencer', social: {
        'previous_brand_collaborations': ['Brand A'],
      });
      expect(ctx.provider.previousCollaborations.text, 'Brand A');
    });

    test(
      'landmark is written on save for influencer, not silently dropped',
      () async {
        final ctx = await _load('influencer');
        ctx.provider.fullName.text = 'Asha';
        ctx.provider.phone.text = '9876543210';
        ctx.provider.landmark.text = 'Near City Mall';
        await ctx.provider.save();

        expect(ctx.writer.mergedSocial['landmark'], 'Near City Mall');
      },
    );
  });

  group('role-specific social_media keys', () {
    test('broker writes alt_mobile_number, builder writes alternate_mobile',
        () async {
      final broker = await _load('broker');
      broker.provider.fullName.text = 'A';
      broker.provider.phone.text = '9876543210';
      broker.provider.alternateMobile.text = '9998887777';
      await broker.provider.save();
      expect(broker.writer.socialChanges!['alt_mobile_number'], '9998887777');
      expect(broker.writer.socialChanges!.containsKey('alternate_mobile'), isFalse);

      final builder = await _load('builder');
      builder.provider.fullName.text = 'A';
      builder.provider.phone.text = '9876543210';
      builder.provider.alternateMobile.text = '9998887777';
      await builder.provider.save();
      expect(builder.writer.socialChanges!['alternate_mobile'], '9998887777');
      expect(
          builder.writer.socialChanges!.containsKey('alt_mobile_number'), isFalse);
    });

    test('gender and dob are written for every role', () async {
      for (final role in ['builder', 'broker', 'influencer', 'individual']) {
        final ctx = await _load(role);
        ctx.provider.fullName.text = 'A';
        ctx.provider.phone.text = '9876543210';
        ctx.provider.setGender('Female');
        await ctx.provider.save();
        expect(ctx.writer.socialChanges!['gender'], 'Female', reason: role);
        expect(ctx.writer.socialChanges!.containsKey('dob'), isTrue, reason: role);
      }
    });
  });

  group('phone assembly', () {
    test('the stored country code is split out on load', () async {
      final ctx = await _load('broker');
      expect(ctx.provider.countryCode, '+91');
      expect(ctx.provider.phone.text, '9876543210');
    });

    test('code and number are recombined on save', () async {
      final ctx = await _load('broker');
      ctx.provider.fullName.text = 'A';
      ctx.provider.countryCode = '+44';
      ctx.provider.phone.text = '7700 900123';
      await ctx.provider.save();
      // Non-digits stripped, code prefixed — EditProfile.tsx:420.
      expect(ctx.writer.columns!['phone'], '+447700900123');
    });

    test('an unrecognised stored prefix is left in the local field', () async {
      final row = UserProfile.fromMap({
        'user_id': 'u-1',
        'user_type': 'broker',
        'phone': '+3512345678901',
      });
      final provider = EditProfileProvider(
        profileService: _FakeProfileService(row),
        writeService: _CapturingWriteService(),
      );
      await provider.load('u-1');
      expect(provider.countryCode, '+91');
      expect(provider.phone.text, '+3512345678901');
    });
  });

  group('city preference mirror', () {
    test('runs for builder and broker only', () async {
      for (final entry in {
        'builder': 1,
        'broker': 1,
        'influencer': 0,
        'individual': 0,
      }.entries) {
        final ctx = await _load(entry.key);
        ctx.provider.fullName.text = 'A';
        ctx.provider.phone.text = '9876543210';
        ctx.provider.city.text = 'Mumbai';
        await ctx.provider.save();
        expect(ctx.writer.citySyncs, entry.value, reason: entry.key);
      }
    });
  });

  group('validation thresholds', () {
    test('phone requires at least 10 digits, not exactly 10', () {
      expect(ProfileValidators.phoneAtLeast10('98765'), isNotNull);
      expect(ProfileValidators.phoneAtLeast10('9876543210'), isNull);
      expect(ProfileValidators.phoneAtLeast10('98765432101'), isNull);
      expect(ProfileValidators.phoneAtLeast10('98765 43210'), isNull);
      expect(ProfileValidators.phoneAtLeast10(''), isNotNull);
    });

    test('GST is exactly 15 characters, blank passes', () {
      expect(ProfileValidators.gstNumber(''), isNull);
      expect(ProfileValidators.gstNumber('123'), isNotNull);
      expect(ProfileValidators.gstNumber('11AAAAA1111A1Z1'), isNull);
    });

    test('PAN is exactly 10, blank passes, and "uploaded" is allowed', () {
      expect(ProfileValidators.panNumber(''), isNull);
      expect(ProfileValidators.panNumber('ABC'), isNotNull);
      expect(ProfileValidators.panNumber('ABCDE1234F'), isNull);
      // EditProfile.tsx:345 sentinel — a PAN document with no typed number.
      expect(ProfileValidators.panNumber('uploaded'), isNull);
    });

    test('alternate mobile allows blank but not a short number', () {
      expect(ProfileValidators.optionalMobile(''), isNull);
      expect(ProfileValidators.optionalMobile('12345'), isNotNull);
      expect(ProfileValidators.optionalMobile('9998887777'), isNull);
    });

    test('years allows 0 and rejects decimals', () {
      expect(ProfileValidators.optionalYears(''), isNull);
      expect(ProfileValidators.optionalYears('0'), isNull);
      expect(ProfileValidators.optionalYears('2.5'), isNotNull);
      expect(ProfileValidators.optionalYears('-1'), isNotNull);
    });

    test('website accepts a scheme-less host, as the portal does', () {
      expect(ProfileValidators.website('www.example.com'), isNull);
    });

    test('save refuses an invalid form and writes nothing', () async {
      final ctx = await _load('broker');
      ctx.provider.fullName.text = '';
      expect(await ctx.provider.save(), isNotNull);
      expect(ctx.writer.columns, isNull);
    });

    test('pincode must be 6 digits when present', () async {
      final ctx = await _load('broker');
      ctx.provider.fullName.text = 'A';
      ctx.provider.phone.text = '9876543210';
      ctx.provider.pincode.text = '123';
      expect(await ctx.provider.save(), contains('6 digits'));
    });

    test('broker About needs at least 50 words', () async {
      final ctx = await _load('broker');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      ctx.provider.bio.text = 'Too short to pass';
      expect(await ctx.provider.save(), contains('50 words'));
      expect(ctx.writer.columns, isNull);
    });

    test('DOB under 18 is refused', () async {
      final ctx = await _load('broker');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      final now = DateTime.now();
      ctx.provider.setDob('${now.year - 10}-01-01');
      expect(await ctx.provider.save(), contains('18 years'));
      expect(ctx.writer.columns, isNull);
    });

    test('DOB under 18 is refused for influencer specifically', () async {
      final ctx = await _load('influencer');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      final now = DateTime.now();
      ctx.provider.setDob('${now.year - 10}-01-01');
      expect(await ctx.provider.save(), contains('18 years'));
      expect(ctx.writer.columns, isNull);
    });

    test('a future DOB is refused, not silently accepted', () async {
      final ctx = await _load('influencer');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      final future = DateTime.now().add(const Duration(days: 365));
      ctx.provider.setDob(
        '${future.year}-${future.month.toString().padLeft(2, '0')}-'
        '${future.day.toString().padLeft(2, '0')}',
      );
      expect(await ctx.provider.save(), isNotNull);
      expect(ctx.writer.columns, isNull);
    });

    test('a DOB one day short of 18 is refused', () async {
      final ctx = await _load('influencer');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      final now = DateTime.now();
      // Turns 18 tomorrow, not today.
      final almost18 = DateTime(now.year - 18, now.month, now.day + 1);
      ctx.provider.setDob(
        '${almost18.year}-${almost18.month.toString().padLeft(2, '0')}-'
        '${almost18.day.toString().padLeft(2, '0')}',
      );
      expect(await ctx.provider.save(), contains('18 years'));
      expect(ctx.writer.columns, isNull);
    });

    test('a DOB of exactly 18 years ago today is accepted', () async {
      final ctx = await _load('influencer');
      ctx.provider.fullName.text = 'Asha';
      ctx.provider.phone.text = '9876543210';
      final now = DateTime.now();
      final exactly18 = DateTime(now.year - 18, now.month, now.day);
      ctx.provider.setDob(
        '${exactly18.year}-${exactly18.month.toString().padLeft(2, '0')}-'
        '${exactly18.day.toString().padLeft(2, '0')}',
      );
      expect(await ctx.provider.save(), isNull);
      expect(ctx.writer.socialChanges!['dob'], isNotNull);
    });
  });

  group('option sets match the React vocabulary', () {
    test('content types are the portal\'s eight', () {
      expect(kContentTypeOptions, [
        'Reels',
        'Shorts',
        'YouTube Videos',
        'Property Tours',
        'Reviews',
        'Stories',
        'Posts',
        'Live Sessions',
      ]);
    });

    test('promotion types are the portal\'s four', () {
      expect(kPromotionTypeOptions, [
        'Paid Promotion',
        'Affiliate Marketing',
        'Lead Generation',
        'Brand Collaboration',
      ]);
    });

    test('property types come from the broker wizard verbatim', () {
      expect(kPropertyTypeOptions, [
        'Residential',
        'Commercial',
        'Industrial',
        'Plots',
        'Agricultural',
        'Luxury',
      ]);
    });

    test('user types are the four the portal offers', () {
      expect(kUserTypeOptions, ['builder', 'broker', 'individual', 'influencer']);
    });
  });
}
