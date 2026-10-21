import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/services/auth_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService authService;
  late AuthProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authService = FakeAuthService();
    provider = AuthProvider(
      authService: authService,
      teamService: FakeTeamService(),
    );
  });

  tearDown(() async {
    provider.dispose();
    await authService.dispose();
  });

  test('starts signed out before any auth event arrives', () {
    expect(provider.isLoggedIn, isFalse);
    expect(provider.userId, isNull);
  });

  test(
    'a signedOut event with no prior session leaves identity cleared and sets destination signedOut',
    () async {
      authService.emit(AuthState(AuthChangeEvent.signedOut, null));
      await Future.delayed(Duration.zero);

      expect(provider.isLoggedIn, isFalse);
      expect(provider.userId, isNull);
      expect(provider.destination, AuthDestination.signedOut);
      expect(provider.isResolving, isFalse);
    },
  );

  group('isResolving — auth still initializing', () {
    test(
      'is true the instant a session-carrying event arrives, before the profile fetch lands',
      () async {
        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': 'individual',
          'profile_complete': true,
        };
        authService.currentUserOverride = user;
        final pause = Completer<void>();
        authService.pauseNextFetch = pause;

        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);

        // isLoggedIn is already true (set synchronously from the session),
        // but destination must still be unresolved — this is exactly the
        // window that must never be treated as "ready" or "signed out".
        expect(provider.isLoggedIn, isTrue);
        expect(provider.isResolving, isTrue);
        expect(provider.destination, isNull);

        pause.complete();
        await Future.delayed(Duration.zero);

        expect(provider.isResolving, isFalse);
        expect(provider.destination, AuthDestination.ready);
      },
    );
  });

  test(
    'a restored session (initialSession) populates isLoggedIn/userId immediately, then the profile',
    () async {
      final user = fakeUser('user-a', email: 'a@example.com');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': true,
        'user_role': 'seller',
        'display_name': 'A',
      };
      authService.currentUserOverride = user;

      authService.emit(
        AuthState(AuthChangeEvent.initialSession, fakeSession(user)),
      );
      // One microtask hop for the stream event to reach the listener at all
      // (StreamController delivery is never synchronous) — still zero
      // network round-trips, unlike the profile fields checked below.
      await Future.delayed(Duration.zero);

      // userId/isLoggedIn are set directly from the session, before the
      // profiles round-trip resolves — see the comment in _handleAuthState.
      expect(provider.isLoggedIn, isTrue);
      expect(provider.userId, 'user-a');

      await Future.delayed(Duration.zero);

      expect(provider.userType, 'builder');
      expect(provider.userRole, 'seller');
      expect(provider.destination, AuthDestination.ready);
    },
  );

  test(
    'a stream error does not clear a previously-established identity',
    () async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'individual',
        'profile_complete': true,
      };
      authService.currentUserOverride = user;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);
      expect(provider.isLoggedIn, isTrue);

      authService.emitError(Exception('token refresh network failure'));
      await Future.delayed(Duration.zero);

      expect(provider.isLoggedIn, isTrue);
      expect(provider.userId, 'user-a');
    },
  );

  test(
    'a profile-fetch failure sets profileFetchFailed, not signedOut, and does not clear identity',
    () async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      authService.nextProfileFetchError = Exception('socket closed');

      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);

      expect(provider.destination, AuthDestination.profileFetchFailed);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.userId, 'user-a');
    },
  );

  test('a blocked profile forces sign-out and clears identity', () async {
    final user = fakeUser('user-a');
    authService.profilesByUserId['user-a'] = {
      'is_blocked': true,
      'user_type': 'individual',
      'profile_complete': true,
    };
    authService.currentUserOverride = user;

    authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    expect(authService.logoutCallCount, 1);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.userId, isNull);
    expect(provider.destination, AuthDestination.signedOut);
    expect(
      AuthProvider.consumeBlockedMessage(),
      AuthProvider.blockedAccountMessage,
    );
    // Consumed once — a second read must not repeat a stale message.
    expect(AuthProvider.consumeBlockedMessage(), isNull);
  });

  test('logout clears userId (not just the other identity fields)', () async {
    final user = fakeUser('user-a');
    authService.profilesByUserId['user-a'] = {
      'user_type': 'individual',
      'profile_complete': true,
    };
    authService.currentUserOverride = user;
    authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
    await Future.delayed(Duration.zero);
    expect(provider.userId, 'user-a');

    await provider.logout();

    expect(provider.userId, isNull);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.destination, AuthDestination.signedOut);
  });

  test(
    'account A -> logout -> account B: a slow A fetch must not overwrite B',
    () async {
      final userA = fakeUser('user-a');
      final userB = fakeUser('user-b');
      final pauseA = Completer<void>();
      authService.pauseNextFetch = pauseA;
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': true,
        'user_role': 'seller',
      };
      authService.profilesByUserId['user-b'] = {
        'user_type': 'individual',
        'profile_complete': true,
        'user_role': 'buyer',
      };

      // A signs in — its profile fetch starts but is paused mid-flight.
      authService.currentUserOverride = userA;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(userA)));
      await Future.delayed(Duration.zero);
      expect(provider.userId, 'user-a');
      expect(provider.isResolving, isTrue);

      // A logs out before their own fetch resolves.
      await provider.logout();

      // B signs in and its (unpaused) fetch resolves immediately.
      authService.currentUserOverride = userB;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(userB)));
      await Future.delayed(Duration.zero);
      expect(provider.userId, 'user-b');
      expect(provider.userType, 'individual');
      expect(provider.destination, AuthDestination.ready);

      // Now A's stale fetch finally resolves — it must be dropped, not
      // resurrect A's role/type over B's, and must not flip destination
      // back to something resolving for A.
      pauseA.complete();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.userId, 'user-b');
      expect(provider.userType, 'individual');
      expect(provider.userRole, 'buyer');
      expect(provider.destination, AuthDestination.ready);
    },
  );

  test(
    'repeated notifications while the same user stays signed in do not change identity',
    () async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'broker',
        'profile_complete': true,
      };
      authService.currentUserOverride = user;

      for (var i = 0; i < 5; i++) {
        authService.emit(
          AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);
      }

      expect(provider.userId, 'user-a');
      expect(provider.userType, 'broker');
      expect(provider.isLoggedIn, isTrue);
      expect(provider.destination, AuthDestination.ready);
    },
  );

  group('deleted-user liveness check (current_auth_user_is_live)', () {
    test('cached session for a since-deleted user: liveness=false signs out '
        'via logout() and never looks up the profile', () async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'individual',
        'profile_complete': true,
      };
      authService.currentUserOverride = user;
      authService.isLiveOverride = false;

      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(authService.isCurrentUserLiveCalls, ['user-a']);
      expect(authService.profileFetchCalls, isEmpty);
      expect(authService.logoutCallCount, 1);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.userId, isNull);
      expect(provider.destination, AuthDestination.signedOut);
    });

    test('a connectivity failure verifying liveness retains identity and '
        'falls back to the retryable profileFetchFailed state', () async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      authService.nextIsCurrentUserLiveError = Exception('socket closed');

      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);

      expect(authService.profileFetchCalls, isEmpty);
      expect(authService.logoutCallCount, 0);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.userId, 'user-a');
      expect(provider.destination, AuthDestination.profileFetchFailed);
    });
  });

  group('resolver destinations reflected end-to-end through AuthProvider', () {
    final cases = {
      'builder': AuthDestination.needsBuilderRegistration,
      'broker': AuthDestination.needsBrokerRegistration,
      'influencer': AuthDestination.needsInfluencerRegistration,
      'individual': AuthDestination.needsIndividualRegistration,
    };

    cases.forEach((type, expected) {
      test('incomplete $type profile resolves to $expected', () async {
        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': type,
          'profile_complete': false,
        };
        authService.currentUserOverride = user;

        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);

        expect(provider.destination, expected);
      });
    });

    test('no user_type resolves to needsAccountType', () async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': null,
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);

      expect(provider.destination, AuthDestination.needsAccountType);
    });

    test(
      'a legacy user with no profiles row at all resolves to profileMissing',
      () async {
        final user = fakeUser('user-a');
        // No entry in profilesByUserId — fetchProfile returns null.
        authService.currentUserOverride = user;

        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);

        expect(provider.destination, AuthDestination.profileMissing);
      },
    );
  });

  group('completeAccountSetup', () {
    /// Establishes a real signed-in identity first (so AuthProvider's
    /// generation/expectedUserId guards accept the subsequent
    /// `completeAccountSetup` → `refreshProfile` round-trip) with no
    /// `user_type` yet — the state `AccountTypeScreen` is actually shown for.
    Future<void> signInWithNoType(User user) async {
      authService.profilesByUserId[user.id] = {
        'user_type': null,
        'profile_complete': false,
      };
      authService.currentUserOverride = user;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);
    }

    test('rejects an invalid type without writing anything', () async {
      final user = fakeUser('user-a');
      await signInWithNoType(user);

      final error = await provider.completeAccountSetup(
        fullName: 'Jane Doe',
        userType: 'buyer',
      );

      expect(error, isNotNull);
      expect(authService.upsertCalls, isEmpty);
    });

    test('rejects a blank name without writing anything', () async {
      final user = fakeUser('user-a');
      await signInWithNoType(user);

      final error = await provider.completeAccountSetup(
        fullName: '   ',
        userType: 'builder',
      );

      expect(error, isNotNull);
      expect(authService.upsertCalls, isEmpty);
    });

    test('rejects with no current session', () async {
      authService.currentUserOverride = null;

      final error = await provider.completeAccountSetup(
        fullName: 'Jane Doe',
        userType: 'builder',
      );

      expect(error, isNotNull);
      expect(authService.upsertCalls, isEmpty);
    });

    test(
      'a valid submission writes user_id/display_name/user_type/profile_complete:false and never user_role, then resolves to the matching registration destination',
      () async {
        final user = fakeUser('user-a');
        await signInWithNoType(user);

        final error = await provider.completeAccountSetup(
          fullName: 'Jane Doe',
          userType: 'builder',
        );

        expect(error, isNull);
        expect(authService.upsertCalls, [
          {
            'userId': 'user-a',
            'displayName': 'Jane Doe',
            'userType': 'builder',
          },
        ]);
        expect(
          authService.profilesByUserId['user-a']?['profile_complete'],
          false,
        );
        expect(
          authService.profilesByUserId['user-a']?.containsKey('user_role'),
          isFalse,
        );
        expect(provider.destination, AuthDestination.needsBuilderRegistration);
      },
    );
  });

  group('legacy pending_user_type cannot influence routing', () {
    test(
      'a stale pending_user_type=builder is ignored for a new confirmed user with no user_type',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_user_type', 'builder');
        await prefs.setString('pending_user_type_uid', 'some-other-user');

        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': null,
          'profile_complete': false,
        };
        authService.currentUserOverride = user;
        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);

        // The resolver (AuthResolver.classify) takes only the profile row as
        // input — there is no code path left by which a SharedPreferences
        // value could reach it — so this must be needsAccountType, never
        // needsBuilderRegistration.
        expect(provider.destination, AuthDestination.needsAccountType);
      },
    );

    test(
      "an existing user's stored database user_type remains authoritative even with an unrelated stale pending value present",
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_user_type', 'influencer');
        await prefs.setString('pending_user_type_uid', 'user-a');

        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': 'broker',
          'profile_complete': true,
        };
        authService.currentUserOverride = user;
        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(user)),
        );
        await Future.delayed(Duration.zero);

        expect(provider.destination, AuthDestination.ready);
        expect(provider.userType, 'broker');
      },
    );
  });

  group('signUpWithEmail — portal-parity email signup', () {
    test('rejects a blank email without calling the service', () async {
      final error = await provider.signUpWithEmail('   ');

      expect(error, isNotNull);
      expect(authService.signUpWithEmailCalls, isEmpty);
    });

    test(
      'sends exactly the entered (trimmed) email and nothing else',
      () async {
        final error = await provider.signUpWithEmail('  jane@example.com  ');

        expect(error, isNull);
        expect(authService.signUpWithEmailCalls, ['jane@example.com']);
      },
    );

    test('never writes pending_user_type/pending_user_type_uid', () async {
      await provider.signUpWithEmail('jane@example.com');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_user_type'), isNull);
      expect(prefs.getString('pending_user_type_uid'), isNull);
    });

    test('surfaces a service failure as an error string', () async {
      authService.nextSignUpError = Exception('rate limited');

      final error = await provider.signUpWithEmail('jane@example.com');

      expect(error, isNotNull);
    });

    test(
      'does not change isLoggedIn/destination — no session exists until the link is confirmed',
      () async {
        await provider.signUpWithEmail('jane@example.com');

        expect(provider.isLoggedIn, isFalse);
        expect(provider.destination, isNot(AuthDestination.ready));
      },
    );
  });

  group('same-user event-burst coalescing (physical-device callback race)', () {
    // Reproduces the exact class of event physically observed right after an
    // OAuth/magic-link callback: multiple session-carrying events for the
    // SAME identity arriving before the first profile fetch has landed.
    // Before this fix, every one of these bumped `_authGeneration`, so an
    // in-flight fetch could be discarded by a later same-user event with no
    // guarantee any fetch ever completed against a still-current
    // generation — losing the destination (and the navigation) entirely.

    Future<void> fireBurst(User user) async {
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await Future.delayed(Duration.zero);
      authService.emit(
        AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
      );
      authService.emit(
        AuthState(AuthChangeEvent.userUpdated, fakeSession(user)),
      );
      await Future.delayed(Duration.zero);
    }

    test(
      'new user (profile missing user_type): burst never yields Home or signedOut, '
      'settles on needsAccountType via at most one extra coalesced fetch',
      () async {
        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': null,
          'profile_complete': false,
        };
        authService.currentUserOverride = user;
        final pause = Completer<void>();
        authService.pauseNextFetch = pause;

        // Events arrive DURING the first fetch.
        await fireBurst(user);

        expect(provider.destination, isNot(AuthDestination.ready));
        expect(provider.destination, isNot(AuthDestination.signedOut));
        expect(provider.isLoggedIn, isTrue);

        pause.complete();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(provider.destination, AuthDestination.needsAccountType);
        expect(provider.destination, isNot(AuthDestination.ready));
        expect(provider.destination, isNot(AuthDestination.signedOut));
        // Coalescing means the burst produces the initial fetch plus at most
        // one rerun — never one fetch per event (which would be 3).
        expect(authService.profileFetchCalls.length, lessThanOrEqualTo(2));
      },
    );

    test('existing complete user: burst settles on ready exactly, never an '
        'intermediate signedOut/null destination', () async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': true,
      };
      authService.currentUserOverride = user;
      final pause = Completer<void>();
      authService.pauseNextFetch = pause;

      await fireBurst(user);
      expect(provider.destination, isNot(AuthDestination.signedOut));

      pause.complete();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.destination, AuthDestination.ready);
      expect(authService.profileFetchCalls.length, lessThanOrEqualTo(2));
    });

    test(
      'incomplete builder: burst settles on needsBuilderRegistration, never Home',
      () async {
        final user = fakeUser('user-a');
        authService.profilesByUserId['user-a'] = {
          'user_type': 'builder',
          'profile_complete': false,
        };
        authService.currentUserOverride = user;
        final pause = Completer<void>();
        authService.pauseNextFetch = pause;

        await fireBurst(user);
        pause.complete();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(provider.destination, AuthDestination.needsBuilderRegistration);
        expect(provider.destination, isNot(AuthDestination.ready));
      },
    );

    test(
      'account switching under a burst: A signs in, A profile fetch starts, '
      'signedOut, B signs in, A completes then B completes — only B decides',
      () async {
        final userA = fakeUser('user-a');
        final userB = fakeUser('user-b');
        final pauseA = Completer<void>();
        authService.pauseNextFetch = pauseA;
        authService.profilesByUserId['user-a'] = {
          'user_type': 'builder',
          'profile_complete': true,
        };
        authService.profilesByUserId['user-b'] = {
          'user_type': 'individual',
          'profile_complete': true,
        };

        authService.currentUserOverride = userA;
        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(userA)),
        );
        await Future.delayed(Duration.zero);

        authService.emit(AuthState(AuthChangeEvent.signedOut, null));
        await Future.delayed(Duration.zero);

        authService.currentUserOverride = userB;
        authService.emit(
          AuthState(AuthChangeEvent.signedIn, fakeSession(userB)),
        );
        await Future.delayed(Duration.zero);

        expect(provider.userId, 'user-b');
        expect(provider.destination, AuthDestination.ready);

        // A's paused fetch finally resolves — must not overwrite B.
        pauseA.complete();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(provider.userId, 'user-b');
        expect(provider.userType, 'individual');
        expect(provider.destination, AuthDestination.ready);
      },
    );
  });
}
