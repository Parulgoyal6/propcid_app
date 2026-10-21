// models/app_notification.dart
//
// One `notifications` row.
//
// Named `AppNotification`, not `Notification`: `Notification` is a Flutter
// framework class (the one `NotificationListener` dispatches), and shadowing it
// inside widget files would be a trap for every future reader.
//
// THE TABLE IS ALREADY COMPLETE — nothing here implies a migration
// ----------------------------------------------------------------
// `notifications` (20250913060836_f90f3657…sql:12-22) carries a typed enum, an
// `is_read` flag, a `data` JSONB, RLS scoped to `auth.uid() = user_id` for SELECT
// **and UPDATE**, three indexes including a partial one on unread, and is already
// in the `supabase_realtime` publication with `REPLICA IDENTITY FULL`.
//
// It also has an `AFTER INSERT` trigger that posts every new row to the
// `send-web-push` edge function (20270203000000). That is why this app must never
// call `send-web-push` itself — `notificationHelpers.ts:48` records that doing both
// double-sends — and why the five existing writers need no change at all.
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The `notification_type` enum, in migration order.
///
/// Base six from 20250913060836:2-9, then twelve `ADD VALUE` migrations. Kept as
/// strings rather than a Dart enum: the column is a Postgres enum that has grown
/// thirteen times, and an unrecognised value must render rather than crash a whole
/// screen. `kUnappliedNotificationTypes` below records the ones that are declared
/// only in the unapplied `migration2/` set.
class NotificationTypes {
  NotificationTypes._();

  // ── Base six ────────────────────────────────────────────────────────────
  static const String newFollower = 'new_follower';
  static const String channelAddition = 'channel_addition';
  static const String builderNetworkAddition = 'builder_network_addition';
  static const String propertyApproved = 'property_approved';
  static const String propertyInquiry = 'property_inquiry';
  static const String messageReceived = 'message_received';

  // ── Added by later migrations, all applied ──────────────────────────────
  static const String leadAssigned = 'lead_assigned';
  static const String leadStatusUpdate = 'lead_status_update';
  static const String networkLeadNew = 'network_lead_new';
  static const String channelMessage = 'channel_message';
  static const String projectShared = 'project_shared';
  static const String propertyLike = 'property_like';
  static const String visitBookingUpdate = 'visit_booking_update';

  /// Added by `20270916000000_add_visit_booking_new_notification_type.sql`.
  /// Written only by the `notify_on_visit_booking` DB trigger (an `AFTER
  /// INSERT` on `property_visit_bookings`/`project_visit_bookings`/
  /// `profile_visit_requests`) — the recipient is always the listing/profile
  /// owner, never the requester (the trigger skips self-booking rows where
  /// recipient == requester). See `resolveNotificationDestination`.
  static const String visitBookingNew = 'visit_booking_new';
  static const String socialPublishStarted = 'social_publish_started';
  static const String socialPublishSuccess = 'social_publish_success';
  static const String socialPublishFailed = 'social_publish_failed';
  static const String socialRetryStarted = 'social_retry_started';
  static const String socialRetrySuccess = 'social_retry_success';

  // ── Collaboration Marketplace — 20270421000000_collab_marketplace_enums.sql
  // `ALTER TYPE notification_type ADD VALUE`, all applied. Every payload
  // carries `collaboration_id` (+ `asset_id` for the two asset-related
  // types) — see `resolveCollabNotificationDestination`, which is async
  // (it looks the collaboration up) and therefore lives outside
  // `resolveNotificationDestination`, not as a case in it.
  static const String collabRequest = 'collab_request';
  static const String collabAccepted = 'collab_accepted';
  static const String collabDeclined = 'collab_declined';
  static const String collabAdvancePaid = 'collab_advance_paid';
  static const String collabSampleReady = 'collab_sample_ready';
  static const String collabFinalPaid = 'collab_final_paid';
  static const String collabDeliverableReady = 'collab_deliverable_ready';
  static const String collabDeliverableExpiring = 'collab_deliverable_expiring';
  static const String collabDisputed = 'collab_disputed';
  static const String collabCompleted = 'collab_completed';

  // ── KYC document review —
  // 20270423000000_document_review_notification_types.sql, both applied.
  // Written client-side by the portal's admin panel (`AdminPanel.tsx`'s
  // `reviewDocument`) straight into `notifications`, so this app only ever
  // reads these — it never writes them.
  static const String documentReuploadRequested = 'document_reupload_requested';
  static const String documentApproved = 'document_approved';

  // ── Bulk message — 20270915030000_add_bulk_message_notification_type.sql,
  // applied. A builder's broadcast to their network; no conversation/message
  // row backs it (the notification's own title/message IS the content), so
  // NotificationsScreen shows it in a detail dialog rather than navigating —
  // see `resolveNotificationDestination`'s header comment.
  static const String bulkMessage = 'bulk_message';

  // ── New rating/review — `trigger_notify_on_rating` on `user_ratings`
  // (20270421001700_sync_missing_functions_and_triggers.sql), applied; title
  // is literally "New Review". Payload carries `rater_id`/`rater_name`/
  // `rating`/`rating_id` only — never the rated user's own id, since the
  // recipient always *is* the rated user — so NotificationsScreen opens the
  // signed-in user's own public profile rather than reading an id from
  // `data`. See `resolveNotificationDestination`'s header comment.
  static const String newRating = 'new_rating';

  /// Added by `20271007040000_add_team_activity_notification_type.sql`.
  /// Written by two triggers in `20271007040100_notify_team_activity.sql`:
  /// `notify_team_member_change` (a `builder_team_members` row going
  /// active/revoked/changed — "Added to a team", "Team member joined",
  /// "Removed from a team", "Team access updated") and
  /// `notify_team_activity_log` (a delegated edit logged to
  /// `builder_team_activity`, coalesced into one "Team activity" row per
  /// actor+entity-type per 15 minutes). Every row's `data.route` is one of
  /// the portal paths this type can mean — `/team-workspace`,
  /// `/manage-builder-dashboard` or `/notifications` — which
  /// `resolveNotificationDestination` reads directly rather than
  /// re-deriving from `data.event`.
  static const String teamActivity = 'team_activity';

  static const Set<String> collabTypes = {
    collabRequest,
    collabAccepted,
    collabDeclined,
    collabAdvancePaid,
    collabSampleReady,
    collabFinalPaid,
    collabDeliverableReady,
    collabDeliverableExpiring,
    collabDisputed,
    collabCompleted,
  };

  /// Declared only in `supabase/migration2/`, which `supabase/MIGRATIONS.md`
  /// records as never applied.
  ///
  /// A row can therefore never hold one of these today. They are named so the
  /// fallback rendering is a deliberate choice rather than an oversight if the
  /// migration lands later.
  static const Set<String> unapplied = {
    'profile_view',
    'social_campaign_created',
    'social_lead_new',
  };
}

/// How one notification type is drawn.
///
/// The five visual buckets are the mock screen's own — `Icons.trending_down` on
/// green for a price drop, a calendar on brand for a visit, and so on. Spec G keeps
/// them and maps the eighteen real enum values onto them, rather than inventing an
/// eighteen-icon palette the design never specified.
class NotificationStyle {
  const NotificationStyle({
    required this.icon,
    required this.color,
    required this.background,
    required this.filter,
  });

  final IconData icon;
  final Color color;
  final Color background;

  /// Which of the screen's filter chips this type belongs to.
  final String filter;
}

/// The screen's filter chips, in their existing order.
///
/// `All` first, then the four the mock screen already showed. `System` is not a
/// chip — it is the fallback bucket, and giving it a chip would advertise a
/// category most users never receive.
const List<String> kNotificationFilters = [
  'All',
  'Price Drop',
  'Visits',
  'Matches',
  'Enquiries',
];

/// Style and filter bucket for every applied enum value.
///
/// Grouping rationale, since it is a judgement call and not a portal contract —
/// the portal renders no icons per type at all:
///
///   * **Visits**    — anything about a scheduled viewing;
///   * **Enquiries** — anything where a person is trying to reach you;
///   * **Matches**   — approvals and likes, i.e. good news about your own content;
///   * **Price Drop** — reserved for a genuine price change. No enum value produces
///     one yet, so the chip currently filters to nothing; it is kept because the
///     design specifies it and a future `price_drop` value would land here.
const Map<String, NotificationStyle> kNotificationStyles = {
  // ── Enquiries: someone is contacting you ────────────────────────────────
  NotificationTypes.propertyInquiry: NotificationStyle(
    icon: Icons.chat_bubble_outline_rounded,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.messageReceived: NotificationStyle(
    icon: Icons.chat_bubble_outline_rounded,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.channelMessage: NotificationStyle(
    icon: Icons.forum_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.bulkMessage: NotificationStyle(
    icon: Icons.campaign_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.leadAssigned: NotificationStyle(
    icon: Icons.assignment_ind_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.leadStatusUpdate: NotificationStyle(
    icon: Icons.timeline_rounded,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.networkLeadNew: NotificationStyle(
    icon: Icons.inbox_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),

  // ── Visits ──────────────────────────────────────────────────────────────
  NotificationTypes.visitBookingUpdate: NotificationStyle(
    icon: Icons.calendar_today_outlined,
    color: AppColors.primary,
    background: AppColors.primaryLight,
    filter: 'Visits',
  ),
  NotificationTypes.visitBookingNew: NotificationStyle(
    icon: Icons.calendar_today_outlined,
    color: AppColors.primary,
    background: AppColors.primaryLight,
    filter: 'Visits',
  ),

  // ── Matches: good news about your own content ───────────────────────────
  NotificationTypes.propertyApproved: NotificationStyle(
    icon: Icons.verified_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.propertyLike: NotificationStyle(
    icon: Icons.favorite_outline_rounded,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.projectShared: NotificationStyle(
    icon: Icons.apartment_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.newRating: NotificationStyle(
    icon: Icons.star_outline_rounded,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),

  // ── Collaboration Marketplace ────────────────────────────────────────────
  //
  // Bucketing rationale (a judgement call — the portal renders no icons per
  // type here either, and has no client-side routing for any of these at
  // all): request/accepted/declined are someone trying to reach you, so
  // Enquiries; the payment/asset/completion milestones are good news about
  // an active deal, so Matches; a dispute is the one type that needs its own
  // visual weight, so it gets System's neutral bucket plus an error tint
  // rather than either of those two.
  NotificationTypes.collabRequest: NotificationStyle(
    icon: Icons.handshake_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.collabAccepted: NotificationStyle(
    icon: Icons.handshake_outlined,
    color: AppColors.statusBooked,
    background: Color(0xFFFFF7ED),
    filter: 'Enquiries',
  ),
  NotificationTypes.collabDeclined: NotificationStyle(
    icon: Icons.handshake_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'Enquiries',
  ),
  NotificationTypes.collabAdvancePaid: NotificationStyle(
    icon: Icons.payments_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.collabSampleReady: NotificationStyle(
    icon: Icons.videocam_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.collabFinalPaid: NotificationStyle(
    icon: Icons.payments_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.collabDeliverableReady: NotificationStyle(
    icon: Icons.movie_creation_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.collabDeliverableExpiring: NotificationStyle(
    icon: Icons.timer_outlined,
    color: AppColors.error,
    background: Color(0xFFFEE2E2),
    filter: 'Matches',
  ),
  NotificationTypes.collabCompleted: NotificationStyle(
    icon: Icons.verified_outlined,
    color: Color(0xFFF59E0B),
    background: Color(0xFFFEF3C7),
    filter: 'Matches',
  ),
  NotificationTypes.collabDisputed: NotificationStyle(
    icon: Icons.report_gmailerrorred_outlined,
    color: AppColors.error,
    background: Color(0xFFFEE2E2),
    filter: 'System',
  ),

  // ── System: everything structural ───────────────────────────────────────
  NotificationTypes.newFollower: NotificationStyle(
    icon: Icons.person_add_alt_1_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.builderNetworkAddition: NotificationStyle(
    icon: Icons.hub_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.channelAddition: NotificationStyle(
    icon: Icons.group_add_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.teamActivity: NotificationStyle(
    icon: Icons.groups_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.socialPublishStarted: NotificationStyle(
    icon: Icons.cloud_upload_outlined,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.socialPublishSuccess: NotificationStyle(
    icon: Icons.cloud_done_outlined,
    color: AppColors.success,
    background: Color(0xFFDCFCE7),
    filter: 'System',
  ),
  NotificationTypes.socialPublishFailed: NotificationStyle(
    icon: Icons.cloud_off_outlined,
    color: AppColors.error,
    background: Color(0xFFFEE2E2),
    filter: 'System',
  ),
  NotificationTypes.socialRetryStarted: NotificationStyle(
    icon: Icons.refresh_rounded,
    color: AppColors.textSecondary,
    background: AppColors.background,
    filter: 'System',
  ),
  NotificationTypes.socialRetrySuccess: NotificationStyle(
    icon: Icons.cloud_done_outlined,
    color: AppColors.success,
    background: Color(0xFFDCFCE7),
    filter: 'System',
  ),

  // ── KYC document review — same two icons NotificationList.tsx:59-62 uses
  // (ShieldAlert amber / ShieldCheck emerald), Material equivalents.
  NotificationTypes.documentReuploadRequested: NotificationStyle(
    icon: Icons.gpp_maybe_outlined,
    color: AppColors.warning,
    background: Color(0xFFFEF3C7),
    filter: 'System',
  ),
  NotificationTypes.documentApproved: NotificationStyle(
    icon: Icons.verified_user_outlined,
    color: AppColors.success,
    background: Color(0xFFDCFCE7),
    filter: 'System',
  ),
};

/// The fallback for a type this build does not know.
///
/// Reached by the three `migration2` values if that set is ever applied, and by any
/// future `ADD VALUE`. Renders as System rather than throwing — the shield icon the
/// mock screen already used for its own `system` bucket.
const NotificationStyle kFallbackNotificationStyle = NotificationStyle(
  icon: Icons.shield_outlined,
  color: AppColors.textSecondary,
  background: AppColors.background,
  filter: 'System',
);

/// Style for [type], never null.
NotificationStyle notificationStyleFor(String? type) =>
    kNotificationStyles[type] ?? kFallbackNotificationStyle;

/// One notification, as stored.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    this.data = const {},
    this.createdAt,
  });

  final String id;

  /// The raw enum value. Not parsed into a Dart enum — see [NotificationTypes].
  final String type;

  /// Both NOT NULL.
  final String title;
  final String message;

  final bool isRead;

  /// The `data` JSONB. Nullable in the schema, `{}` here so every reader can index
  /// it without a guard.
  ///
  /// Its keys are set by whoever wrote the row and are **not** uniform — the
  /// Flutter writers use `projectId`, `sender_id`, `sender_name`, `member_type`,
  /// `status`, `date`, `time`, `title`, plus (as of this fix) `bookingId`,
  /// `recipientRole` and `source` on visit-booking rows. `NotificationRoute` is
  /// the one place that knows which key means what.
  final Map<String, dynamic> data;

  final DateTime? createdAt;

  /// The columns this model reads.
  ///
  /// Spelled out rather than the portal's `select('*')`, so a column added by a
  /// future migration cannot silently change what is parsed.
  static const String columns =
      'id, type, title, message, data, is_read, created_at';

  factory AppNotification.fromSupabase(Map<String, dynamic> json) {
    final raw = json['data'];
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isRead: json['is_read'] == true,
      data: raw is Map<String, dynamic> ? raw : const {},
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    isRead: isRead ?? this.isRead,
    data: data,
    createdAt: createdAt,
  );

  NotificationStyle get style => notificationStyleFor(type);

  /// Which filter chip this row answers to.
  String get filter => style.filter;

  /// Relative age, the way the mock screen's hardcoded strings read
  /// ("2 min ago", "1 hr ago", "Yesterday").
  ///
  /// Computed rather than stored, so it stays true as the screen sits open.
  String get relativeTime {
    final created = createdAt;
    if (created == null) return '';

    final delta = DateTime.now().difference(created);
    if (delta.isNegative) return 'Just now';
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) {
      return '${delta.inHours} hr${delta.inHours == 1 ? '' : 's'} ago';
    }
    if (delta.inDays == 1) return 'Yesterday';
    if (delta.inDays < 7) return '${delta.inDays} days ago';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[created.month - 1]} ${created.day}';
  }
}
