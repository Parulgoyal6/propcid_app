import 'dart:async';

import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/services/auth_service.dart';
import 'package:propcid_app/services/builder_sections_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drives [AuthProvider] with a manually controlled auth-state stream and
/// canned profile rows — no live or locally-initialized Supabase client
/// involved, thanks to [AuthServiceBase] (see `auth_service.dart`). Shared
/// by `auth_provider_test.dart` and `auth_navigation_test.dart` so both
/// exercise the exact same fake behaviour.
class FakeAuthService implements AuthServiceBase {
  final _controller = StreamController<AuthState>.broadcast();

  User? currentUserOverride;
  final Map<String, Map<String, dynamic>?> profilesByUserId = {};
  Object? nextProfileFetchError;
  Completer<void>? pauseNextFetch;
  int logoutCallCount = 0;
  final List<String> profileFetchCalls = [];
  final List<Map<String, String>> upsertCalls = [];
  final List<String> signUpWithEmailCalls = [];
  Object? nextSignUpError;

  // Defaults to true so existing tests that never touch liveness keep
  // working unchanged.
  bool isLiveOverride = true;
  Object? nextIsCurrentUserLiveError;
  final List<String> isCurrentUserLiveCalls = [];

  void emit(AuthState state) => _controller.add(state);
  void emitError(Object error) => _controller.addError(error);
  Future<void> dispose() => _controller.close();

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  @override
  User? get currentUser => currentUserOverride;

  @override
  Session? get currentSession {
    final user = currentUserOverride;
    return user == null ? null : fakeSession(user);
  }

  @override
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    profileFetchCalls.add(userId);
    final pause = pauseNextFetch;
    if (pause != null) {
      pauseNextFetch = null;
      await pause.future;
    }
    final error = nextProfileFetchError;
    if (error != null) {
      nextProfileFetchError = null;
      throw error;
    }
    return profilesByUserId[userId];
  }

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) =>
      throw UnimplementedError('AuthProvider uses fetchProfile, not this.');

  @override
  Future<void> upsertAccountTypeAndName({
    required String userId,
    required String displayName,
    required String userType,
  }) async {
    upsertCalls.add({
      'userId': userId,
      'displayName': displayName,
      'userType': userType,
    });
    final existing = profilesByUserId[userId] ?? <String, dynamic>{};
    profilesByUserId[userId] = {
      ...existing,
      'user_id': userId,
      'display_name': displayName,
      'user_type': userType,
      'profile_complete': false,
    };
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
    currentUserOverride = null;
    emit(AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Future<bool> isCurrentUserLive(String expectedUserId) async {
    isCurrentUserLiveCalls.add(expectedUserId);
    final error = nextIsCurrentUserLiveError;
    if (error != null) {
      nextIsCurrentUserLiveError = null;
      throw error;
    }
    return isLiveOverride;
  }

  @override
  Future<void> requireLiveUser(String expectedUserId) async {
    final isLive = await isCurrentUserLive(expectedUserId);
    if (isLive) return;
    await logout();
    throw 'This account is no longer available. Please sign in again.';
  }

  @override
  Future<void> loginWithIdentifier(String identifier, String password) =>
      throw UnimplementedError();

  /// Set by a test to control the next [login] outcome — `null` (the
  /// default) succeeds; any other value is thrown as-is, mirroring
  /// [AuthService.login]'s own "surface whatever the real failure was"
  /// contract.
  Object? nextLoginError;
  final List<String> loginCalls = [];

  @override
  Future<AuthResponse> login(String email, String password) async {
    loginCalls.add(email);
    final error = nextLoginError;
    if (error != null) {
      nextLoginError = null;
      throw error;
    }
    final user = currentUserOverride;
    return AuthResponse(session: user == null ? null : fakeSession(user));
  }

  @override
  Future<void> sendOtp(String phone) => throw UnimplementedError();
  @override
  Future<void> resendOtp(String phone) => throw UnimplementedError();
  @override
  Future<void> verifyOtp({
    required String phone,
    required String otp,
    String? name,
  }) => throw UnimplementedError();
  @override
  Future<bool> signInWithGoogle() => throw UnimplementedError();
  @override
  Future<void> signUpWithEmail(String email) async {
    signUpWithEmailCalls.add(email);
    final error = nextSignUpError;
    if (error != null) {
      nextSignUpError = null;
      throw error;
    }
  }

  final List<String> passwordResetEmailCalls = [];
  Object? nextSendPasswordResetError;

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    passwordResetEmailCalls.add(email);
    final error = nextSendPasswordResetError;
    if (error != null) {
      nextSendPasswordResetError = null;
      throw error;
    }
  }

  @override
  Future<void> verifyRecoveryToken(String tokenHash) =>
      throw UnimplementedError();

  final List<String> updatePasswordCalls = [];
  Object? nextUpdatePasswordError;

  @override
  Future<UserResponse> updatePassword(String newPassword) async {
    updatePasswordCalls.add(newPassword);
    final error = nextUpdatePasswordError;
    if (error != null) {
      nextUpdatePasswordError = null;
      throw error;
    }
    // The caller only awaits success/failure here — never reads the
    // returned user — so a fixed, valid-shape minimal row is enough.
    return UserResponse.fromJson(<String, dynamic>{
      'id': 'fake-user',
      'aud': 'authenticated',
      'created_at': '2024-01-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    });
  }
}

/// Overrides the two network calls [AuthProvider] makes on every profile
/// fetch so tests never touch a real Supabase client. The `client:` argument
/// avoids `BuilderTeamService`'s default `Supabase.instance.client` fallback
/// — it's stored but never read once these overrides are in place.
class FakeTeamService extends BuilderTeamService {
  FakeTeamService()
    : super(
        client: SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          // Its `auth` is never read (both network methods below are
          // overridden), but GoTrue's auto-refresh timer still starts by
          // default on construction — a `testWidgets` test that drives it
          // far enough to lazily create this client trips flutter_test's
          // "Timer is still pending" invariant at teardown otherwise.
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<BuilderTeamMember>> myActiveMemberships(String userId) async =>
      const [];

  @override
  Future<List<BuilderTeamInvitation>> myPendingInvitations(
    String email,
  ) async => const [];

  @override
  Future<BuilderTeamInvitation?> myPendingPhoneInvitation() async => null;
}

User fakeUser(String id, {String? email}) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2024-01-01T00:00:00Z',
  email: email,
);

Session fakeSession(User user) =>
    Session(accessToken: 'access-$user.id', tokenType: 'bearer', user: user);
