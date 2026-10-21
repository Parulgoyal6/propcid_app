import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_navigator.dart';
import '../../providers/auth_provider.dart';
import '../constants/app_constants.dart';
import 'pending_invite_link_store.dart';

/// Mobile mirror of the portal's `TeamInviteGate.tsx`.
///
/// That component is mounted globally in `App.tsx`, outside `<Routes>`, and
/// silently redirects a signed-in user with a pending invitation to
/// `/accept-invite`. This widget is mounted the same way — wrapped around
/// every screen via [MaterialApp.builder] in `app.dart` — and does the same
/// thing: it never renders anything of its own.
///
/// Two independent triggers, both signed-in-gated, neither re-entrant:
///
///   * The EMAIL path — watches [AuthProvider.pendingTeamInvitations]
///     (already populated by `AuthProvider._checkTeamStatus`, so this runs
///     no query of its own) and pushes the first time that list is non-empty.
///   * The PHONE-LINK path — consumes [PendingInviteLinkStore] once per
///     sign-in: `InviteDeepLinkHandler` persists a phone-OTP invite's
///     `invitation`/`token` there when the link was tapped signed-out, since
///     the email-based list above has no way to find a phone invite that
///     doesn't match this account's own `profiles.email`/`profiles.phone`.
///
/// "Once" for each is what stands in for `TeamInviteGate`'s own
/// `sessionStorage["propcid_team_invite_checked"]` guard: the closest
/// Flutter analogue of "once per browser session" is once per app run.
/// [_pushed] is shared across both so they can never double-push if a user
/// somehow has both an email invite and a persisted phone link at once —
/// whichever resolves first wins, and the loser's branch simply drops its
/// own result.
class PendingInvitationGate extends StatefulWidget {
  const PendingInvitationGate({required this.child, super.key});

  final Widget child;

  @override
  State<PendingInvitationGate> createState() => _PendingInvitationGateState();
}

class _PendingInvitationGateState extends State<PendingInvitationGate> {
  bool _pushed = false;
  bool _checkedPersistedLink = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!_pushed && auth.isLoggedIn && auth.pendingTeamInvitations.isNotEmpty) {
      // Set synchronously, before the frame callback below even runs, so a
      // second `build()` triggered before that callback fires (e.g. by
      // another provider notifying in the same frame) cannot schedule a
      // second push.
      _pushed = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        appNavigatorKey.currentState?.pushNamed(
          AppConstants.pendingInvitationScreen,
        );
      });
    }

    if (!_checkedPersistedLink && auth.isLoggedIn) {
      // The store read is async and one-time; `_pushed` (checked again
      // inside, after the read resolves) is what actually prevents a double
      // push if the email path above already fired in the meantime.
      _checkedPersistedLink = true;
      _consumePersistedInviteLink();
    }

    return widget.child;
  }

  Future<void> _consumePersistedInviteLink() async {
    final pending = await PendingInviteLinkStore.consume();
    if (pending == null || !mounted || _pushed) return;
    _pushed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.pushNamed(
        AppConstants.pendingInvitationScreen,
        arguments: {
          'invitationId': pending.invitationId,
          'token': pending.token,
        },
      );
    });
  }
}
