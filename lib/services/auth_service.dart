import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/validation/validators.dart';
import 'edge_functions_service.dart';

/// The subset of [AuthService] that [AuthProvider] depends on, extracted so
/// tests can drive `AuthProvider` with a fake implementation — a manually
/// controlled auth-state stream and canned profile rows — without touching a
/// live (or even a locally-initialized) Supabase client. Production code
/// always uses [AuthService] itself; this changes no runtime behaviour.
abstract class AuthServiceBase {
  Stream<AuthState> get onAuthStateChange;
  User? get currentUser;

  /// The session GoTrue currently holds, read directly rather than through
  /// [onAuthStateChange] — see [AuthProvider]'s constructor for why a fresh
  /// subscriber can't always trust that stream's replayed event alone.
  Session? get currentSession;

  Future<void> loginWithIdentifier(String identifier, String password);

  /// A direct `signInWithPassword` re-verification — distinct from
  /// [loginWithIdentifier], which goes through the `username-auth` Edge
  /// Function and replaces the session's tokens via `setSession`. Added
  /// specifically for [ChangePasswordScreen]'s "confirm the current
  /// password" step, where only a success/failure credential check is
  /// wanted, not a new session.
  Future<AuthResponse> login(String email, String password);
  Future<void> sendOtp(String phone);
  Future<void> resendOtp(String phone);
  Future<void> verifyOtp({
    required String phone,
    required String otp,
    String? name,
  });
  Future<bool> signInWithGoogle();
  Future<void> signUpWithEmail(String email);
  Future<void> logout();
  Future<void> sendPasswordResetEmail(String email);
  Future<void> verifyRecoveryToken(String tokenHash);
  Future<UserResponse> updatePassword(String newPassword);
  Future<Map<String, dynamic>?> getUserProfile(String userId);

  /// Like [getUserProfile], but never swallows a fetch failure into `null`
  /// — used exclusively by [AuthProvider] to tell "no profile row"
  /// (`AuthDestination.profileMissing`) apart from "the read itself failed"
  /// (`AuthDestination.profileFetchFailed`), which `getUserProfile`'s
  /// existing swallow-and-log contract (relied on by other, unrelated
  /// callers — team screens, `profile_completion_coordinator.dart`) cannot
  /// distinguish.
  Future<Map<String, dynamic>?> fetchProfile(String userId);

  /// Writes the Full-Name-+-User-Type setup step's result — see
  /// `AccountTypeScreen`. Deliberately narrow: only ever these three
  /// columns, `profile_complete` always `false` (the relevant registration
  /// form is what sets it `true`), and never `user_role` — that stays
  /// whatever it already was, this never writes or promotes it.
  Future<void> upsertAccountTypeAndName({
    required String userId,
    required String displayName,
    required String userType,
  });

  /// True only when [expectedUserId] both matches the locally cached
  /// [currentUser] AND still exists in `auth.users` per
  /// `current_auth_user_is_live()` — a cached JWT can be well-formed and
  /// unexpired for a user an admin already deleted, which `currentUser`
  /// alone cannot detect.
  ///
  /// A temporary RPC/network failure is NOT reported as `false` — it
  /// propagates as a thrown exception so a connectivity blip is never
  /// mistaken for a deleted account. Callers that need "block the write on
  /// any doubt" behaviour should use [requireLiveUser] instead of catching
  /// this method's exceptions themselves.
  Future<bool> isCurrentUserLive(String expectedUserId);

  /// Returns normally when [expectedUserId] is live. Otherwise clears the
  /// local session via the existing [logout] mechanism and throws
  /// `'This account is no longer available. Please sign in again.'`.
  ///
  /// A temporary verification failure (network/RPC error) is never turned
  /// into a sign-out — it propagates as-is so the caller can treat it as a
  /// retryable failure rather than a confirmed-dead account.
  Future<void> requireLiveUser(String expectedUserId);
}

class AuthService implements AuthServiceBase {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EdgeFunctionsService _functions = EdgeFunctionsService();

  /// Stream of Auth State changes
  @override
  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  /// Current active session
  @override
  Session? get currentSession => _supabase.auth.currentSession;

  /// Current active user
  @override
  User? get currentUser => _supabase.auth.currentUser;

  /// Login with email and password
  @override
  Future<AuthResponse> login(String email, String password) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Signs in with an email or username through the `username-auth` Edge
  /// Function and establishes the resulting session locally — mirrors the
  /// portal's `SignIn.tsx` exactly, and never resolves the identifier via
  /// `get_email_by_username`/`get_email_by_phone`: those RPCs are revoked
  /// from `anon`/`authenticated` on the shared backend (they were a free
  /// account-enumeration endpoint — see `username-auth/index.ts`'s header
  /// comment), so calling them here would just fail.
  ///
  /// Phone sign-in is not part of this path — it stays on the OTP flow (see
  /// [verifyOtp]). A phone number typed here is treated like an unknown
  /// username by the edge function and fails with the same generic message,
  /// which matches the portal (its `username-auth` call has no phone branch
  /// either) and this app's own pre-existing behaviour: a phone-originated
  /// account is created with a random password nobody ever knows, so
  /// password sign-in for it could never have succeeded regardless of how
  /// the identifier was resolved.
  @override
  Future<void> loginWithIdentifier(String identifier, String password) async {
    final value = identifier.trim();
    if (value.isEmpty || password.isEmpty) {
      throw 'Please enter your email/username and password.';
    }

    Map<String, dynamic> data;
    try {
      data = await _functions.usernameAuthSignIn(value, password);
    } on EdgeFunctionFailure catch (e) {
      throw AuthService.mapEdgeFunctionFailure(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }

    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw 'Invalid username or password.';
    }

    try {
      // Establishes the session locally from the tokens the edge function
      // already obtained server-side (the email itself never reaches this
      // client) — the normal auth-state listener (AuthProvider) then takes
      // over exactly as it does after any other sign-in.
      await _supabase.auth.setSession(refreshToken, accessToken: accessToken);
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Maps a [EdgeFunctionFailure] from [EdgeFunctionsService.usernameAuthSignIn]
  /// to portal-equivalent copy. The server already sends a good `message` in
  /// almost every case (see `username-auth/index.ts`); this only special-cases
  /// the one code the UI must word differently and fills in a status-based
  /// fallback if the body was ever empty.
  ///
  /// `static` and public (unlike [_mapAuthException]) specifically so tests
  /// can exercise this mapping without constructing an [AuthService] — its
  /// field initializers reach for `Supabase.instance.client`, which is not
  /// available in a plain unit test.
  static String mapEdgeFunctionFailure(EdgeFunctionFailure e) {
    if (e.code == 'email_not_confirmed') {
      return 'Please verify your email before signing in.';
    }
    switch (e.status) {
      case 429:
        return e.message.isNotEmpty
            ? e.message
            : 'Too many attempts. Please try again later.';
      case 503:
        return 'Service temporarily unavailable. Please try again shortly.';
      default:
        return e.message.isNotEmpty
            ? e.message
            : 'A network error occurred. Please try again.';
    }
  }

  /// Email sign-up/sign-in, portal-parity: a magic link, not a password.
  /// Mirrors `SignIn.tsx`'s `handleEmailAuth` exactly —
  /// `signInWithOtp({ email, shouldCreateUser: true, emailRedirectTo })` —
  /// which both creates the account (if new) and signs in (if existing)
  /// with the same call; no name, password, role or type is collected or
  /// stored at this stage. `emailRedirectTo` is the `com.propcid.app://
  /// login-callback` custom-scheme deep link — registered in
  /// `AndroidManifest.xml`/`Info.plist` and already handled by the existing
  /// auth-state listener, so no new native wiring is needed. Google OAuth
  /// below uses a different, https-based redirect — see its own doc.
  @override
  Future<void> signUpWithEmail(String email) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: true,
        emailRedirectTo: kIsWeb
            ? Uri.base.origin
            : 'com.propcid.app://login-callback',
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  // ── Phone OTP (MSG91 via the send-otp edge function) ──────────────────────
  //
  // Supabase's own phone auth is deliberately NOT used: the project's SMS goes
  // through MSG91 inside the edge function, and `otp_verifications` is the
  // store of record on the backend.

  @override
  Future<void> sendOtp(String phone) async {
    try {
      await _functions.sendOtp(Validators.toE164(phone));
    } catch (e) {
      throw e is String ? e : 'A network error occurred. Please try again.';
    }
  }

  @override
  Future<void> resendOtp(String phone) async {
    try {
      await _functions.resendOtp(Validators.toE164(phone));
    } catch (e) {
      throw e is String ? e : 'A network error occurred. Please try again.';
    }
  }

  /// Verifies the code **and establishes the session**.
  ///
  /// Two steps, because the edge function cannot mint a session for a caller
  /// that does not have one yet:
  /// 1. `send-otp` `verify` → checks the OTP, creates the auth user if the
  ///    phone is new, returns `hashed_token` plus `verification_type` — GoTrue's
  ///    own classification of the token it just issued.
  /// 2. `verifyOTP(type: …, tokenHash: …)` → exchanges that token for a
  ///    session, with no browser round-trip.
  ///
  /// `type` must be the exact value GoTrue assigned, not assumed —
  /// `send-otp`'s own header comment: "signup" for a brand-new/unconfirmed
  /// user, "magiclink" only once the user is already confirmed; a hardcoded
  /// `magiclink` fails with a misleading `otp_expired` for any new user,
  /// since the token GoTrue issued for that case is actually type `signup`.
  /// [_otpTypeFrom] falls back to `magiclink` (this method's previous fixed
  /// behaviour) when `verification_type` is absent, for compatibility with
  /// an older deployment of `send-otp` that predates the field.
  @override
  Future<void> verifyOtp({
    required String phone,
    required String otp,
    String? name,
  }) async {
    Map<String, dynamic> data;
    try {
      data = await _functions.verifyOtp(
        phoneNumber: Validators.toE164(phone),
        otp: otp.trim(),
        name: name,
      );
    } catch (e) {
      throw e is String ? e : 'A network error occurred. Please try again.';
    }

    final hashedToken = data['hashed_token'] as String?;
    if (hashedToken == null) {
      throw data['error']?.toString() ?? 'That code could not be verified.';
    }

    try {
      await _supabase.auth.verifyOTP(
        type: otpTypeFromVerificationType(data['verification_type']),
        tokenHash: hashedToken,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Maps `send-otp`'s `verification_type` to the `OtpType` GoTrue's own
  /// `verifyOTP` expects. The only two values that function ever sends
  /// (see its header comment) are `"signup"` and `"magiclink"`; anything
  /// else — including a missing field, from a response predating this
  /// field — falls back to `magiclink`, this method's own prior behaviour.
  @visibleForTesting
  static OtpType otpTypeFromVerificationType(Object? verificationType) =>
      verificationType == 'signup' ? OtpType.signup : OtpType.magiclink;

  /// Google Sign In
  @override
  Future<bool> signInWithGoogle() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? Uri.base.origin
            : 'com.propcid.app://login-callback',
      );

      return true;
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      return false;
    }
  }

  @override
  Future<void> upsertAccountTypeAndName({
    required String userId,
    required String displayName,
    required String userType,
  }) async {
    // A JWT cached from before an admin deleted this account can still look
    // valid locally — the upsert below would otherwise proceed and hit
    // profiles_user_id_fkey. Confirmed live before this identity-owned write.
    await requireLiveUser(userId);

    // `upsert` rather than `update`: this can be the very first profile
    // write for a legacy user with no row yet (AuthDestination.profileMissing
    // routes here too). A plain `.update()` would silently affect zero rows
    // in that case. `onConflict: 'user_id'` still only ever touches these
    // three columns when the row already exists — `user_role` and every
    // other column (avatar_url, work_city, ...) are untouched either way.
    await _supabase.from('profiles').upsert({
      'user_id': userId,
      'display_name': displayName,
      'user_type': userType,
      'profile_complete': false,
    }, onConflict: 'user_id');
  }

  @override
  Future<bool> isCurrentUserLive(String expectedUserId) async {
    final current = _supabase.auth.currentUser;
    if (current == null || current.id != expectedUserId) return false;

    // Deliberately no try/catch here: a network/RPC failure must propagate
    // as an exception, not collapse into `false`, or a connectivity blip
    // would be indistinguishable from a confirmed-deleted account.
    final result = await _supabase.rpc('current_auth_user_is_live');
    return result == true;
  }

  @override
  Future<void> requireLiveUser(String expectedUserId) async {
    final isLive = await isCurrentUserLive(expectedUserId);
    if (isLive) return;

    await logout();
    throw 'This account is no longer available. Please sign in again.';
  }

  /// Update profile with additional fields (for profile completion)
  Future<void> updateProfileFields(
    String userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      await _supabase
          .from('profiles')
          .update(profileData)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Error updating profile fields: $e');
      rethrow;
    }
  }

  /// Logout
  @override
  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  /// Forgot password
  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kIsWeb ? null : 'propcid://reset-password',
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Exchanges a recovery `token_hash` from the reset-password deep link for
  /// a session, which is what makes the subsequent [updatePassword] call
  /// legal. Not needed when `supabase_flutter` has already established the
  /// session itself from the incoming link (the common case).
  @override
  Future<void> verifyRecoveryToken(String tokenHash) async {
    try {
      await _supabase.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: tokenHash,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Update password
  @override
  Future<UserResponse> updatePassword(String newPassword) async {
    try {
      return await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Load profile
  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await _supabase
          .from('profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  /// Same query as [getUserProfile], but lets a fetch failure propagate
  /// instead of swallowing it to `null` — see the interface doc comment for
  /// why [AuthProvider] needs this distinction and `getUserProfile` cannot
  /// be changed to provide it without breaking its other callers.
  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) {
    return _supabase
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  String _mapAuthException(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return 'Incorrect email or password.';
      case 'email_not_confirmed':
        return 'Please verify your email.';
      case 'user_not_found':
        return 'No account found.';
      case 'email_exists':
        return 'Email already registered.';
      case 'weak_password':
        return 'Password must be at least 6 characters.';
      default:
        return e.message;
    }
  }
}
