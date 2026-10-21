import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/services/auth_resolver.dart';

void main() {
  group('profile missing / blocked', () {
    test('a null profile (zero rows) resolves to profileMissing', () {
      expect(AuthResolver.classify(null), AuthDestination.profileMissing);
    });

    test('is_blocked takes priority even on an otherwise-complete profile', () {
      final destination = AuthResolver.classify({
        'is_blocked': true,
        'user_type': 'builder',
        'profile_complete': true,
      });

      expect(destination, AuthDestination.blocked);
    });
  });

  group('completed profiles → ready, matching the portal rule exactly', () {
    // user_type exists AND profile_complete == true — no per-type exception.
    for (final type in ['individual', 'builder', 'broker', 'influencer']) {
      test('profile_complete true routes $type straight home', () {
        final destination = AuthResolver.classify({
          'user_type': type,
          'profile_complete': true,
          'is_blocked': false,
        });

        expect(destination, AuthDestination.ready);
      });
    }
  });

  group(
    'incomplete profiles with user_type already set → resume registration',
    () {
      // All four roles — including individual — must resolve to their
      // resume-registration destination, not `ready`: the portal explicitly
      // refuses to let "a role picked but the wizard abandoned partway
      // through" reach the app, uniformly, with no carve-out for individual.
      final cases = {
        'builder': AuthDestination.needsBuilderRegistration,
        'broker': AuthDestination.needsBrokerRegistration,
        'influencer': AuthDestination.needsInfluencerRegistration,
        'individual': AuthDestination.needsIndividualRegistration,
      };

      cases.forEach((type, expected) {
        test('$type with profile_complete false resolves to $expected', () {
          final destination = AuthResolver.classify({
            'user_type': type,
            'profile_complete': false,
          });

          expect(destination, expected);
        });
      });
    },
  );

  group('user_type not yet written', () {
    test(
      'null user_type resolves to needsAccountType regardless of any other field',
      () {
        final destination = AuthResolver.classify({
          'user_type': null,
          'profile_complete': false,
        });

        expect(destination, AuthDestination.needsAccountType);
      },
    );

    test(
      'a completely bare row (only user_id) resolves to needsAccountType',
      () {
        final destination = AuthResolver.classify({'user_id': 'user-1'});

        expect(destination, AuthDestination.needsAccountType);
      },
    );
  });

  test(
    'an unrecognised user_type with profile_complete false conservatively falls back to ready',
    () {
      final destination = AuthResolver.classify({
        'user_type': 'something-unexpected',
        'profile_complete': false,
      });

      expect(destination, AuthDestination.ready);
    },
  );
}
