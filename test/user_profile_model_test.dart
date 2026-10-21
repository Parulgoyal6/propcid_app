// Phase 0 parity guard for the Public Profile read layer.
//
// Two things are asserted here, and they fail for different reasons:
//
// 1. THE COLUMN LISTS. A column-level GRANT is not a row filter — naming a
//    column that `anon` cannot read makes the whole query fail. The expected
//    strings below are typed independently, straight from
//    propcid/src/pages/UserProfile.tsx:331-332, exactly as
//    listing_constants_parity_test.dart transcribes the React arrays rather than
//    generating them. That independence is the point: a list derived from the
//    same source as the code under test would only prove the code agrees with
//    itself.
//
// 2. THE FALLBACK CHAINS. The portal's `||` chains are JS truthiness, where `''`
//    and `0` are falsy. Dart's `??` only tests null, so a naive port returns an
//    empty string where React returns the next candidate. Every chain is
//    exercised with a blank and a zero, not just with null.
//
// No Supabase initialisation is needed: the column lists are `static const` and
// the model is pure.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/services/user_profile_service.dart';

/// `publicCols` from pages/UserProfile.tsx:331, transcribed verbatim.
const String kPortalPublicCols =
    'user_id, display_name, username, avatar_url, user_type, company_name, '
    'agency_name, website_url, years_experience, specialization, '
    'business_hours, created_at, bio, work_city, city, license_number, '
    'rera_number, social_media, years_of_experience, office_address, state, '
    'pincode, website, company_description, verification_status, '
    'fb_followers_count, ig_followers_count, ig_follows_count, '
    'ig_media_count, social_followers_synced_at';

/// The only column Flutter adds to the portal's public list. See the
/// DOCUMENTED DEVIATION note on [UserProfileService.publicColumns].
const String kFlutterOnlyPublicCol = 'background_image_url';

/// A minimal anonymous-viewer row: the public columns only, with every contact
/// key absent from the map rather than null — which is what the narrowed grant
/// actually produces.
Map<String, dynamic> anonRow({
  String userId = 'u-1',
  String? displayName = 'Asha Menon',
}) =>
    <String, dynamic>{
      'user_id': userId,
      'display_name': displayName,
      'user_type': 'broker',
    };

void main() {
  group('column lists are the portal contract', () {
    test('publicColumns is the portal list plus background_image_url only', () {
      expect(
        UserProfileService.publicColumns,
        '$kPortalPublicCols, $kFlutterOnlyPublicCol',
      );
    });

    test('publicColumns never names a PII column', () {
      // The three columns REVOKEd from anon by 20270311000000. Naming any of
      // them here would break every logged-out profile view.
      for (final column in ['phone', 'email', 'mobile_number']) {
        expect(
          UserProfileService.publicColumns.split(RegExp(r',\s*')),
          isNot(contains(column)),
          reason: '$column is not granted to anon; requesting it fails the query',
        );
      }
    });

    test('authenticatedColumns is publicColumns plus exactly the three PII columns',
        () {
      expect(
        UserProfileService.authenticatedColumns,
        '${UserProfileService.publicColumns}, phone, email, mobile_number',
      );

      final public = UserProfileService.publicColumns.split(RegExp(r',\s*'));
      final authed =
          UserProfileService.authenticatedColumns.split(RegExp(r',\s*'));
      expect(authed.length, public.length + 3);
      expect(
        authed.toSet().difference(public.toSet()),
        {'phone', 'email', 'mobile_number'},
      );
    });

    test('no column appears twice in either list', () {
      for (final list in [
        UserProfileService.publicColumns,
        UserProfileService.authenticatedColumns,
      ]) {
        final parts = list.split(RegExp(r',\s*'));
        expect(parts.toSet().length, parts.length, reason: 'duplicate in: $list');
      }
    });

    test('lists use exactly ", " separators and have no empty entries', () {
      // Multi-line string concatenation makes a missing or doubled space easy to
      // introduce and invisible on review. `', '` is also what the split-based
      // assertions above rely on.
      for (final list in [
        UserProfileService.publicColumns,
        UserProfileService.authenticatedColumns,
        UserProfileService.summaryColumns,
      ]) {
        expect(list.trim(), list, reason: 'no leading/trailing whitespace');
        expect(list, isNot(contains('  ')), reason: 'no doubled spaces');
        expect(list, isNot(contains(',,')));

        final parts = list.split(', ');
        for (final part in parts) {
          expect(part, isNotEmpty);
          expect(part.trim(), part, reason: 'unexpected whitespace in "$part"');
          expect(part, isNot(contains(',')));
        }
        // Reassembling with ', ' must reproduce the original exactly.
        expect(parts.join(', '), list);
      }
    });

    test('the follower columns ARE requested for anonymous viewers', () {
      // 20270312000000_social_follower_counts.sql:76-79 grants these to anon
      // "so logged-out visitors see them too". An earlier revision of the plan
      // wrongly believed they were withheld and gated the section behind auth.
      for (final column in [
        'fb_followers_count',
        'ig_followers_count',
        'ig_follows_count',
        'ig_media_count',
        'social_followers_synced_at',
      ]) {
        expect(
          UserProfileService.publicColumns.split(RegExp(r',\s*')),
          contains(column),
        );
      }
    });
  });

  group('tolerant parsing', () {
    test('an anonymous-shaped row parses with contact fields null', () {
      final profile = UserProfile.fromMap(anonRow());

      expect(profile.userId, 'u-1');
      expect(profile.displayName, 'Asha Menon');
      expect(profile.phone, isNull);
      expect(profile.email, isNull);
      expect(profile.mobileNumber, isNull);
      expect(profile.effectivePhone, isNull);
      expect(profile.hasContactDetails, isFalse);
    });

    test('an empty map does not throw', () {
      final profile = UserProfile.fromMap(<String, dynamic>{});
      expect(profile.userId, '');
      expect(profile.displayTitle, isNull);
      expect(profile.socialMedia.isEmpty, isTrue);
      expect(profile.specialization, isEmpty);
      expect(profile.initials, 'U');
    });

    test('userId falls back from user_id to id, per the portal normalisation', () {
      expect(UserProfile.fromMap({'id': 'abc'}).userId, 'abc');
      expect(
        UserProfile.fromMap({'user_id': 'real', 'id': 'other'}).userId,
        'real',
      );
    });

    test('blank strings are read as absent, not as empty values', () {
      final profile = UserProfile.fromMap({
        'user_id': 'u-1',
        'display_name': '   ',
        'bio': '',
      });
      expect(profile.displayName, isNull);
      expect(profile.bio, isNull);
    });

    test('numbers survive arriving as strings', () {
      final profile = UserProfile.fromMap({
        'user_id': 'u-1',
        'years_experience': '7',
        'ig_followers_count': '12300',
      });
      expect(profile.yearsExperience, 7);
      expect(profile.igFollowersCount, 12300);
    });

    test('a malformed social_media value degrades to empty', () {
      for (final bad in ['not-a-map', 42, <String>['a'], null]) {
        final profile =
            UserProfile.fromMap({'user_id': 'u-1', 'social_media': bad});
        expect(profile.socialMedia.isEmpty, isTrue);
      }
    });

    test('text arrays drop nulls and blanks', () {
      final profile = UserProfile.fromMap({
        'user_id': 'u-1',
        'specialization': ['Luxury', '', null, '  ', 'Commercial'],
      });
      expect(profile.specialization, ['Luxury', 'Commercial']);
    });

    test('raw is unmodifiable so the cached row cannot be mutated', () {
      final profile = UserProfile.fromMap({'user_id': 'u-1'});
      expect(() => profile.raw['user_id'] = 'tampered', throwsUnsupportedError);
    });
  });

  group('display fallback chains (JS truthiness)', () {
    test('displayTitle: company_name || agency_name || display_name', () {
      String? title(Map<String, dynamic> m) =>
          UserProfile.fromMap({'user_id': 'u', ...m}).displayTitle;

      expect(
        title({
          'company_name': 'Prestige',
          'agency_name': 'Dream',
          'display_name': 'Asha',
        }),
        'Prestige',
      );
      expect(title({'agency_name': 'Dream', 'display_name': 'Asha'}), 'Dream');
      expect(title({'display_name': 'Asha'}), 'Asha');

      // The chain that Dart's `??` would get wrong.
      expect(
        title({'company_name': '', 'agency_name': 'Dream'}),
        'Dream',
        reason: "'' is falsy in JS, so React falls through to agency_name",
      );
    });

    test('effectiveCity: city || work_city', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'city': '', 'work_city': 'Pune'})
            .effectiveCity,
        'Pune',
      );
      expect(
        UserProfile.fromMap(
                {'user_id': 'u', 'city': 'Mumbai', 'work_city': 'Pune'})
            .effectiveCity,
        'Mumbai',
      );
    });

    test('effectiveBio: bio || company_description (display order)', () {
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'bio': 'Personal bio',
          'company_description': 'Company blurb',
        }).effectiveBio,
        'Personal bio',
      );
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'bio': '',
          'company_description': 'Company blurb',
        }).effectiveBio,
        'Company blurb',
      );
    });

    test('effectiveRera: rera_number || license_number', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'license_number': 'LIC-9'})
            .effectiveRera,
        'LIC-9',
      );
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'rera_number': 'RERA-1',
          'license_number': 'LIC-9',
        }).effectiveRera,
        'RERA-1',
      );
    });

    test('effectiveWebsite: website || website_url', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'website_url': 'b.com'})
            .effectiveWebsite,
        'b.com',
      );
    });

    test('effectivePhone: phone || mobile_number', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'mobile_number': '9990001111'})
            .effectivePhone,
        '9990001111',
      );
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'phone': '+919876543210',
          'mobile_number': '9990001111',
        }).effectivePhone,
        '+919876543210',
      );
    });

    test('effectiveAddress: office_address || city || work_city', () {
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'office_address': '12 MG Road',
          'city': 'Mumbai',
        }).effectiveAddress,
        '12 MG Road',
      );
      expect(
        UserProfile.fromMap({'user_id': 'u', 'work_city': 'Pune'})
            .effectiveAddress,
        'Pune',
      );
    });

    test('effectiveExperience: a stored 0 falls through, as JS || does', () {
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'years_experience': 0,
          'years_of_experience': 8,
        }).effectiveExperience,
        8,
        reason: '0 is falsy in JS, so React uses years_of_experience',
      );

      // ...but a genuine 0 with nothing else present is still reported as 0,
      // not as null, so the row can render "0 yrs" rather than vanishing.
      expect(
        UserProfile.fromMap({'user_id': 'u', 'years_experience': 0})
            .effectiveExperience,
        0,
      );
    });

    test('hasExperienceField uses presence, not truthiness', () {
      // The portal gates the row on `!== undefined` (UserProfile.tsx:1101), so a
      // stored 0 still shows a row.
      expect(
        UserProfile.fromMap({'user_id': 'u', 'years_experience': 0})
            .hasExperienceField,
        isTrue,
      );
      expect(
        UserProfile.fromMap({'user_id': 'u'}).hasExperienceField,
        isFalse,
      );
    });
  });

  group('isVerified — UserProfile.tsx:1038', () {
    test('verification_status == verified', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'verification_status': 'verified'})
            .isVerified,
        isTrue,
      );
      expect(
        UserProfile.fromMap({'user_id': 'u', 'verification_status': 'VERIFIED'})
            .isVerified,
        isTrue,
        reason: 'case-insensitive so a differently-cased row still verifies',
      );
    });

    test('a license number alone verifies', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'license_number': 'LIC-1'})
            .isVerified,
        isTrue,
      );
    });

    test('a RERA number alone verifies', () {
      expect(
        UserProfile.fromMap({'user_id': 'u', 'rera_number': 'RERA-1'})
            .isVerified,
        isTrue,
      );
    });

    test('nothing set, or a pending status, is not verified', () {
      expect(UserProfile.fromMap({'user_id': 'u'}).isVerified, isFalse);
      expect(
        UserProfile.fromMap({'user_id': 'u', 'verification_status': 'pending'})
            .isVerified,
        isFalse,
      );
      expect(
        UserProfile.fromMap({
          'user_id': 'u',
          'verification_status': 'pending',
          'license_number': '',
          'rera_number': '   ',
        }).isVerified,
        isFalse,
        reason: 'blank identifiers must not count as credentials',
      );
    });
  });

  group('social_media reads both key spellings', () {
    ProfileSocialMedia sm(Map<String, dynamic> raw) =>
        UserProfile.fromMap({'user_id': 'u', 'social_media': raw}).socialMedia;

    test('display spelling wins where the two portal files disagree', () {
      final both = sm({
        'facebook': 'fb-display',
        'facebook_page_link': 'fb-edit',
      });
      expect(both.facebook, 'fb-display');
    });

    test('the edit-form spelling is still found when it is the only one', () {
      expect(sm({'facebook_page_link': 'fb-edit'}).facebook, 'fb-edit');
      expect(sm({'instagram_username': 'ig-edit'}).instagram, 'ig-edit');
      expect(sm({'linkedin_profile_url': 'li-edit'}).linkedin, 'li-edit');
      expect(sm({'youtube_channel_link': 'yt-edit'}).youtube, 'yt-edit');
      expect(sm({'whatsapp_number': '919876543210'}).whatsapp, '919876543210');
      expect(sm({'telegram_channel_link': 'tg-edit'}).telegram, 'tg-edit');
      expect(sm({'twitter_profile_url': 'x-edit'}).twitter, 'x-edit');
    });

    test('broker and builder alternate-mobile spellings both resolve', () {
      // Broker writes alt_mobile_number; builder/influencer write
      // alternate_mobile (EditProfile.tsx:365, 381, 395).
      expect(sm({'alt_mobile_number': '111'}).alternateMobile, '111');
      expect(sm({'alternate_mobile': '222'}).alternateMobile, '222');
    });

    test('primary platform resolves from either spelling', () {
      expect(sm({'primary_platform': 'Instagram'}).primaryPlatform, 'Instagram');
      expect(
        sm({'primary_content_platform': 'YouTube'}).primaryPlatform,
        'YouTube',
      );
    });

    test('numeric metrics parse, including from strings', () {
      final metrics = sm({
        'instagram_followers': 12300,
        'youtube_subscribers': '4500',
        'price_range_min': 2500000,
      });
      expect(metrics.instagramFollowers, 12300);
      expect(metrics.youtubeSubscribers, 4500);
      expect(metrics.priceRangeMin, 2500000);
    });

    test('chip lists parse and drop blanks', () {
      expect(
        sm({'areas_of_expertise': ['Luxury Properties', '', 'Commercial Leasing']})
            .areasOfExpertise,
        ['Luxury Properties', 'Commercial Leasing'],
      );
      expect(sm({'languages_known': null}).languagesKnown, isEmpty);
    });

    test('hasAnySocialLink reflects either spelling, and nothing else', () {
      expect(sm({}).hasAnySocialLink, isFalse);
      expect(sm({'gender': 'Male'}).hasAnySocialLink, isFalse);
      expect(sm({'instagram_username': 'x'}).hasAnySocialLink, isTrue);
      expect(sm({'telegram': 'y'}).hasAnySocialLink, isTrue);
    });

    test('raw stays reachable for keys nothing has modelled', () {
      expect(sm({'some_future_key': 'v'}).raw['some_future_key'], 'v');
    });
  });

  group('role helpers', () {
    UserProfile withType(String? type) =>
        UserProfile.fromMap({'user_id': 'u', 'user_type': type});

    test('each known role resolves, case-insensitively', () {
      expect(withType('builder').isBuilder, isTrue);
      expect(withType('Builder').isBuilder, isTrue);
      expect(withType('broker').isBroker, isTrue);
      expect(withType('influencer').isInfluencer, isTrue);
    });

    test('individual, unknown and null all read as individual', () {
      expect(withType('individual').isIndividual, isTrue);
      expect(withType('team_member').isIndividual, isTrue);
      expect(withType(null).isIndividual, isTrue);
      expect(withType('builder').isIndividual, isFalse);
    });
  });

  group('initials', () {
    String initialsFor(Map<String, dynamic> m) =>
        UserProfile.fromMap({'user_id': 'u', ...m}).initials;

    test('two words give two letters', () {
      expect(initialsFor({'display_name': 'Asha Menon'}), 'AM');
    });

    test('capped at two letters', () {
      expect(initialsFor({'display_name': 'Asha Ravi Menon Nair'}), 'AR');
    });

    test('one word gives one letter', () {
      expect(initialsFor({'display_name': 'Asha'}), 'A');
    });

    test('derived from displayTitle, so a company name wins', () {
      expect(
        initialsFor({
          'company_name': 'Prestige Builders',
          'display_name': 'Asha Menon',
        }),
        'PB',
      );
    });

    test('collapses extra whitespace', () {
      expect(initialsFor({'display_name': '  Asha   Menon  '}), 'AM');
    });

    test('falls back to U when there is no name at all', () {
      expect(initialsFor({}), 'U');
      expect(initialsFor({'display_name': '   '}), 'U');
    });
  });
}
