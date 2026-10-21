import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'user_profile_service.dart';

/// "Who viewed my profile" counts, backing the Profile screen's
/// "Profile Views" tile.
class ProfileViewService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Unique-viewer count for [userId].
  ///
  /// Mirrors `useProfileViewCount` in hooks/useProfileViews.ts — see blueprint
  /// §9. `profile_views` holds ONE row per (owner, viewer) pair: a returning
  /// visitor bumps `view_count` instead of inserting, so the unique-viewer
  /// count is exactly the row count. React uses a head-only exact count and
  /// pulls no rows; this does the same.
  Future<int> getCount(String userId) async {
    try {
      final res = await _supabase
          .from('profile_views')
          .select('id')
          .eq('profile_user_id', userId)
          .count(CountOption.exact);

      return res.count;
    } catch (e) {
      debugPrint('ProfileViewService.getCount failed: $e');
      rethrow;
    }
  }

  // ── Recording (Phase 2) ────────────────────────────────────────────────────
  //
  // The note that used to sit here said recording was deliberately unimplemented
  // because the app had no other-user profile screen. `PublicProfileScreen` now
  // exists, so the reason has expired and [recordView] below fills the gap.

  /// Guard against re-recording the same (viewer, owner) pair.
  ///
  /// `static`, so it is shared by every instance and lives as long as the process.
  /// The portal guards with `sessionStorage`, which is cleared when the tab
  /// closes; a process-lifetime Set is the closest equivalent Flutter has.
  ///
  /// `shared_preferences` was considered and rejected: it persists across app
  /// launches, so a user who viewed a profile once would never record another
  /// view — `view_count` would stay at 1 forever and the owner would stop
  /// hearing about repeat interest. That is worse than the portal, not merely
  /// different.
  static final Set<String> _recorded = <String>{};

  /// Records that [viewerId] opened [profileUserId]'s profile.
  ///
  /// Mirrors `useRecordProfileView` in hooks/useProfileViews.ts. The RPC does the
  /// real work — it upserts `profile_views`, bumps `view_count`, and inserts a
  /// `profile_view` notification subject to its own 30-minute cooldown — so this
  /// is a thin, guarded call.
  ///
  /// No-ops for an anonymous viewer and for a self-view. Both are enforced
  /// server-side as well (`record_profile_view` returns `{recorded: false}`), so
  /// this only avoids a pointless round-trip.
  ///
  /// **Never throws and never needs awaiting.** A failed recording must not
  /// affect the screen: the guard is released so a later visit retries, and the
  /// error is logged. Callers should fire and forget — awaiting this on a render
  /// path would put an RPC between the user and their first frame.
  Future<void> recordView({
    required String? viewerId,
    required String profileUserId,
  }) async {
    if (viewerId == null || viewerId.isEmpty) return;
    if (profileUserId.isEmpty || viewerId == profileUserId) return;

    final key = '$viewerId:$profileUserId';
    // Claimed before the await, so two near-simultaneous loads cannot both fire.
    if (!_recorded.add(key)) return;

    try {
      await _supabase.rpc(
        'record_profile_view',
        params: {'p_profile_user_id': profileUserId},
      );
    } catch (e) {
      // Released, exactly as the portal removes its sessionStorage key on error —
      // otherwise one transient failure would suppress this pair for the rest of
      // the session.
      _recorded.remove(key);
      debugPrint('ProfileViewService.recordView($profileUserId) failed: $e');
    }
  }

  /// Clears the in-process guard. Test-only — no production caller.
  @visibleForTesting
  static void resetRecordedGuard() => _recorded.clear();

  // ── Viewer list (Phase 7) ──────────────────────────────────────────────────

  /// Everyone who has viewed [userId]'s profile, most recent visit first.
  ///
  /// Mirrors `useProfileViewers` (hooks/useProfileViews.ts:86-136). Two queries,
  /// not one: `profile_views.viewer_id` references `auth.users`, **not**
  /// `profiles`, so there is no PostgREST relationship to embed and the viewers
  /// must be resolved separately. Attempting an embed here fails — it is the kind
  /// of thing that looks like it needs a schema change and does not.
  ///
  /// Capped at 200, as the portal caps it.
  ///
  /// Returns an empty list on failure rather than throwing: the caller shows an
  /// empty state, and a failed list must not take down the screen.
  Future<List<ProfileViewer>> fetchViewers(String userId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('profile_views')
            .select(
              'id, viewer_id, view_count, first_viewed_at, last_viewed_at',
            )
            .eq('profile_user_id', userId)
            .order('last_viewed_at', ascending: false)
            .limit(200),
      );

      if (rows.isEmpty) return const [];

      final viewerIds = rows
          .map((r) => r['viewer_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final profiles = await UserProfileService().fetchProfilesByIds(viewerIds);

      return rows
          .map(
            (row) => ProfileViewer.fromRow(
              row,
              profile: profiles[row['viewer_id']?.toString()],
            ),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('ProfileViewService.fetchViewers($userId) failed: $e');
      return const [];
    }
  }
}

/// One row of "who viewed my profile".
///
/// `profile_views` holds ONE row per (owner, viewer) pair, so [viewCount] is how
/// many times that person came back — not a second row.
@immutable
class ProfileViewer {
  final String id;
  final String viewerId;
  final int viewCount;
  final DateTime? lastViewedAt;

  /// Resolved from `profiles`, or null when the viewer's row is missing.
  final UserProfile? profile;

  const ProfileViewer({
    required this.id,
    required this.viewerId,
    required this.viewCount,
    this.lastViewedAt,
    this.profile,
  });

  /// True when this person has been back — drives the "viewed N times" badge.
  bool get isRepeatVisitor => viewCount > 1;

  String get displayName => profile?.displayTitle ?? 'PropCid user';

  factory ProfileViewer.fromRow(
    Map<String, dynamic> row, {
    UserProfile? profile,
  }) {
    final raw = row['last_viewed_at'];
    return ProfileViewer(
      id: row['id']?.toString() ?? '',
      viewerId: row['viewer_id']?.toString() ?? '',
      viewCount: (row['view_count'] as num?)?.toInt() ?? 1,
      lastViewedAt: raw == null ? null : DateTime.tryParse(raw.toString()),
      profile: profile,
    );
  }
}
