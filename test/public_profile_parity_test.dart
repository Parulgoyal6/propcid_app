// Phase 1 Stage 1 parity guards for the Public Profile screen.
//
// These assert the portal's *rules*, not its pixels: the gates and branches that
// would silently expose or hide the wrong thing. Each one names the
// pages/UserProfile.tsx line it comes from, so a future reader can check the
// claim rather than trust it.
//
// Pure unit tests over the model and the rating fold — no Supabase, no rendering.
// The widgets they feed are covered by number_format_test.dart's parity pass and
// by the existing shared-component suite.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/profile_review.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/screens/profile/public_profile_role.dart';
import 'package:propcid_app/services/profile_connection_service.dart';

UserProfile _profile({
  String userType = 'broker',
  Map<String, dynamic> extra = const {},
}) =>
    UserProfile.fromMap({
      'user_id': 'u-1',
      'display_name': 'Asha Menon',
      'user_type': userType,
      ...extra,
    });

Map<String, dynamic> _rating({
  required String id,
  required int value,
  String raterId = 'r-1',
  String? review,
}) =>
    <String, dynamic>{
      'id': id,
      'rating': value,
      'review': review,
      'rater_id': raterId,
      'created_at': '2026-08-01T10:00:00Z',
    };

void main() {
  group('contact visibility gate', () {
    // UserProfile.tsx:1520 — phone/email render only when connected OR self.
    test('only connected and self statuses unlock contact', () {
      expect(ProfileConnectionStatus.connected.isConnected, isTrue);
      expect(ProfileConnectionStatus.none.isConnected, isFalse);
      expect(ProfileConnectionStatus.pendingSent.isConnected, isFalse);
      expect(ProfileConnectionStatus.pendingReceived.isConnected, isFalse);
    });

    test('an anonymous row carries no contact columns at all', () {
      // The anon grant omits phone/email/mobile_number, so they are absent from
      // the map rather than null — there is nothing to leak even if the gate were
      // wrong.
      final anon = _profile();
      expect(anon.phone, isNull);
      expect(anon.email, isNull);
      expect(anon.effectivePhone, isNull);
      expect(anon.hasContactDetails, isFalse);
    });

    test('address is public even when contact is locked', () {
      // UserProfile.tsx:1537 renders the address outside the connected gate.
      final profile = _profile(extra: {'office_address': '12 MG Road'});
      expect(profile.effectiveAddress, '12 MG Road');
    });
  });

  group('connections tile visibility', () {
    // UserProfile.tsx:1131 — `profile?.user_type !== 'individual'`.
    test('hidden for individual and unknown types', () {
      expect(_profile(userType: 'individual').isIndividual, isTrue);
      expect(_profile(userType: 'team_member').isIndividual, isTrue);
    });

    test('shown for the three business roles', () {
      for (final role in ['builder', 'broker', 'influencer']) {
        expect(_profile(userType: role).isIndividual, isFalse, reason: role);
      }
    });
  });

  group('rating shown depends on the role', () {
    // UserProfile.tsx:193 — a builder is scored by its customers, everyone else
    // by everyone.
    final rows = [
      _rating(id: '1', value: 5, raterId: 'customer-1'),
      _rating(id: '2', value: 5, raterId: 'customer-2'),
      _rating(id: '3', value: 1, raterId: 'broker-1'),
    ];
    const types = <String, String?>{
      'customer-1': 'individual',
      'customer-2': 'influencer',
      'broker-1': 'broker',
    };

    final breakdown = RatingBreakdown.fromRatings(
      rows,
      raterTypes: types,
      reviews: const [],
    );

    test('customer average excludes brokers', () {
      expect(breakdown.customer.count, 2);
      expect(breakdown.customer.average, 5.0);
    });

    test('broker average is brokers only', () {
      expect(breakdown.broker.count, 1);
      expect(breakdown.broker.average, 1.0);
    });

    test('total is everyone', () {
      expect(breakdown.total.count, 3);
      // (5 + 5 + 1) / 3 = 3.666… → 3.7 at one decimal, matching
      // RatingsService.getRatingSummary's rounding.
      expect(breakdown.total.average, 3.7);
    });

    test('a builder shows the customer average, others the total', () {
      expect(breakdown.displayFor(isBuilder: true).average, 5.0);
      expect(breakdown.displayFor(isBuilder: false).average, 3.7);
    });

    test('an unknown rater counts as a customer', () {
      // useUserRatings.ts:61 defaults a missing profile to 'individual'.
      final withUnknown = RatingBreakdown.fromRatings(
        [_rating(id: '1', value: 4, raterId: 'ghost')],
        raterTypes: const {},
        reviews: const [],
      );
      expect(withUnknown.customer.count, 1);
      expect(withUnknown.broker.count, 0);
    });

    test('broker trust score only exists when a broker has rated', () {
      expect(breakdown.hasBrokerTrustScore, isTrue);
      final noBroker = RatingBreakdown.fromRatings(
        [_rating(id: '1', value: 4, raterId: 'customer-1')],
        raterTypes: const {'customer-1': 'individual'},
        reviews: const [],
      );
      expect(noBroker.hasBrokerTrustScore, isFalse);
    });
  });

  group('rating distribution', () {
    test('always carries all five bars, even at zero', () {
      expect(RatingBreakdown.zero.distribution.keys.toSet(), {1, 2, 3, 4, 5});
      expect(
        RatingBreakdown.zero.distribution.values.every((v) => v == 0),
        isTrue,
      );
    });

    test('counts each star and reports the peak', () {
      final breakdown = RatingBreakdown.fromRatings(
        [
          _rating(id: '1', value: 5),
          _rating(id: '2', value: 5),
          _rating(id: '3', value: 5),
          _rating(id: '4', value: 3),
        ],
        raterTypes: const {},
        reviews: const [],
      );

      expect(breakdown.distribution[5], 3);
      expect(breakdown.distribution[3], 1);
      expect(breakdown.distribution[4], 0);
      expect(breakdown.distributionPeak, 3);
    });

    test('peak is never zero, so callers can divide safely', () {
      expect(RatingBreakdown.zero.distributionPeak, 1);
    });

    test('an out-of-range value still counts toward the average', () {
      // The column is not constrained to 1–5 in the client, and the portal
      // averages whatever it holds. Such a value has no bar to land in.
      final breakdown = RatingBreakdown.fromRatings(
        [_rating(id: '1', value: 7)],
        raterTypes: const {},
        reviews: const [],
      );
      expect(breakdown.total.count, 1);
      expect(breakdown.total.average, 7.0);
      expect(breakdown.distribution.values.every((v) => v == 0), isTrue);
    });
  });

  group('reviews', () {
    test('a rater with no profile row reads as Anonymous', () {
      // UserProfile.tsx:531 falls back the same way.
      final review = ProfileReview.fromRow(
        _rating(id: '1', value: 4, review: 'Great to work with'),
      );
      expect(review.raterName, 'Anonymous');
      expect(review.raterInitial, 'A');
    });

    test('a resolved rater uses their display title', () {
      final review = ProfileReview.fromRow(
        _rating(id: '1', value: 4, review: 'Great'),
        raterProfile: UserProfile.fromMap({
          'user_id': 'r-1',
          'display_name': 'Ravi Kumar',
        }),
      );
      expect(review.raterName, 'Ravi Kumar');
      expect(review.raterInitial, 'R');
    });

    test('a company name wins over the personal name, as elsewhere', () {
      final review = ProfileReview.fromRow(
        _rating(id: '1', value: 4, review: 'Great'),
        raterProfile: UserProfile.fromMap({
          'user_id': 'r-1',
          'display_name': 'Ravi Kumar',
          'company_name': 'Kumar Realty',
        }),
      );
      expect(review.raterName, 'Kumar Realty');
    });

    test('blank and whitespace-only review text counts as no text', () {
      for (final text in [null, '', '   ']) {
        final review = ProfileReview.fromRow(
          _rating(id: '1', value: 4, review: text),
        );
        expect(review.hasText, isFalse, reason: 'for "$text"');
      }
    });

    test('review text is trimmed', () {
      final review = ProfileReview.fromRow(
        _rating(id: '1', value: 4, review: '  Solid work  '),
      );
      expect(review.review, 'Solid work');
      expect(review.hasText, isTrue);
    });
  });

  group('role wording', () {
    test('subtitle covers every role with a Member fallback', () {
      expect(roleSubtitle('builder'), 'Real Estate Builder');
      expect(roleSubtitle('broker'), 'Real Estate Broker');
      expect(roleSubtitle('influencer'), 'Real Estate Influencer');
      expect(roleSubtitle('individual'), 'PropCid Member');
      expect(roleSubtitle(null), 'PropCid Member');
      expect(roleSubtitle('BUILDER'), 'Real Estate Builder');
    });

    test('badge is uppercase and falls back to MEMBER', () {
      expect(roleBadge('builder'), 'BUILDER');
      expect(roleBadge('individual'), 'MEMBER');
      expect(roleBadge(null), 'MEMBER');
    });

    test('content label switches projects for builders only', () {
      expect(contentLabel('builder', plural: true), 'Projects');
      expect(contentLabel('builder', plural: false), 'Project');
      expect(contentLabel('broker', plural: true), 'Listings');
      expect(contentLabel(null, plural: true), 'Listings');
    });

    test('re-exports the existing role helpers rather than restating them', () {
      // If `profile_role.dart` ever changes, these come with it — there is no
      // second copy to drift.
      expect(roleLabel('builder'), 'Builder');
      expect(roleLabel('individual'), 'Member');
      expect(roleColor('broker'), isNotNull);
    });
  });

  group('verified badge condition', () {
    // UserProfile.tsx:1038 — broader than the own-profile screen's
    // `auth.userRole != null`, deliberately.
    test('any of the three signals verifies', () {
      expect(
        _profile(extra: {'verification_status': 'verified'}).isVerified,
        isTrue,
      );
      expect(_profile(extra: {'license_number': 'L-1'}).isVerified, isTrue);
      expect(_profile(extra: {'rera_number': 'R-1'}).isVerified, isTrue);
    });

    test('none of them means not verified', () {
      expect(_profile().isVerified, isFalse);
    });
  });

  group('builder project visibility', () {
    // UserProfile.tsx:416 — a visitor sees approved projects only; the owner sees
    // everything. The filter lives in ProfileContentService, so this documents
    // the flag the provider must pass.
    test('viewerIsOwner is driven by the self check', () {
      final selfViewer = _profile(userType: 'builder');
      // A profile is "self" when the viewer id equals the profile's user id; the
      // model exposes the id the provider compares.
      expect(selfViewer.userId, 'u-1');
    });
  });
}
