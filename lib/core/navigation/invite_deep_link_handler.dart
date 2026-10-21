import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../providers/auth_provider.dart';
import '../constants/app_constants.dart';
import 'pending_invite_link_store.dart';

/// Resolves `https://propcid.com/accept-invite?invitation=...&token=...` —
/// the link `invite-team-member` actually sends (`index.ts:149`,
/// `redirectTo = "${origin}/accept-invite?invitation=...&token=..."`).
///
/// WHY `invitation`/`token` ARE PRESERVED, NOT JUST THE LINK RECOGNISED
/// -----------------------------------------------------------------------
/// For an EMAIL invite, `PendingInvitationGate`'s own lookup
/// (`AuthProvider.pendingTeamInvitations`, by the signed-in user's verified
/// `profiles.email`) already finds the same invitation — the exact fallback
/// `AcceptInvite.tsx:57-69` itself falls back to when the URL param is
/// missing, so the URL's own values add nothing there.
///
/// A PHONE-OTP invite is different: it has no email at all, and this app's
/// own `myPendingInvitations` has no reliable way to locate one by phone
/// (`builder_team_invitations` RLS only covers the email case — see
/// `BuilderTeamService`'s own doc comments). The link's `invitation`/`token`
/// query params are the ONLY way such an invite is ever found if the
/// invitee's signed-in account doesn't already carry a matching
/// `profiles.phone`, so this handler passes them through as
/// [AppConstants.pendingInvitationScreen]'s route arguments instead of
/// discarding them.
///
/// WHY THIS CAN'T JUST ACCEPT THE INVITE ITSELF
/// ---------------------------------------------
/// `accept-team-invite` requires an authenticated caller
/// (`index.ts:27-38`) — the URL's `invitation`/`token` are business data, not
/// a credential. A brand-new invitee's *browser* gets a session from the
/// Supabase-hosted first hop of this link (`.../auth/v1/verify` redirecting
/// here); this Flutter app's own `SupabaseClient` is a separate storage
/// context that redirect never touches. So for that population, tapping the
/// link on a phone cannot itself complete acceptance in-app — they still
/// need to sign in to the app.
///
/// NOT LOGGED IN YET: PERSISTED, NOT DISCARDED
/// ---------------------------------------------
/// [PendingInviteLinkStore] saves `invitation`/`token` for exactly this
/// case. `PendingInvitationGate` consumes it the moment sign-in completes
/// (whichever identity signs in — same as the portal, which also has no way
/// to confirm the link's recipient is who actually signs in), so the
/// invitee is never required to notice and re-tap the link a second time
/// after finishing sign-in. An *already signed-in* user tapping the link
/// still jumps straight to [AppConstants.pendingInvitationScreen] below,
/// with no store round-trip needed.
class InviteDeepLinkHandler {
  InviteDeepLinkHandler({AuthProvider? authProvider})
    : _authProvider = authProvider;

  final AuthProvider? _authProvider;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Starts listening. Safe to call once, from app start — checks the link
  /// that launched a cold start, then the stream for anything opened while
  /// running.
  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('InviteDeepLinkHandler.start (initial link) failed: $e');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (e) =>
          debugPrint('InviteDeepLinkHandler.uriLinkStream error: $e'),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }

  /// `path` is `/accept-invite` on both platforms once the OS hands the URI
  /// over.
  void _handle(Uri uri) {
    if (!uri.path.contains('accept-invite')) return;

    final invitationId = uri.queryParameters['invitation'];
    final token = uri.queryParameters['token'];

    final authProvider = _authProvider;
    if (authProvider == null || !authProvider.isLoggedIn) {
      // Not logged in yet: nothing this handler does can complete
      // acceptance (see class doc). Persist it — `PendingInvitationGate`
      // picks it up the moment sign-in completes — rather than discard it
      // and force a second tap.
      if (invitationId != null && invitationId.isNotEmpty) {
        unawaited(
          PendingInviteLinkStore.save(invitationId: invitationId, token: token),
        );
      }
      return;
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    final currentRoute = ModalRoute.of(navigator.context)?.settings.name;
    if (currentRoute == AppConstants.pendingInvitationScreen) return;

    navigator.pushNamed(
      AppConstants.pendingInvitationScreen,
      arguments: {'invitationId': invitationId, 'token': token},
    );
  }
}
