// core/navigation/notification_route_resolver.dart
//
// Where tapping a notification goes — G-4.
//
// A transcription of `NotificationList.tsx:53-115`'s switch, which is the portal's
// only routing contract for notifications. Kept as a pure function returning a
// destination rather than as `Navigator` calls inside the list, so the whole table is
// testable without pumping a widget.
//
// THE IMPORTANT CONSTRAINT: MOST PAYLOADS CARRY NO ID
// ---------------------------------------------------
// `utils/notificationHelpers.ts` writes display strings, not identifiers. Its
// payloads are:
//
//   new_follower              { follower_name }                      ← no id
//   channel_addition          { channel_name, added_by }             ← no id
//   builder_network_addition  { sender_name, member_type }           ← no id
//   property_approved         { property_title }                     ← no id
//   property_inquiry          { property_title, inquirer_name }      ← no id
//   channel_message           { channel_id, … }                      ← has one
//
// The portal handles this by routing to a *list* where an id is missing
// (`/chat`, `/networks/members`, `/manage-properties`) and to a detail page only when
// `data.follower_id` / `data.property_id` / `data.projectId` happens to be present —
// which, for rows its own helpers wrote, it never is. Those branches are effectively
// dead on the portal.
//
// This app's five writers are better in two cases and no worse anywhere:
//
//   project_shared            { projectId, projectTitle, builderName }   ← routable
//   builder_network_addition  { sender_id, sender_name[, member_type] }  ← routable
//
// So the id-bearing branches are honoured when the key is there and fall back to the
// portal's list destination when it is not. Nothing here invents an id or guesses a
// destination from a display string.
//
// `visit_booking_new`/`visit_booking_update` are a separate case, not in the
// list above — see their own case comments below. They route to the Manage
// Dashboard's Leads/Visits tabs via `DashboardSection`, which no other
// notification type in this switch needs.
//
// `message_received` is a SEPARATE case, not in either list above: unlike the
// portal's own `notificationHelpers.ts` writers, `notify_new_message()` (the
// DB trigger — the only writer of this type) always includes
// `conversation_id`/`sender_id`/`sender_name`, and the portal's own
// `NotificationList.tsx` does deep-link straight to that sender's thread with
// them. Flutter does too — but `ChatThreadScreen` has no named-route
// generator (every call site builds it directly via `Navigator.push`, e.g.
// `NotificationsScreen._openCollab`), so this pure `(type, data) → named
// route` function cannot build that destination. `NotificationsScreen`
// intercepts `message_received` before calling this function, the same way
// it already does for `collab_*` and `bulk_message`.
import '../../models/app_notification.dart' show NotificationTypes;
import '../../models/builder_section_models.dart';
import '../constants/app_constants.dart';
import 'dashboard_section.dart';

/// A resolved destination: a named route plus its arguments.
class NotificationDestination {
  const NotificationDestination(this.route, [this.arguments]);

  final String route;
  final Map<String, dynamic>? arguments;
}

/// Where [type] with [data] should open, or null for "nowhere".
///
/// Null is a first-class answer, not a failure. The portal's `default` branch is
/// `// For unknown types, just mark as read`, and several of its cases fall through
/// without navigating when the id is absent. A tap on one of those should still mark
/// the row read — which the caller does regardless — and simply not move the user.
///
/// `visit_booking_new`/`visit_booking_update` route to the Manage
/// Dashboard's Leads/Visits tabs rather than a detail page — see their own
/// case comments for the direction-disambiguation rule `visit_booking_update`
/// needs (it is written in both directions and must not always land on the
/// same tab).
NotificationDestination? resolveNotificationDestination({
  required String type,
  required Map<String, dynamic> data,
}) {
  String? id(String key) {
    final value = data[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  switch (type) {
    // ── Detail when an id is present, list when it is not ──────────────────
    case 'new_follower':
      // `/user/${follower_id}` (`:63`). The portal's own helper does not write
      // `follower_id`, so this resolves only for rows written elsewhere.
      final followerId = id('follower_id') ?? id('sender_id');
      return followerId == null
          ? null
          : NotificationDestination(AppConstants.publicProfileScreen, {
              'userId': followerId,
            });

    case 'builder_network_addition':
      // The portal goes to `/networks/members` unconditionally (`:73`). This app's
      // `sendRequest` and `sendBuilderInvite` both write `sender_id`, so the person
      // can be opened directly — strictly more useful, and the list is the fallback.
      final senderId = id('sender_id');
      if (senderId != null) {
        return NotificationDestination(AppConstants.publicProfileScreen, {
          'userId': senderId,
        });
      }
      // `NetworkCommunicationService.sendBulkMessage` reuses this same enum
      // value for a broadcast announcement — the one writer of it with no
      // `sender_id` at all (see its own `data` shape:
      // `{message_type, priority}`). Routing a bulk announcement to "the
      // sender's connection list" would misleadingly read as if it were a
      // connection request; the Communication screen it was actually sent
      // from is the honest destination.
      if (id('message_type') != null) {
        return const NotificationDestination(
          AppConstants.networkCommunicationScreen,
        );
      }
      return const NotificationDestination(AppConstants.myNetworksScreen);

    case 'property_approved':
    case 'property_like':
      // `/property/${property_id}` (`:79`). `property_like` has no portal case;
      // grouped here because it is the same subject and the same payload shape.
      //
      // `property_approved` is ALSO reused for a builder PROJECT's approval —
      // confirmed from a real device log: `{project_id: "<uuid>", review_kind:
      // "project"}`, with no `property_id` at all. Whatever writes that row
      // isn't in this repo (added directly against the live database, not
      // through a checked-in trigger/migration), so `project_id`'s presence
      // is the only signal available here to tell the two apart — checked
      // first, since a genuine property-approval row never carries one.
      final projectId = id('project_id') ?? id('projectId');
      if (projectId != null) {
        return NotificationDestination(AppConstants.projectDetailScreen, {
          'projectId': projectId,
        });
      }
      final propertyId = id('property_id') ?? id('propertyId');
      return propertyId == null
          ? null
          : NotificationDestination(AppConstants.propertyDetailScreen, {
              'propertyId': propertyId,
            });

    case 'project_shared':
      // `/project/${projectId}` (`:96`). `ProjectShareService` does write
      // `projectId`, so this is the one detail route that resolves in practice.
      final projectId = id('projectId') ?? id('project_id');
      return projectId == null
          ? null
          : NotificationDestination(AppConstants.projectDetailScreen, {
              'projectId': projectId,
            });

    case 'profile_view':
      // `/user/${viewer_id}` else `/profile-views` (`:101-107`). Only reachable if
      // the unapplied `migration2` enum value lands.
      final viewerId = id('viewer_id');
      return viewerId != null
          ? NotificationDestination(AppConstants.publicProfileScreen, {
              'userId': viewerId,
            })
          : const NotificationDestination(AppConstants.profileViewsScreen);

    // ── List destinations ──────────────────────────────────────────────────
    case 'channel_addition':
    case 'channel_message':
    case 'channel_admin_promoted':
      // Both go to `/chat` on the portal (`:68`, `:87`). Flutter's equivalent
      // is the messages list. `channel_message` does carry `channel_id`, but this
      // app's channel thread route expects a channel summary object rather than an
      // id, so the list is the honest destination rather than a route that would
      // fail to build.
      //
      // `channel_admin_promoted` (`leave_channel_with_succession` SQL,
      // `20271007030100_...`) has the identical shape problem — its own
      // `data` is only `{channel_id, channel_name}` — so it routes the same
      // way for the same reason, not a lesser case.
      //
      // `message_received` is NOT handled here (see below) — it opens the
      // specific sender's thread, which this resolver cannot build.
      return const NotificationDestination(AppConstants.messagesScreen);

    case 'lead_assigned':
    case 'lead_status_update':
    case 'network_lead_new':
      // `/networks/leads` (`:93`). `network_lead_new` has no portal case; it is the
      // same subject.
      return const NotificationDestination(AppConstants.myLeadsScreen);

    case 'property_inquiry':
      // The portal goes to `/manage-properties`, which this app does not have —
      // listings are managed on the role dashboard instead. The dispatcher
      // resolves the right dashboard for the role.
      return const NotificationDestination(AppConstants.manageDashboardScreen);

    case 'document_reupload_requested':
    case 'document_approved':
      // `navigate('/edit-profile')` for both (`NotificationList.tsx:220-223`).
      return const NotificationDestination(AppConstants.editProfileScreen);

    case NotificationTypes.teamActivity:
      // `notify_team_member_change`/`notify_team_activity_log`
      // (`20271007040100_notify_team_activity.sql`) write four distinct
      // events under this one type, each stamping the exact portal path to
      // open as `data.route` — read directly rather than re-derived from
      // `data.event`, the same "trust the payload over the title" rule
      // every other case here follows:
      //
      //   '/team-workspace'           — `member_added`/`access_changed`:
      //     this account just gained, or had changed, team access to
      //     ANOTHER builder's workspace. `data.builder_id` names which one,
      //     so the right membership opens instead of whichever is first.
      //   '/manage-builder-dashboard' — `invite_accepted` (a builder's own
      //     invite got accepted) and the coalesced "Team activity" log (a
      //     member edited something on the builder's own projects): both
      //     are about THIS builder's own team roster, on their own
      //     dashboard's Team tab.
      //   anything else (`/notifications` for `member_removed`, or an
      //     unrecognised future value) — nowhere to open; the row already
      //     says what happened.
      final route = data['route']?.toString();
      if (route == '/team-workspace') {
        final builderId = id('builder_id');
        return NotificationDestination(AppConstants.teamWorkspaceScreen, {
          if (builderId != null) 'builderId': builderId,
        });
      }
      if (route == '/manage-builder-dashboard') {
        return const NotificationDestination(AppConstants.manageDashboardScreen, {
          'section': DashboardSection.team,
        });
      }
      return null;

    case 'visit_booking_new':
      // Written only by the backend's `notify_on_visit_booking` DB trigger
      // (an `AFTER INSERT` on `property_visit_bookings`/
      // `project_visit_bookings`/`profile_visit_requests`). The trigger
      // always resolves the recipient to the listing/project/profile OWNER
      // and skips the row entirely when recipient == requester (no
      // self-booking notifications) — so there is no direction to
      // disambiguate here, unlike `visit_booking_update` below: every row of
      // this type always means "someone requested a visit on your own
      // listing/profile", i.e. the owner's Leads tab.
      return NotificationDestination(AppConstants.manageDashboardScreen, {
        'section': DashboardSection.leads,
        ..._visitHighlightArgs(data),
      });

    case 'visit_booking_update':
      // Unlike every other case above, this type is written in BOTH
      // directions and must not be routed the same way every time:
      //
      //   * owner → requester (the owner confirmed/cancelled/rescheduled a
      //     booking on their own listing) — belongs on the REQUESTER's
      //     Site Visits tab.
      //   * requester → owner (the requester cancelled/rescheduled their
      //     own outgoing request) — belongs on the OWNER's Leads tab.
      //
      // Confirmed from the backend's actual writers (not guessed): the
      // owner→requester direction — both the portal's shared
      // `insertVisitBookingUpdateNotification` helper AND this app's own
      // `SiteVisitService`/`PropertyVisitBookingService` writers — never
      // include a `bookingId` in `data` (`{title, status, date, time[,
      // projectId]}` only). The requester→owner direction — the backend's
      // `my-visit-booking-manage` edge function, the only writer of that
      // direction — always includes `data.bookingId`. So "has a bookingId"
      // reliably means "I am the owner", with zero inference from role,
      // status value or title text. `data.recipientRole` (set by this
      // app's own writers going forward) is checked first when present,
      // since it needs no inference at all.
      final recipientRole = data['recipientRole']?.toString();
      if (recipientRole == 'owner') {
        return NotificationDestination(AppConstants.manageDashboardScreen, {
          'section': DashboardSection.leads,
          ..._visitHighlightArgs(data),
        });
      }
      if (recipientRole == 'requester') {
        return NotificationDestination(AppConstants.manageDashboardScreen, {
          'section': DashboardSection.visits,
          ..._visitHighlightArgs(data),
        });
      }

      // No explicit `recipientRole` — every row written before this fix,
      // and every row the backend itself writes (it has no such field, and
      // this app must not request a backend/schema change to add one).
      // A row with no recognisable visit-booking shape at all (no `status`
      // and no `title`) is genuinely ambiguous — rather than guess, open the
      // dashboard on its ordinary default tab instead of a wrong one.
      final hasVisitShape = data['status'] != null || data['title'] != null;
      if (!hasVisitShape) {
        return const NotificationDestination(
          AppConstants.manageDashboardScreen,
        );
      }

      final hasBookingId = id('bookingId') != null;
      return NotificationDestination(AppConstants.manageDashboardScreen, {
        'section': hasBookingId
            ? DashboardSection.leads
            : DashboardSection.visits,
        ..._visitHighlightArgs(data),
      });

    // ── Deliberately nowhere ───────────────────────────────────────────────
    //
    // The social_* types report background publishing outcomes and have no
    // screen in this app at all. Tapping marks them read, which is the whole
    // interaction.
    //
    // `bulk_message` never reaches this switch at all: there is no
    // conversation/message row behind it (NetworkCommunicationService.
    // sendBulkMessage and the backend's network-channels-manage "broadcast"
    // action both do a pure `notifications` insert), so there is nothing to
    // navigate to. NotificationsScreen intercepts it before calling this
    // function and shows the notification's own title/message in a detail
    // dialog instead — mirroring the portal's NotificationList.tsx, which
    // does the same rather than routing anywhere.
    //
    // `new_rating` also never reaches this switch: `trigger_notify_on_rating`
    // writes `rater_id`/`rater_name`/`rating`/`rating_id` only — never the
    // rated user's own id, since the recipient always *is* the rated user —
    // so there is no id in `data` for this function to read. NotificationsScreen
    // intercepts it and opens the signed-in user's own Reviews screen instead,
    // which is a `BuildContext`/auth lookup this pure function has no access to.
    default:
      return null;
  }
}

/// Redirects a `visit_booking_new`/`visit_booking_update` notification that
/// [resolveNotificationDestination] already placed on the owner's Manage
/// Dashboard "Leads" tab (`DashboardSection.leads`) to the Team Workspace's
/// Site Visits tab instead, when the current viewer only has *team* access
/// to that project — an invited collaborator, not the project's own owner.
/// `builder_sections_service.dart`'s `SiteVisitService` is the shared data
/// source behind both: the owner's own Leads tab
/// (`builder_leads_section.dart`) and the Team Workspace's Site Visits tab
/// (`TeamSiteVisitsTab`) both read `project_visit_bookings` the same way —
/// only which screen can actually act on the project's visits for THIS
/// viewer differs. [TeamLeadsTab] is a different, unrelated feature
/// (`network_leads`, scoped by `builder_id` only) and is never a candidate
/// here.
///
/// [baseline] is whatever [resolveNotificationDestination] already returned
/// for the same `(type, data)` — this never recomputes that routing
/// decision, only redirects the one outcome that means something different
/// for a team member than it does for the project's real owner. Every other
/// outcome (the visits tab, a property/profile id, null, a type this never
/// applies to, …) is returned unchanged.
///
/// A membership's `projectIds` of `null` means every one of that builder's
/// projects grants access ([BuilderTeamMember.hasAllProjects]) — the same
/// convention [TeamWorkspaceScreen] itself uses. A membership that doesn't
/// grant the `site_visits` module is skipped: that tab wouldn't even appear
/// for it, so redirecting there would open nothing.
NotificationDestination? applyTeamWorkspaceOverride({
  required NotificationDestination? baseline,
  required Map<String, dynamic> data,
  required List<BuilderTeamMember> activeTeamMemberships,
}) {
  if (baseline == null) return baseline;
  if (baseline.route != AppConstants.manageDashboardScreen) return baseline;
  if (baseline.arguments?['section'] != DashboardSection.leads) return baseline;

  final projectId =
      data['projectId']?.toString() ?? data['project_id']?.toString();
  if (projectId == null || projectId.isEmpty) return baseline;

  for (final membership in activeTeamMemberships) {
    if (!membership.modules.contains('site_visits')) continue;
    final allowed = membership.projectIds;
    if (membership.hasAllProjects || (allowed?.contains(projectId) ?? false)) {
      return NotificationDestination(AppConstants.teamWorkspaceScreen, {
        if (membership.builderId != null) 'builderId': membership.builderId!,
        'module': 'site_visits',
      });
    }
  }
  return baseline;
}

/// `bookingId`/`source` for the destination screen to focus the matching
/// record on — "source" is derived from whichever single content id the row
/// actually carries (`propertyId`/`projectId`/`profileUserId`), the same way
/// every visit-booking writer in this app and the backend only ever
/// populates exactly one of those three per row. Returns `{}` when neither
/// is available — per spec, missing highlight metadata must never prevent
/// opening the right section, so callers merge this in rather than branch
/// on it.
Map<String, String> _visitHighlightArgs(Map<String, dynamic> data) {
  final bookingId = data['bookingId']?.toString();
  final source = data['propertyId'] != null
      ? 'property'
      : data['projectId'] != null
      ? 'project'
      : data['profileUserId'] != null
      ? 'profile'
      : null;
  return {
    if (bookingId != null && bookingId.isNotEmpty)
      'highlightBookingId': bookingId,
    if (source != null) 'highlightSource': source,
  };
}
