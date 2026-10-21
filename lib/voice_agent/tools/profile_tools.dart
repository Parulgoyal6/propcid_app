import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tool_result.dart';
import '../services/intent_stash.dart';
import 'permissions.dart';
import 'registry.dart';

void registerProfileTools() {
  _registerViewMyProfile();
  _registerUpdateProfile();
  _registerOpenMyDashboard();
  _registerOpenManageDashboard();
  _registerShowNotifications();
  _registerShowMyNetwork();
  _registerOpenChat();
  _registerMyVisitBookings();
  _registerPostContent();
  _registerDeleteAccount();
  _registerOpenDashboardAction();
  _registerLogout();
}

// ─── view_my_profile ──────────────────────────────────────────────────────────

void _registerViewMyProfile() {
  toolRegistry.register(
    ToolDefinition(
      name: 'view_my_profile',
      description: 'Navigate to the user\'s profile screen.',
      execute: (params, ctx) async {
        ctx.navigate('/profile');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── update_profile ───────────────────────────────────────────────────────────

void _registerUpdateProfile() {
  toolRegistry.register(
    ToolDefinition(
      name: 'update_profile',
      description: 'Update a profile field and navigate to the profile screen.',
      execute: (params, ctx) async {
        final field = params['field'] as String? ?? '';
        final value = params['value'];

        if (field.isNotEmpty && value != null) {
          IntentStash.set('va_profile_update', {
            'field': field,
            'value': value,
          });
        }

        ctx.navigate('/profile');
        return ToolResult.ok(
          userMessage: field.isNotEmpty
              ? 'Opening your profile to update $field.'
              : 'Opening your profile.',
        );
      },
    ),
  );
}

// ─── open_my_dashboard ────────────────────────────────────────────────────────

void _registerOpenMyDashboard() {
  toolRegistry.register(
    ToolDefinition(
      name: 'open_my_dashboard',
      description: 'Open the user\'s dashboard screen.',
      execute: (params, ctx) async {
        // AppConstants.manageDashboardScreen: the thin ManageDashboardDispatcher
        // that resolves to the correct role screen (builder/broker/influencer/
        // individual/team_member) in one place — the same route the Workspace
        // Drawer, More sheet and Profile screen all push. Was '/profile' — a
        // stale fallback from before this dispatcher existed.
        ctx.navigate('/manage-dashboard');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── open_manage_dashboard ────────────────────────────────────────────────────

void _registerOpenManageDashboard() {
  toolRegistry.register(
    ToolDefinition(
      name: 'open_manage_dashboard',
      description: 'Open the role-specific management dashboard.',
      execute: (params, ctx) async {
        // ManageDashboardDispatcher already performs this exact role switch
        // (and additionally covers 'individual' and 'team_member', which the
        // old hardcoded builder/broker/influencer map here did not), so route
        // there instead of duplicating an incomplete copy of its logic.
        ctx.navigate('/manage-dashboard');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── show_notifications ───────────────────────────────────────────────────────

void _registerShowNotifications() {
  toolRegistry.register(
    ToolDefinition(
      name: 'show_notifications',
      description: 'Navigate to the notifications screen.',
      execute: (params, ctx) async {
        final filter = params['filter'] as String? ?? 'all';
        ctx.navigate('/notifications?filter=$filter');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── show_my_network ──────────────────────────────────────────────────────────

void _registerShowMyNetwork() {
  toolRegistry.register(
    ToolDefinition(
      name: 'show_my_network',
      description: 'Navigate to the network / connections screen.',
      execute: (params, ctx) async {
        // AppConstants.myNetworksScreen (MyNetworksScreen) — "View and manage
        // your network connections", added in Phase 9. Was '/profile' from
        // before this screen existed.
        ctx.navigate('/network/memberships');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── open_chat ────────────────────────────────────────────────────────────────

void _registerOpenChat() {
  toolRegistry.register(
    ToolDefinition(
      name: 'open_chat',
      description: 'Open the chat screen, optionally with a specific user.',
      execute: (params, ctx) async {
        final withUser = params['with_user'] as String?;
        if (withUser != null) {
          IntentStash.set('va_open_chat_with', withUser);
        }
        // AppConstants.messagesScreen (MessagesListScreen) — the dedicated
        // chat/messages screen. Was '/profile' from before it was wired.
        ctx.navigate('/messages');
        return ToolResult.ok(
          userMessage: withUser != null
              ? 'Opening chat with $withUser.'
              : 'Opening chat.',
        );
      },
    ),
  );
}

// ─── my_visit_bookings ────────────────────────────────────────────────────────

void _registerMyVisitBookings() {
  toolRegistry.register(
    ToolDefinition(
      name: 'my_visit_bookings',
      description: 'Navigate to the visit bookings screen.',
      execute: (params, ctx) async {
        final filter = params['filter'] as String? ?? 'all';
        ctx.navigate('/visits?filter=$filter');
        return ToolResult.ok();
      },
    ),
  );
}

// ─── post_content ─────────────────────────────────────────────────────────────

void _registerPostContent() {
  toolRegistry.register(
    ToolDefinition(
      name: 'post_content',
      description: 'Navigate to the appropriate content creation screen.',
      execute: (params, ctx) async {
        final type = params['type'] as String? ?? 'property';

        switch (type) {
          case 'reel':
          case 'video':
            if (!canCreate(CreatableContent.video, ctx.userType)) {
              return ToolResult.fail(
                createDeniedMessage(CreatableContent.video),
                userMessage: createDeniedMessage(CreatableContent.video),
              );
            }
            // Was `/reels` — the consumer feed. An influencer who asked to *post* a
            // video was dropped into a viewer with no way to create one, which is
            // the only branch of this tool that navigated somewhere the user could
            // not do the thing they asked for. There is now a form to send them to.
            ctx.navigate('/influencer-video');
            return ToolResult.ok();

          case 'property':
            if (!canCreate(CreatableContent.property, ctx.userType)) {
              return ToolResult.fail(
                createDeniedMessage(CreatableContent.property),
                userMessage: createDeniedMessage(CreatableContent.property),
              );
            }
            ctx.navigate('/post-property');
            return ToolResult.ok();

          case 'article':
            if (!canCreate(CreatableContent.article, ctx.userType)) {
              return ToolResult.fail(
                createDeniedMessage(CreatableContent.article),
                userMessage: createDeniedMessage(CreatableContent.article),
              );
            }
            ctx.navigate('/profile');
            return ToolResult.ok();

          default:
            ctx.navigate('/post-property');
            return ToolResult.ok();
        }
      },
    ),
  );
}

// ─── delete_account ───────────────────────────────────────────────────────────

void _registerDeleteAccount() {
  toolRegistry.register(
    ToolDefinition(
      name: 'delete_account',
      description: 'Permanently delete the user account.',
      execute: (params, ctx) async {
        // No account is deleted here or on the screen this navigates to —
        // `AccountDeletionScreen` only files a request (an
        // `account_deletion_requests` row for a human to process), the same
        // way the portal's AccountDeletion.tsx does. Signing out first and
        // saying "scheduled for deletion" used to claim a destructive action
        // that never happened; this now performs the one real, non-destructive
        // step available and describes it accurately.
        try {
          await (ctx.signOut?.call() ??
              Supabase.instance.client.auth.signOut());
          ctx.navigate('/account-deletion');
          return ToolResult.ok(
            userMessage:
                'You have been signed out. Please submit your account deletion request on the next screen.',
          );
        } catch (e) {
          return ToolResult.fail(
            e.toString(),
            userMessage: 'Could not sign out. Please try again.',
          );
        }
      },
    ),
  );
}

// ─── open_dashboard_action ────────────────────────────────────────────────────

void _registerOpenDashboardAction() {
  toolRegistry.register(
    ToolDefinition(
      name: 'open_dashboard_action',
      description: 'Open a specific action from the dashboard.',
      execute: (params, ctx) async {
        final action = params['action'] as String? ?? '';
        IntentStash.set('va_dashboard_action', action);

        switch (action) {
          case 'property':
            ctx.navigate('/post-property');
            return ToolResult.ok();
          case 'settings':
            // Settings has no route of its own — `showSettingsSheet()`
            // (screens/profile/actions/settings_sheet.dart) is a modal bottom
            // sheet that needs a BuildContext, and ToolContext.navigate only
            // supports pushNamed(route). Land on Profile, where the real
            // Settings entry point lives, rather than inventing a route.
            ctx.navigate('/profile');
            return ToolResult.ok(
              userMessage: 'Opening your profile — tap Settings from there.',
            );
          default:
            ctx.navigate('/profile');
            return ToolResult.ok();
        }
      },
    ),
  );
}

// ─── logout ───────────────────────────────────────────────────────────────────

void _registerLogout() {
  toolRegistry.register(
    ToolDefinition(
      name: 'logout',
      description: 'Sign the user out.',
      execute: (params, ctx) async {
        try {
          // Canonical AuthProvider.logout() when wired (see ToolContext.signOut)
          // — clears cached identity/pending-type state the same way the
          // logout dialog does. Falls back to a direct sign-out only if some
          // future caller constructs a ToolContext without it.
          await (ctx.signOut?.call() ??
              Supabase.instance.client.auth.signOut());
          ctx.navigate('/auth');
          return ToolResult.ok(userMessage: 'You have been signed out.');
        } catch (e) {
          return ToolResult.fail(
            e.toString(),
            userMessage: 'Could not sign out. Please try again.',
          );
        }
      },
    ),
  );
}
