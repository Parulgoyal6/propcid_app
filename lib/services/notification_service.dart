// services/notification_service.dart
//
// Read and mark-read access to `notifications`, plus its realtime subscription.
//
// A DIRECT PORT OF `hooks/useNotifications.ts`
// -------------------------------------------
// Query for query: `.eq('user_id')`, `.order('created_at', desc)`, `.limit(50)`
// (`:29-33`); mark-read by id (`:50-53`); mark-unread by id (`:70-73`); mark-all by
// `user_id` + `is_read = false` (`:88-92`).
//
// NOTHING HERE WRITES A NOTIFICATION
// ----------------------------------
// The portal's hook also exposes `createNotification`. This service deliberately
// does not: five services in this app already insert rows
// (`project_share_service`, `profile_connection_service` ×2, `builder_sections_service`,
// `broker_sections_service`), each with its own copy and payload, and Spec G is
// under instruction not to modify them. A sixth writer here would be a second way
// to do something already done five times.
//
// AND NOTHING HERE SENDS PUSH
// ---------------------------
// It must not. `notifications` has an AFTER INSERT trigger that posts every row to
// the `send-web-push` edge function (20270203000000_web_push_on_notification_insert),
// so delivery is automatic and server-side. `notificationHelpers.ts:48` records that
// calling the function *and* inserting double-sends. The five existing writers
// therefore already reach the recipient's browser today with no client work.
//
// NO BACKEND CHANGE
// -----------------
// Three SELECTs and three UPDATEs, all permitted by the table's existing RLS
// (`auth.uid() = user_id` for both), plus a subscription to a table already in the
// `supabase_realtime` publication with `REPLICA IDENTITY FULL`.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

class NotificationService {
  NotificationService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'notifications';

  /// The portal's page size (`useNotifications.ts:33`).
  ///
  /// Not paginated beyond this on either platform. A user with more than fifty
  /// notifications sees the newest fifty, which is the portal's behaviour too.
  static const int pageSize = 50;

  /// This user's notifications, newest first.
  ///
  /// Throws on failure rather than degrading to an empty list: an empty list and a
  /// failed fetch look identical to a user, and "You're all caught up!" over a
  /// network error would be a lie. The provider turns the throw into a retry state.
  Future<List<AppNotification>> list(String userId) async {
    final rows = await _supabase
        .from(table)
        .select(AppNotification.columns)
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(pageSize);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map(AppNotification.fromSupabase).toList();
  }

  /// Marks one notification read.
  ///
  /// RLS scopes the UPDATE to `auth.uid() = user_id`, so a foreign id matches no
  /// row and completes silently — which is why this filters on id alone, exactly as
  /// the portal does.
  Future<void> markRead(String notificationId) async {
    await _supabase
        .from(table)
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Marks one notification unread again.
  ///
  /// The portal has this (`useNotifications.ts:65-79`) and it is cheap to keep, so
  /// the long-press affordance on the list has something to call rather than the
  /// screen owning a half-feature.
  Future<void> markUnread(String notificationId) async {
    await _supabase
        .from(table)
        .update({'is_read': false})
        .eq('id', notificationId);
  }

  /// Marks every unread notification read.
  ///
  /// Filters `is_read = false` as well as `user_id`, matching `:90-91`. Without the
  /// second filter this would rewrite every row the user owns and bump `updated_at`
  /// on all of them, for no change in value.
  Future<void> markAllRead(String userId) async {
    await _supabase
        .from(table)
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Subscribes to this user's notification inserts and updates.
  ///
  /// Follows the channel pattern Spec I established in
  /// `PropertyVisitBookingService.subscribe` — open in `initState`, hand the channel
  /// back, remove it in `dispose` — with one deliberate difference: **this
  /// subscription is filtered**.
  ///
  /// Spec I's bookings could not be filtered because their scope was "bookings on my
  /// listings", a join, and realtime filters are single-column. Here the scope *is*
  /// a single column, so `user_id=eq.$userId` is expressible and the client is only
  /// woken for its own rows. The portal filters identically
  /// (`useNotifications.ts:135`, `:150`).
  ///
  /// Three listeners, as the portal has:
  ///
  ///   * INSERT — a new notification arrived, so [onInsert] receives the parsed row
  ///     and the provider prepends it. No re-fetch: the payload is the whole row,
  ///     and `REPLICA IDENTITY FULL` guarantees it is complete.
  ///   * UPDATE — `is_read` changed, possibly from another device, so [onUpdate]
  ///     receives it and the provider replaces in place.
  ///   * DELETE — an undone action (unlike, uncomment, unfollow, a withdrawn
  ///     pending request, ...) retracted the notification it had created,
  ///     via the shared SQL triggers in
  ///     `20271007020000_retract_notifications_on_undo.sql`; [onDelete]
  ///     receives just the row id so the provider can drop it locally. Same
  ///     `REPLICA IDENTITY FULL` guarantee as INSERT/UPDATE makes
  ///     `payload.oldRecord` the complete old row (not just the primary
  ///     key), which is what lets the `user_id` filter below evaluate
  ///     correctly for a DELETE too — this table is confirmed in that
  ///     migration's own comment and is a member of the
  ///     `supabase_realtime` publication.
  ///
  /// The channel name carries the user id **and** a per-subscription discriminator,
  /// because two widgets subscribing under one name would collide — the portal
  /// solves it the same way (`:130`) with a random suffix.
  RealtimeChannel subscribe({
    required String userId,
    required String channelSuffix,
    required void Function(AppNotification) onInsert,
    required void Function(AppNotification) onUpdate,
    required void Function(String id) onDelete,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: userId,
    );

    return _supabase
        .channel('notifications-$userId-$channelSuffix')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            onInsert(AppNotification.fromSupabase(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            onUpdate(AppNotification.fromSupabase(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (payload) {
            final row = payload.oldRecord;
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) return;
            onDelete(id);
          },
        )
        .subscribe();
  }

  /// Stops a subscription started by [subscribe].
  ///
  /// Swallows its own failure: this is called from `dispose`, which must not throw.
  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (e) {
      debugPrint('NotificationService.unsubscribe failed: $e');
    }
  }
}
