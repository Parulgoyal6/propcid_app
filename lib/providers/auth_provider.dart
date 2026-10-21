import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'dart:async';
import '../app_navigator.dart';
import '../models/builder_section_models.dart';
import '../screens/auth/account_type_screen.dart';
import '../screens/auth/individual_profile_details_screen.dart';
import '../screens/home/home_screen.dart';
import '../services/auth_resolver.dart';
import '../services/auth_service.dart';
import '../services/builder_sections_service.dart';
import '../widgets/premium_launch_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _userName = '';
  String _userEmail = '';
  String? _avatarUrl;
  String? _userRole;
  String? _userType;
  String? _userId;
  String? _profileCity;

  /// The full `profiles` row from the most recent fetch.
  ///
  /// Cached so profile-completion can evaluate role-specific fields (phone,
  /// bio, office_address, social_media, ...) without a second query or a
  /// parallel identity provider — see blueprint §10. Read-only.
  Map<String, dynamic>? _profileRow;

  /// This person's own team standing — never the builder-side view.
  ///
  /// Mirrors two separate, additive React mechanisms rather than one
  /// override: `ProfileDashboardShell.tsx:691-708`'s live
  /// `builder_team_members` count (→ [_activeTeamMemberships]/
  /// [hasTeamMembership]) and `TeamInviteGate.tsx`'s pending-invite lookup by
  /// email (→ [_pendingTeamInvitations]). Neither one changes `userType`
  /// routing — that stays exactly as it is until a later phase.
  List<BuilderTeamMember> _activeTeamMemberships = const [];
  List<BuilderTeamInvitation> _pendingTeamInvitations = const [];

  /// The user id [_activeTeamMemberships]/[_pendingTeamInvitations] were last
  /// checked for.
  ///
  /// `_fetchUserProfile()` reruns on every auth event carrying a session —
  /// including `tokenRefreshed`, which fires far more often than the
  /// membership/invitation rows actually change — so this guards the check to
  /// once per signed-in user rather than once per event, the same way
  /// `builder_dashboard_screen.dart`'s `_loadedUserId` guards its analytics
  /// load.
  String? _teamCheckedUserId;

  /// Bumped only on a genuine identity transition: the authenticated user id
  /// actually changing, a real `signedOut`/`userDeleted` event, or an
  /// explicit [logout]. Deliberately **not** bumped for a same-user
  /// `tokenRefreshed`/`userUpdated`/duplicate `signedIn` — see
  /// [_handleAuthState]. Captured by a profile resolution before its async
  /// read and re-checked after it returns: if a newer event has since
  /// bumped this counter, that read is for a superseded identity and must
  /// not overwrite whatever the newer event already established.
  ///
  /// Earlier revisions bumped this on *every* session-carrying event,
  /// including same-user refreshes. A burst of same-user events (observed
  /// on a physical device immediately after an OAuth/magic-link callback —
  /// e.g. `signedIn` followed by a near-simultaneous `tokenRefreshed`) could
  /// then discard an in-flight resolution's own valid result purely because
  /// a second event for the *same* identity had bumped the generation again
  /// before the first one's fetch returned — with no guarantee a later
  /// fetch would still land to publish a destination at all. See
  /// [_inFlightUserId]/[_rerunRequested] for how same-user events are
  /// now coalesced onto the active resolution instead.
  int _authGeneration = 0;

  /// The user id the *current* generation's async work should apply to; null
  /// while signed out. A second guard alongside [_authGeneration] — belt and
  /// suspenders, since generation alone doesn't catch a same-generation race
  /// that shouldn't be possible but costs nothing to also rule out.
  String? _expectedUserId;

  /// The user id a resolution is actively running for, or null if none is in
  /// flight. Keyed by user id rather than a plain flag so that a genuinely
  /// new identity arriving while a stale one is still resolving always gets
  /// its own resolution — only a request for the SAME identity as the one
  /// already running is coalesced (see [_fetchUserProfile]); a different,
  /// newer identity runs concurrently and wins the staleness check in
  /// [_resolveProfileOnce] as before.
  String? _inFlightUserId;

  /// Set by a same-user event that arrived while a resolution for that same
  /// identity was already in flight. Consumed once that resolution
  /// finishes: it runs exactly one more pass before considering itself
  /// done, so whatever the coalesced event was about (e.g. a just-completed
  /// `AccountTypeScreen` write becoming visible) is still reflected, without
  /// ever running two concurrent fetches for the same identity or losing
  /// the eventual destination.
  bool _rerunRequested = false;

  /// Guards [handleBlockedAccount] against running twice concurrently — it
  /// can be reached both from [_fetchUserProfile] (every profile load) and
  /// from a screen that already resolved [AuthDestination.blocked] itself,
  /// and both paths must collapse into one sign-out and one navigation, not
  /// two.
  bool _handlingBlockedAccount = false;
  bool _googleOAuthLaunchInFlight = false;

  /// Guards the `passwordRecovery` navigation the same way — a second
  /// `passwordRecovery` event before the reset screen has changed anything
  /// (e.g. a background token refresh while already on that screen) must not
  /// push it again. Cleared on the next non-recovery event.
  bool _recoveryNavigationPending = false;

  static String? _pendingBlockedMessage;

  /// Matches the portal's `AuthContext.tsx` copy for the same state.
  static const String blockedAccountMessage =
      'Your account has been blocked. Please contact support.';

  /// Consumed once by [AuthScreen] right after a forced blocked-account
  /// sign-out, so it can show the message through the same snackbar every
  /// other auth failure already uses, rather than a new screen.
  static String? consumeBlockedMessage() {
    final message = _pendingBlockedMessage;
    _pendingBlockedMessage = null;
    return message;
  }

  // ── Single owner of post-auth navigation ──────────────────────────────
  //
  // Everything below this point exists so that AuthProvider — not
  // SplashScreen, not AuthScreen's Google listener, not each screen calling
  // a shared helper after its own action succeeds — is the *only* thing
  // that ever decides "where does an authenticated/unauthenticated user go
  // next" and the only thing that ever pushes that decision onto
  // `appNavigatorKey`. Two independent deciders (each doing its own
  // profile fetch) was the root of the "Home, then back to Sign In" class
  // of bug: they could resolve at different times against different data.

  /// The resolved destination for the current identity, or null while still
  /// resolving (a session-carrying event has arrived but its profile fetch
  /// hasn't landed yet) or while genuinely signed out with nothing to
  /// resolve. Recomputed by [_fetchUserProfile] from the one profile row it
  /// already fetches — see [AuthResolver.classify].
  AuthDestination? _destination;
  AuthDestination? get destination => _destination;

  /// True from the moment a session-carrying event arrives until
  /// [_destination] is computed. `SplashScreen`'s looping animation is the
  /// de-facto loader for this state — nothing else needs to render
  /// differently for it, it just means "don't navigate yet".
  bool _isResolving = true;
  bool get isResolving => _isResolving;

  /// False until `SplashScreen` calls [enableNavigation] (after confirming
  /// onboarding was already seen — onboarding must win over any auth
  /// destination on a genuinely first launch). Once true, it stays true for
  /// the rest of the process: every later destination change (login,
  /// signup, Google, OTP, logout, blocked) navigates automatically from here
  /// on, which is what lets every one of those call sites stop calling
  /// `Navigator` themselves.
  bool _navigationEnabled = false;

  /// `'$destination:$userId:$generation'` for the last destination this
  /// provider actually **executed** a Navigator operation for — de-dupes
  /// repeat notifications (e.g. `tokenRefreshed` re-running profile
  /// resolution with an unchanged result) so the same screen isn't pushed
  /// twice, while still navigating again for a genuinely new destination, a
  /// different user, or a new generation (sign-out then a fresh sign-in as
  /// the same user must not be treated as "the same" navigation as before —
  /// see [_handleAuthState]'s generation bump on sign-out/identity change).
  String? _lastNavigatedKey;

  /// Called once by `SplashScreen` after its animation and onboarding check.
  /// If a destination is already known by then (common — the auth stream is
  /// a `BehaviorSubject` that starts resolving from the moment this provider
  /// is constructed in `main()`, well before Splash's animation finishes),
  /// this navigates immediately; otherwise navigation happens as soon as
  /// [_fetchUserProfile] lands.
  void enableNavigation() {
    if (_navigationEnabled) return;
    _navigationEnabled = true;
    if (_destination != null) {
      _maybeNavigate(_destination!, _userId);
    }
  }

  /// Requests navigation to [destination]. Never marks it as "done" until a
  /// live [NavigatorState] actually receives the call — if
  /// `appNavigatorKey.currentState` is momentarily null (not yet attached),
  /// the request is retried after the next frame instead of being silently
  /// dropped, which previously let a resolved destination go un-navigated
  /// forever if the very first attempt landed before the Navigator existed.
  void _maybeNavigate(AuthDestination destination, String? userId) {
    if (!_navigationEnabled) return;
    final key = '$destination:$userId:$_authGeneration';
    if (key == _lastNavigatedKey) return;

    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      _logFlow(
        'navigate dest=$destination user=${_shortId(userId)} gen=$_authGeneration '
        '-> navigator not ready, scheduling post-frame retry',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeNavigate(destination, userId);
      });
      return;
    }

    // Recorded only now — immediately before the Navigator call actually
    // executes — never before it's known this attempt will really happen.
    _lastNavigatedKey = key;
    _logFlow(
      'navigate dest=$destination user=${_shortId(userId)} gen=$_authGeneration -> executing',
    );
    _performNavigation(destination, userId);
  }

  void _performNavigation(AuthDestination destination, String? userId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    switch (destination) {
      case AuthDestination.signedOut:
        nav.pushNamedAndRemoveUntil('/auth', (route) => false);
        return;

      case AuthDestination.blocked:
        // Handled by handleBlockedAccount itself, which also performs the
        // sign-out this destination implies — nothing to do here.
        return;

      case AuthDestination.profileFetchFailed:
        // Retryable — never move the user to Auth or Home just because one
        // read failed. Whatever screen is showing stays showing.
        return;

      case AuthDestination.profileMissing:
      case AuthDestination.needsAccountType:
        if (userId == null) return;
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => AccountTypeScreen(userId: userId)),
          (route) => false,
        );
        return;

      case AuthDestination.needsIndividualRegistration:
        if (userId == null) return;
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => IndividualProfileDetailsScreen(userId: userId),
          ),
          (route) => false,
        );
        return;

      case AuthDestination.needsBuilderRegistration:
        nav.pushNamedAndRemoveUntil('/builder-profile', (route) => false);
        return;

      case AuthDestination.needsBrokerRegistration:
        nav.pushNamedAndRemoveUntil('/broker-profile', (route) => false);
        return;

      case AuthDestination.needsInfluencerRegistration:
        nav.pushNamedAndRemoveUntil('/influencer-profile', (route) => false);
        return;

      case AuthDestination.ready:
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        return;
    }
  }

  final AuthServiceBase _authService;
  final BuilderTeamService _teamService;
  StreamSubscription<AuthState>? _authSub;

  /// [authService]/[teamService] are injectable so tests can drive
  /// [_handleAuthState] and [_fetchUserProfile] with a fake stream instead of
  /// a live Supabase client — production code always uses the defaults.
  AuthProvider({AuthServiceBase? authService, BuilderTeamService? teamService})
    : _authService = authService ?? AuthService(),
      _teamService = teamService ?? BuilderTeamService() {
    _authSub = _authService.onAuthStateChange.listen(
      _handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        // The underlying failure (a token refresh or network hiccup) is
        // already logged by gotrue before it reaches this stream. Clearing
        // identity here would turn a transient stream error into a forced
        // sign-out, which is worse than keeping the last-known-good state —
        // so this only needs to stop it becoming an unhandled zone error.
        debugPrint('[AuthProvider] auth stream error: $error');

        // `onAuthStateChange` is a BehaviorSubject: a subscriber only ever
        // replays the single MOST RECENT event, not every event emitted
        // before it subscribed. This provider is constructed (and subscribes
        // here) only after `Supabase.initialize()` has already returned in
        // `main()` — and that call can itself emit two events synchronously
        // before anything here ever sees them: the cold-start
        // `initialSession` (with whatever session actually exists), followed
        // immediately by an error if a deep link it processed in the same
        // call failed (e.g. a post-signup confirmation link opened somewhere
        // the PKCE `code_verifier` it needs was never stored — "Code
        // verifier could not be found in local storage."). When both fire in
        // that order, this subscription's first-ever delivery is the error,
        // and the preceding `initialSession` is dropped forever — leaving
        // `_destination` stuck at null and the app parked on whatever screen
        // was already showing (no crash, but no way forward either).
        //
        // Recover by re-deriving that dropped state directly from the auth
        // client's actual current session rather than trusting the stream
        // alone. `_handleAuthState` already coalesces a redundant/duplicate
        // event safely (see its own comments), so this is a no-op on top of
        // whatever the stream did separately manage to deliver.
        _handleAuthState(
          AuthState(
            AuthChangeEvent.initialSession,
            _authService.currentSession,
          ),
        );
      },
    );
  }

  /// Debug-only structured tracing for the auth event → resolution →
  /// navigation pipeline, added to diagnose a live-callback race a physical
  /// device reproduced (a burst of same-user events losing the eventual
  /// destination) — see the generation/coalescing comments above. Never
  /// logs a token, code, password, OTP, email, or phone number; only event
  /// names, a shortened user id, counters/flags, and classified state.
  /// No-ops outside debug builds.
  void _logFlow(String message) {
    if (kDebugMode) {
      debugPrint('[AUTH_FLOW] $message');
    }
  }

  /// First 8 characters of a user id for log correlation without printing
  /// anything that identifies the person on its own (not an email/phone).
  String _shortId(String? id) {
    if (id == null) return 'null';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  void _handleAuthState(AuthState state) {
    // A recovery-link deep link establishes a session before the user has
    // set a new password — jump straight to the reset screen regardless of
    // what's currently on screen (including a cold start). Guarded so a
    // second recovery-flavoured event (e.g. a refresh while already on that
    // screen) doesn't push it twice. Deliberately outside the destination
    // machinery below: recovery is its own flow, not a routing destination.
    if (state.event == AuthChangeEvent.passwordRecovery) {
      _logFlow('event=passwordRecovery hasSession=${state.session != null}');
      if (!_recoveryNavigationPending) {
        _recoveryNavigationPending = true;
        appNavigatorKey.currentState?.pushNamed('/reset-password');
      }
      return;
    }
    _recoveryNavigationPending = false;

    if (state.session == null) {
      // A real sign-out/deletion — always a genuine identity transition, so
      // this is the one case (alongside a new user id below and explicit
      // [logout]) that bumps the generation and resets navigation dedupe.
      _logFlow('event=${state.event.name} session=null -> signedOut');
      // So the PropCID Pro launch-offer sheet shows again on the user's next
      // successful login instead of staying suppressed for the rest of this
      // app run — it must fire on every login, not just once per app launch.
      LaunchOfferSessionGate.resetForNewLogin();
      _authGeneration++;
      _inFlightUserId = null;
      _rerunRequested = false;
      _lastNavigatedKey = null;
      _expectedUserId = null;
      _isLoggedIn = false;
      _isResolving = false;
      _destination = AuthDestination.signedOut;
      _userName = '';
      _userEmail = '';
      _avatarUrl = null;
      _userRole = null;
      _userType = null;
      _userId = null;
      _profileCity = null;
      _profileRow = null;
      _teamCheckedUserId = null;
      _activeTeamMemberships = const [];
      _pendingTeamInvitations = const [];
      notifyListeners();
      _maybeNavigate(AuthDestination.signedOut, null);
      return;
    }

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      // A session exists but gotrue hasn't surfaced a user for it yet —
      // nothing to resolve until a later event carries one.
      _logFlow(
        'event=${state.event.name} session!=null but currentUser=null -> ignored',
      );
      return;
    }

    final isNewIdentity = _expectedUserId != currentUser.id;

    _isLoggedIn = true;
    _expectedUserId = currentUser.id;

    // Set synchronously from the session the auth SDK already has, rather
    // than waiting on the async `profiles` round-trip below. `currentUser.id`
    // never changes once a session exists — unlike _userRole/_userType/
    // _profileCity, it needs no DB read to be correct. Previously this only
    // got set deep inside profile resolution after that call succeeded, so
    // isLoggedIn could read true while userId was still null for the length
    // of that round-trip (or forever, if the fetch failed) — exactly the
    // window a screen that gates a write on `userId != null` (e.g. Post
    // Property's publish check) could lose to, most visibly right after an
    // OAuth redirect where the user taps the primary action before the
    // profile fetch has had a chance to land.
    _userName = currentUser.userMetadata?['display_name'] ?? '';
    _userEmail = currentUser.email ?? '';
    _userId = currentUser.id;

    _logFlow(
      'event=${state.event.name} user=${_shortId(currentUser.id)} '
      'newIdentity=$isNewIdentity gen=$_authGeneration inFlightFor=${_shortId(_inFlightUserId)}',
    );

    if (isNewIdentity) {
      // A genuine identity transition — start a fresh generation. Any
      // resolution still in flight for the OLD identity is superseded and
      // its result will be discarded by the staleness check when it lands.
      _authGeneration++;
      _rerunRequested = false;
      _isResolving = true;
      final generation = _authGeneration;
      notifyListeners();
      _fetchUserProfile(expectedUserId: currentUser.id, generation: generation);
      return;
    }

    // Same user re-firing — duplicate `signedIn`, `tokenRefreshed`,
    // `userUpdated`, or another `initialSession` for a session already
    // being resolved. The generation is deliberately NOT bumped here: doing
    // so on every same-user event (the previous behaviour) meant a burst of
    // these — observed on a physical device immediately after an OAuth/
    // magic-link callback — could keep invalidating an in-flight
    // resolution's own valid result before any fetch ever got a chance to
    // land against a still-current generation, so no destination was ever
    // published and no navigation occurred. _isResolving/_destination are
    // left exactly as they are until whichever fetch runs lands, so a mere
    // refresh can never be observed as a transient `ready`, `signedOut`, or
    // unresolved state. Whether this starts a fresh fetch or coalesces onto
    // one already running for this identity is [_fetchUserProfile]'s call.
    notifyListeners();
    _fetchUserProfile(
      expectedUserId: currentUser.id,
      generation: _authGeneration,
    );
  }

  /// Coalescing wrapper around [_resolveProfileOnce]: guarantees at most one
  /// resolution runs at a time *per identity* — a request for the same
  /// identity as one already in flight is coalesced onto it (queues exactly
  /// one rerun after it finishes) instead of racing a second concurrent
  /// fetch or being dropped. A request for a genuinely different identity
  /// always runs (concurrently, if an old one is still winding down); the
  /// staleness check in [_resolveProfileOnce] still ensures only the
  /// current identity's result is ever applied.
  Future<void> _fetchUserProfile({
    required String expectedUserId,
    required int generation,
  }) async {
    if (_inFlightUserId == expectedUserId) {
      _rerunRequested = true;
      _logFlow(
        'fetchUserProfile user=${_shortId(expectedUserId)} -> resolution already in '
        'flight for this identity, coalesced (rerun queued)',
      );
      return;
    }

    _inFlightUserId = expectedUserId;
    try {
      await _resolveProfileOnce(
        expectedUserId: expectedUserId,
        generation: generation,
      );

      while (_rerunRequested &&
          generation == _authGeneration &&
          _expectedUserId == expectedUserId) {
        _rerunRequested = false;
        _logFlow('coalesced rerun starting for ${_shortId(expectedUserId)}');
        await _resolveProfileOnce(
          expectedUserId: expectedUserId,
          generation: generation,
        );
      }
    } finally {
      if (_inFlightUserId == expectedUserId) {
        _inFlightUserId = null;
      }
    }
  }

  Future<void> _resolveProfileOnce({
    required String expectedUserId,
    required int generation,
  }) async {
    _logFlow('resolve-start user=${_shortId(expectedUserId)} gen=$generation');

    // A JWT cached from before an admin deleted this account can still look
    // valid locally. Without this check, fetchProfile below would simply
    // find no row and get misclassified as AuthDestination.profileMissing —
    // routing a dead account into the registration flow instead of signing
    // it out. Checked first, before the profile fetch, so that
    // misclassification can never happen.
    bool isLive;
    try {
      isLive = await _authService.isCurrentUserLive(expectedUserId);
    } catch (e) {
      // Verification itself failed to complete (network/RPC error) — this is
      // NOT evidence the account is dead. Retain the current identity and
      // fall back to the same retryable profileFetchFailed state a failed
      // profile fetch already produces below, rather than signing out.
      if (generation != _authGeneration || _expectedUserId != expectedUserId) {
        _logFlow(
          'resolve-end user=${_shortId(expectedUserId)} gen=$generation -> STALE '
          '(liveness check), discarded',
        );
        return;
      }
      debugPrint('Error verifying live auth user: $e');
      _logFlow(
        'resolve-end user=${_shortId(expectedUserId)} -> liveness check failed '
        '(connectivity), destination=profileFetchFailed',
      );
      _isResolving = false;
      _destination = AuthDestination.profileFetchFailed;
      notifyListeners();
      _maybeNavigate(AuthDestination.profileFetchFailed, expectedUserId);
      return;
    }

    if (!isLive) {
      // Same staleness re-check as every other async gap in this method: a
      // newer auth event may have already superseded this resolution while
      // the liveness RPC was in flight.
      if (generation != _authGeneration || _expectedUserId != expectedUserId) {
        _logFlow(
          'resolve-end user=${_shortId(expectedUserId)} gen=$generation -> STALE '
          '(liveness check), discarded',
        );
        return;
      }
      _logFlow(
        'resolve-end user=${_shortId(expectedUserId)} -> not live, signing out',
      );
      await logout();
      return;
    }

    Map<String, dynamic>? profile;
    Object? fetchError;
    try {
      profile = await _authService.fetchProfile(expectedUserId);
    } catch (e) {
      fetchError = e;
    }

    // Stale by the time this returns — a newer auth event (sign-out, or a
    // sign-in as someone else) already superseded it. Applying it now
    // would resurrect the wrong identity's role/type/avatar over whatever
    // the newer event already established, which is exactly how a second
    // account's data used to leak into the first account's cached fields
    // across a fast sign-out → sign-in-as-someone-else sequence.
    if (generation != _authGeneration || _expectedUserId != expectedUserId) {
      _logFlow(
        'resolve-end user=${_shortId(expectedUserId)} gen=$generation -> STALE, discarded '
        '(currentGen=$_authGeneration expectedUserNow=${_shortId(_expectedUserId)})',
      );
      return;
    }
    if (_authService.currentUser?.id != expectedUserId) {
      _logFlow(
        'resolve-end user=${_shortId(expectedUserId)} -> currentUser mismatch, discarded',
      );
      return;
    }

    if (fetchError != null) {
      debugPrint('Error fetching user profile: $fetchError');
      _logFlow(
        'resolve-end user=${_shortId(expectedUserId)} -> fetch error, destination=profileFetchFailed',
      );
      _isResolving = false;
      _destination = AuthDestination.profileFetchFailed;
      notifyListeners();
      _maybeNavigate(AuthDestination.profileFetchFailed, expectedUserId);
      return;
    }

    final resolved = AuthResolver.classify(profile);
    _logFlow(
      'resolve-end user=${_shortId(expectedUserId)} profilePresent=${profile != null} '
      'userType=${profile?['user_type']} profileComplete=${profile?['profile_complete']} '
      'destination=$resolved',
    );

    if (resolved == AuthDestination.blocked) {
      // handleBlockedAccount() (via logout()) sets _isResolving/_destination
      // itself and navigates — nothing more to do in this branch.
      await handleBlockedAccount();
      return;
    }

    _isResolving = false;
    _destination = resolved;

    if (profile != null) {
      _userName = profile['display_name'] ?? _userName;

      _userEmail = profile['email'] ?? _userEmail;

      _avatarUrl = profile['avatar_url'];

      _userRole = profile['user_role'];

      _userType = profile['user_type'];
      _userId = expectedUserId;
      _profileCity = profile['work_city'];
      _profileRow = Map<String, dynamic>.from(profile);
    }

    notifyListeners();
    _maybeNavigate(resolved, expectedUserId);

    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      await _checkTeamStatus(currentUser);
    }
  }

  /// Signs out, clears every identity-scoped field (via [logout]), shows the
  /// existing blocked-account message the next time the Auth screen builds,
  /// and forces navigation back to it — reachable both from a background
  /// profile load ([_fetchUserProfile]) and from a screen that already
  /// resolved `AuthDestination.blocked` itself. The guard makes concurrent
  /// callers collapse into a single sign-out/navigation.
  Future<void> handleBlockedAccount() async {
    if (_handlingBlockedAccount) return;
    _handlingBlockedAccount = true;
    try {
      await logout();
      _pendingBlockedMessage = blockedAccountMessage;
      appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/auth',
        (route) => false,
      );
    } finally {
      _handlingBlockedAccount = false;
    }
  }

  /// This person's own active memberships and pending invitations —
  /// deliberately separate from [_fetchUserProfile]'s `profiles` read, since
  /// neither table is scoped by `builder_id` the way the builder-side
  /// `BuilderTeamService` calls are (`myActiveMemberships`/
  /// `myPendingInvitations` query by `member_user_id`/`email` instead — see
  /// `builder_sections_service.dart`).
  ///
  /// Also checks [BuilderTeamService.myPendingPhoneInvitation] — the
  /// email-only table query above has no way to find a phone-OTP invite
  /// that matches this account's own `profiles.phone` instead of its email,
  /// so without this, a phone invite is only ever discovered by tapping its
  /// link (see `PendingInviteLinkStore`). Merged by id so an invite somehow
  /// reachable both ways (e.g. the invitee later added the same email) is
  /// never listed twice; the phone-only result stays minimal (no builder
  /// name/modules — see that method's own doc comment) unless the
  /// email-based query already found the same id with full detail.
  ///
  /// Read-only: never accepts an invitation, never writes `user_type`, never
  /// navigates. Guarded by [_teamCheckedUserId] so a `tokenRefreshed` event
  /// for the same user doesn't re-run it; a genuine failure is swallowed the
  /// same way, rather than retried on every subsequent refresh, so this
  /// cannot become another contributor to a refresh loop.
  Future<void> _checkTeamStatus(User user) async {
    if (_teamCheckedUserId == user.id) return;
    _teamCheckedUserId = user.id;

    try {
      final memberships = await _teamService.myActiveMemberships(user.id);

      final email = user.email;
      final invitations = (email == null || email.isEmpty)
          ? const <BuilderTeamInvitation>[]
          : await _teamService.myPendingInvitations(email);

      final phoneInvite = await _teamService.myPendingPhoneInvitation();

      _activeTeamMemberships = memberships;
      _pendingTeamInvitations = [
        ...invitations,
        if (phoneInvite != null &&
            !invitations.any((i) => i.id == phoneInvite.id))
          phoneInvite,
      ];

      notifyListeners();
    } catch (e) {
      debugPrint('Error checking team status: $e');
    }
  }

  /// Re-runs [_checkTeamStatus] regardless of [_teamCheckedUserId].
  ///
  /// For a caller that just changed the underlying rows itself — right now
  /// only the pending-invitation screen, after `acceptInvite` succeeds — and
  /// needs this cache to reflect that immediately rather than waiting for
  /// the next auth event. This is a single deliberate, user-triggered
  /// refresh, not a poll, so it doesn't reintroduce the every-event-reruns-it
  /// problem [_teamCheckedUserId] guards against elsewhere.
  Future<void> refreshTeamStatus() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    _teamCheckedUserId = null;
    await _checkTeamStatus(currentUser);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String get userEmail => _userEmail;
  String? get avatarUrl => _avatarUrl;
  String? get userRole => _userRole;
  String? get userType => _userType;
  String? get userId => _userId;
  String? get profileCity => _profileCity;

  /// `profiles.background_image_url`, written by
  /// `EditProfileProvider.pickAndUploadCover`. Read from the cached row rather
  /// than a dedicated field so a fresh [refreshProfile] call after upload is
  /// enough to surface it — no separate cache-invalidation path needed.
  String? get backgroundImageUrl =>
      _profileRow?['background_image_url'] as String?;

  /// Unmodifiable view of the cached `profiles` row, or null before the first
  /// successful fetch.
  Map<String, dynamic>? get profileRow => _profileRow == null
      ? null
      : Map<String, dynamic>.unmodifiable(_profileRow!);

  /// True once at least one active `builder_team_members` row has been found
  /// for this person, across any builder. Additive information only — does
  /// not change [userType] or where this app routes them.
  bool get hasTeamMembership => _activeTeamMemberships.isNotEmpty;

  /// This person's own active memberships, across every builder they've
  /// joined. Empty before the first check completes or if there are none.
  List<BuilderTeamMember> get activeTeamMemberships =>
      List.unmodifiable(_activeTeamMemberships);

  /// This person's own pending invitations, across every builder that has
  /// invited them. Empty before the first check completes or if there are
  /// none.
  List<BuilderTeamInvitation> get pendingTeamInvitations =>
      List.unmodifiable(_pendingTeamInvitations);

  /// Accepts an email or username — [AuthService] signs in through the
  /// `username-auth` Edge Function, which resolves whichever was typed
  /// server-side. Phone sign-in is a separate flow (see [sendOtp]/
  /// [verifyOtp]). Returns an error string, or null on success — on success,
  /// this provider's own auth-stream listener resolves the destination and
  /// navigates; the caller does not need to (and must not) do so itself.
  Future<String?> login(String identifier, String password) async {
    if (identifier.trim().isEmpty || password.isEmpty) {
      return 'Please fill in all fields';
    }

    try {
      await _authService.loginWithIdentifier(identifier.trim(), password);

      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Sends a 6-digit SMS code to [phone]. Returns an error string, or null on
  /// success.
  Future<String?> sendOtp(String phone) async {
    try {
      await _authService.sendOtp(phone);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> resendOtp(String phone) async {
    try {
      await _authService.resendOtp(phone);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Verifies the code and establishes the session. Returns an error string,
  /// or null on success — the auth-state listener above then populates
  /// [isLoggedIn]/the profile fields and navigates.
  Future<String?> verifyOtp({
    required String phone,
    required String otp,
    String? name,
  }) async {
    try {
      await _authService.verifyOtp(phone: phone, otp: otp, name: name);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Exchanges a recovery `token_hash` from the reset-password deep link for
  /// a session. Returns an error string, or null on success.
  Future<String?> verifyRecoveryToken(String tokenHash) async {
    try {
      await _authService.verifyRecoveryToken(tokenHash);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updatePassword(String newPassword) async {
    try {
      await _authService.updatePassword(newPassword);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Portal-parity email sign-up: collects only an email address and sends a
  /// magic link (`signInWithOtp(shouldCreateUser: true)`) — no name,
  /// password, role or type here. Returns an error string, or null once the
  /// link has been sent (not once a session exists — that only happens
  /// later, when the link is tapped, entirely independently of this call).
  Future<String?> signUpWithEmail(String email) async {
    if (email.trim().isEmpty) {
      return 'Please enter your email address.';
    }
    try {
      await _authService.signUpWithEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Initiates Google OAuth. Returns null on success (browser opened),
  /// or an error string if the flow could not be started.
  /// The actual session arrives later via the auth state stream, which this
  /// provider's own listener reacts to — the caller does not navigate.
  Future<String?> signInWithGoogle() async {
    // Never restart OAuth when the user is already authenticated.
    if (_authService.currentUser != null) {
      debugPrint('[GOOGLE_OAUTH] Ignored: session already exists');
      return null;
    }

    // Prevent two Google browser/account-chooser launches at the same time.
    if (_googleOAuthLaunchInFlight) {
      debugPrint('[GOOGLE_OAUTH] Ignored: launch already in progress');
      return null;
    }

    _googleOAuthLaunchInFlight = true;

    try {
      debugPrint('[GOOGLE_OAUTH] Launching Google OAuth');

      final success = await _authService.signInWithGoogle();

      if (!success) {
        return 'Could not open Google Sign In. Please try again.';
      }

      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _googleOAuthLaunchInFlight = false;
    }
  }

  /// The Full-Name-+-User-Type setup step (`AccountTypeScreen`), reached
  /// whenever [destination] is [AuthDestination.needsAccountType] or
  /// [AuthDestination.profileMissing]. Validates a real session, a
  /// non-blank name, and one of the four allowed types; writes exactly
  /// `user_id`/`display_name`/`user_type`/`profile_complete: false` (never
  /// `user_role`); then refreshes so this provider's own destination
  /// recomputes and navigates to the matching registration screen. Returns
  /// an error string on any failure — the caller stays on the setup screen
  /// and shows it; nothing is marked complete and Home is never reached.
  Future<String?> completeAccountSetup({
    required String fullName,
    required String userType,
  }) async {
    const allowedTypes = {'individual', 'builder', 'broker', 'influencer'};

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      return 'Your session has expired. Please sign in again.';
    }
    if (!allowedTypes.contains(userType)) {
      return 'Please select a valid account type.';
    }
    final name = fullName.trim();
    if (name.isEmpty) {
      return 'Please enter your full name.';
    }

    try {
      await _authService.upsertAccountTypeAndName(
        userId: currentUser.id,
        displayName: name,
        userType: userType,
      );
    } catch (e) {
      return e.toString();
    }

    await refreshProfile();
    return null;
  }

  /// The single canonical sign-out path — every logout entry point (the
  /// logout dialog, a blocked-account force sign-out, account switching)
  /// must call this rather than `Supabase.instance.client.auth.signOut()`
  /// directly, or the fields cleared below stay stale under the new identity
  /// (or lack of one). Also performs the navigation back to Auth itself,
  /// rather than waiting for the corresponding `signedOut` stream event —
  /// callers must not additionally navigate after this returns.
  Future<void> logout() async {
    // Invalidated first, synchronously, so any profile fetch already in
    // flight for the outgoing user is rejected by _resolveProfileOnce's
    // generation/expectedUserId check even if it resolves before the
    // corresponding `signedOut` stream event arrives. _rerunRequested is
    // also cleared so a coalesced same-user rerun queued just before this
    // logout doesn't fire for an identity that no longer applies, and
    // _lastNavigatedKey is cleared so signing back in later — including as
    // the same user — is never deduped against a destination from before
    // this sign-out.
    _authGeneration++;
    _expectedUserId = null;
    _inFlightUserId = null;
    _rerunRequested = false;
    _lastNavigatedKey = null;

    await _authService.logout();

    // `pending_user_type`/`pending_user_type_uid` are no longer written by
    // any live code path (the Full-Name-+-User-Type setup screen writes
    // straight to the database instead — see `completeAccountSetup`), but
    // this clears any value still left over from before that change, or
    // from a very old install, so it can never be read as if it meant
    // something for whoever signs in next.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_user_type');
    await prefs.remove('pending_user_type_uid');

    _isLoggedIn = false;
    _isResolving = false;
    _destination = AuthDestination.signedOut;
    _userName = '';
    _userEmail = '';
    _avatarUrl = null;
    _userRole = null;
    _userType = null;
    _userId = null;
    _profileCity = null;
    _profileRow = null;
    _teamCheckedUserId = null;
    _activeTeamMemberships = const [];
    _pendingTeamInvitations = const [];

    notifyListeners();
    _maybeNavigate(AuthDestination.signedOut, null);
  }

  /// Re-reads the profiles row from Supabase and updates all cached fields
  /// (and, via the same path `_fetchUserProfile` always uses, re-resolves
  /// and navigates to whatever destination that row now implies). Call this
  /// after any external write to the profiles table (e.g. after a
  /// registration screen saves its data) so the provider reflects DB state.
  Future<void> refreshProfile() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;
    await _fetchUserProfile(
      expectedUserId: currentUser.id,
      generation: _authGeneration,
    );
  }

  void updateProfile(String name, String email) {
    _userName = name.trim();
    _userEmail = email.trim();

    notifyListeners();
  }
}
