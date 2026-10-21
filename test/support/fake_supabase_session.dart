import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Establishes a fake signed-in session on the already-initialized
/// `Supabase.instance.client` with no network call — for widget tests of
/// code that reads `Supabase.instance.client.auth.currentUser` directly
/// (registration screens' auth-prefill, `RegistrationDraftStore`'s
/// per-user key) rather than through an injectable interface.
///
/// `GoTrueClient.recoverSession` is a real, public, documented API meant for
/// restoring a persisted session from local storage — it parses the given
/// JSON into a `Session`/`User` and calls its own local `_saveSession`
/// directly. It never calls the network UNLESS the parsed session is
/// expired (see its source: `if (session.isExpired) ... _callRefreshToken`),
/// which is why this omits `expires_at`/`expires_in` entirely — `isExpired`
/// then reads `expiresAt == null` and short-circuits to `false`, so the
/// network branch is never reached. No production code is touched by this;
/// it is a test-only use of an existing SDK entry point.
Future<void> signInFakeUser(String userId, {String? email, String? phone}) async {
  final session = Session(
    accessToken: 'test-access-token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2024-01-01T00:00:00Z',
      email: email,
      phone: phone,
    ),
  );
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode(session.toJson()),
  );
}

/// `signOut()` clears the local session synchronously first (what tests
/// actually need) and only then makes a best-effort server-side revocation
/// call — against the fake local test URL, that call can throw, which this
/// swallows since it has nothing to do with the local state this is for.
Future<void> signOutFakeUser() async {
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // Local session is already cleared by this point — see signOut's source.
  }
}
