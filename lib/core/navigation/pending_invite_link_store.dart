// core/navigation/pending_invite_link_store.dart
//
// Persists an `accept-invite` deep link's `invitation`/`token` query
// parameters across a sign-in — the one case `InviteDeepLinkHandler` itself
// cannot complete: a brand-new or signed-out invitee taps the link, there is
// no session yet to push [PendingInvitationScreen] with, and
// `AuthProvider.pendingTeamInvitations`'s own email-based lookup has no way
// to find a phone-OTP invite that doesn't happen to match this account's
// `profiles.email`/`profiles.phone` (see that provider's own doc comment).
// Without this, the invitee would have to notice the link again and tap it
// a second time after finishing sign-in, which most people never do.
//
// A single, local, per-device slot (not a queue) — exactly one invite link
// is ever "in flight" at a time in practice, and [consume] clears it
// immediately so it is used at most once, mirroring the portal's own
// one-time `TeamInviteGate` semantics.
import 'package:shared_preferences/shared_preferences.dart';

class PendingInviteLinkStore {
  PendingInviteLinkStore._();

  static const String _idKey = 'pending_invite_link_id';
  static const String _tokenKey = 'pending_invite_link_token';

  static Future<void> save({
    required String invitationId,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, invitationId);
    if (token != null) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
    }
  }

  /// Reads and clears the stored link in one call, so a second read (e.g. a
  /// later app start with no new link) finds nothing. Returns `null` when
  /// nothing is stored.
  static Future<({String invitationId, String? token})?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    if (id == null || id.isEmpty) return null;
    final token = prefs.getString(_tokenKey);
    await prefs.remove(_idKey);
    await prefs.remove(_tokenKey);
    return (invitationId: id, token: token);
  }
}
