/// Where a just-authenticated (or just-restored) user should land, decided
/// purely from a `profiles` row — no network, no `SharedPreferences`, no
/// side effects. [AuthProvider] is the only caller: it already holds the
/// row (from its own single profile fetch) and is the single owner of the
/// navigation that follows — see `auth_provider.dart`'s `_maybeNavigate`.
///
/// This used to be two independently-fetching, independently-deciding
/// copies (`SplashScreen._navigateToNextScreen` and `auth_post_login.dart`'s
/// `routeAfterAuth`), each doing its own Supabase round-trip and sometimes
/// disagreeing — the root of the "Home, then back to Sign In" class of bug.
/// Collapsing the decision to a pure function of the *one* profile row
/// [AuthProvider] already fetched removes the possibility of two answers
/// for the same identity.
enum AuthDestination {
  /// No Supabase session at all.
  signedOut,

  /// `profiles.is_blocked == true`. The caller must sign the user out and
  /// return to the existing Auth UI — see `AuthProvider.handleBlockedAccount`.
  blocked,

  /// The fetch succeeded (no exception) but returned zero rows — a legacy
  /// authenticated user with no `profiles` row at all. Routed to the same
  /// Full-Name-+-User-Type setup screen as [needsAccountType]: the setup
  /// screen's `upsert(onConflict: 'user_id')` creates the row if it doesn't
  /// exist yet, so this is recoverable rather than a dead end.
  profileMissing,

  /// The profile query itself threw — network failure, expired/invalid JWT,
  /// or any other transport-level error. Deliberately distinct from
  /// [profileMissing]: an authenticated user must never be bounced to Auth
  /// or account-type selection just because this one read failed. The
  /// caller shows a retryable error and does not navigate away from
  /// wherever the user currently is.
  profileFetchFailed,

  /// No `user_type` yet — first sign-in (email confirmation, Google, or
  /// phone OTP) before Full Name + User Type has ever been collected.
  /// Shown via the Full-Name-+-User-Type setup screen (`AccountTypeScreen`).
  needsAccountType,

  /// `user_type == 'individual'` but `profile_complete != true` — routed to
  /// the existing `IndividualProfileDetailsScreen`, the same screen the
  /// setup screen's own "Individual" selection pushes.
  needsIndividualRegistration,

  needsBuilderRegistration,
  needsBrokerRegistration,
  needsInfluencerRegistration,

  /// `profile_complete == true`. Matches the portal's completion rule
  /// exactly (`user_type exists AND profile_complete == true`) — no
  /// per-type exception routes an incomplete profile here.
  ready,
}

abstract final class AuthResolver {
  /// Pure decision table. [profile] is the full `profiles` row already
  /// fetched by the caller, or `null` if the fetch succeeded with zero rows.
  /// Never inspects `SharedPreferences` — a stale locally-cached type must
  /// never influence this decision; the database row is the only input.
  static AuthDestination classify(Map<String, dynamic>? profile) {
    if (profile == null) return AuthDestination.profileMissing;

    if (profile['is_blocked'] == true) return AuthDestination.blocked;

    if (profile['profile_complete'] == true) return AuthDestination.ready;

    final userType = profile['user_type'] as String?;
    if (userType == null) return AuthDestination.needsAccountType;

    switch (userType) {
      case 'builder':
        return AuthDestination.needsBuilderRegistration;
      case 'broker':
        return AuthDestination.needsBrokerRegistration;
      case 'influencer':
        return AuthDestination.needsInfluencerRegistration;
      case 'individual':
        return AuthDestination.needsIndividualRegistration;
      default:
        // No such user_type in practice — conservative fallback matching
        // the pre-existing behaviour for an unrecognised value.
        return AuthDestination.ready;
    }
  }
}
