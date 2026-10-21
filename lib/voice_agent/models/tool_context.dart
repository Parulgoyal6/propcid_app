class ToolContext {
  final void Function(String route) navigate;
  final String? userId;
  final String? userRole;
  final String? userType;
  final String? displayName;
  final String? profileCity;
  final bool isAdmin;
  final bool isSuperAdmin;

  /// The canonical `AuthProvider.logout()` for whichever tool needs to sign
  /// the user out (e.g. `logout`, `delete_account` in `profile_tools.dart`).
  /// Wired by `VoiceAgentProvider` (it already holds the live `AuthProvider`
  /// instance) so those tools clear cached identity/pending-type state the
  /// same way every other sign-out path does, instead of calling
  /// `Supabase.instance.client.auth.signOut()` directly. Nullable so
  /// existing `ToolContext(...)` call sites that don't need it (tests,
  /// non-auth tools) are unaffected.
  final Future<void> Function()? signOut;

  const ToolContext({
    required this.navigate,
    this.userId,
    this.userRole,
    this.userType,
    this.displayName,
    this.profileCity,
    this.isAdmin = false,
    this.isSuperAdmin = false,
    this.signOut,
  });
}
