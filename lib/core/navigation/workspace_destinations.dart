import 'package:flutter/material.dart';

import '../../config/launch_features.dart';
import '../../screens/profile/actions/logout_dialog.dart';
import '../../screens/profile/actions/settings_sheet.dart';
import '../../screens/reels/reels_screen.dart';
import '../constants/app_constants.dart';

/// The single implementation of every Workspace Drawer / More sheet
/// destination.
///
/// Both surfaces offer overlapping destination sets; blueprint §16.3 requires
/// they "reuse the same navigation callbacks, don't reimplement" so the two
/// entry points can never drift apart. Each method takes the [NavigatorState]
/// captured *before* the drawer/sheet closes — the overlay's own context is
/// deactivated once it is dismissed.
class WorkspaceDestinations {
  WorkspaceDestinations._();

  /// Returns to the root of the stack, matching what the bottom bar's Home
  /// tab does.
  static void home(NavigatorState navigator) {
    navigator.popUntil((route) => route.isFirst);
  }

  /// Opens the Feed screen — properties/projects/videos merged, mirroring
  /// the portal's `/feed` (CombinedFeed.tsx). Previously stubbed to Home;
  /// FeedScreen now exists as a real destination.
  static void feed(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.feedScreen);
  }

  /// Reels reuses the bottom bar's guard verbatim.
  ///
  /// Each [ReelsScreen] owns a ReelControllerManager holding up to 3 live
  /// VideoPlayerControllers. Pushing a fresh instance without popping earlier
  /// ones exhausts the Android surface buffer pool and the screen stops
  /// rendering — see the comment in `bottom_nav_bar.dart`. Reusing an existing
  /// instance when one is already in the stack is load-bearing, not an
  /// optimisation.
  static void reels(NavigatorState navigator) {
    bool foundExisting = false;
    navigator.popUntil((route) {
      if (route.settings.name == AppConstants.reelsScreen) {
        foundExisting = true;
        return true;
      }
      return route.isFirst;
    });
    if (!foundExisting) {
      navigator.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: AppConstants.reelsScreen),
          builder: (context) => const ReelsScreen(),
        ),
      );
    }
  }

  /// Resolves to the caller's role-specific dashboard via the dispatcher.
  static void manageDashboard(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.manageDashboardScreen);
  }

  /// The additive Team Workspace destination for an existing user with an
  /// active `builder_team_members` row — the mirror of
  /// `ProfileDashboardShell.tsx`'s nav link. Only shown by the caller when
  /// `AuthProvider.hasTeamMembership` is true; this method itself does no
  /// gating, matching every other destination here.
  static void teamWorkspace(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.teamWorkspaceScreen);
  }

  /// Network — memberships, leads and referrals (Phase 6).
  ///
  /// The drawer and the More sheet share this one destination.
  static void network(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.networkScreen);
  }

  /// Social — the Meta publishing hub (Phase 6).
  static void social(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.socialScreen);
  }

  /// Upgrade — the plan ladder (Phase 6).
  ///
  /// Distinct from "Subscription & Billing", which reviews an existing
  /// subscription across its own tabbed surface — see [subscriptionBilling].
  ///
  /// Defensive guard: every visible caller already hides this destination
  /// when [LaunchFeatures.subscriptions] is off (see `WorkspaceDrawer`/
  /// `MoreBottomSheet`); this no-op is a second line of defence in case
  /// something else ever calls it directly.
  static void upgrade(NavigatorState navigator) {
    if (!LaunchFeatures.subscriptions) return;
    navigator.pushNamed(AppConstants.upgradeScreen);
  }

  /// Subscription & Billing — the read-only billing surface (Phase 7).
  ///
  /// Same defensive guard as [upgrade].
  static void subscriptionBilling(NavigatorState navigator) {
    if (!LaunchFeatures.subscriptions) return;
    navigator.pushNamed(AppConstants.subscriptionBillingScreen);
  }

  /// Messages — the real screen as of Phase 4. Both the drawer and the More
  /// sheet reach it through here.
  static void messages(NavigatorState navigator) {
    navigator.pushNamed(AppConstants.messagesScreen);
  }

  static void settings(BuildContext context) => showSettingsSheet(context);

  static void logout(BuildContext context) => showLogoutDialog(context);
}
