import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_models.dart';
import '../models/network_stats.dart';

/// Mostly read-only reads for the Network feature.
///
/// Grew in three steps: the Profile screen's accepted-connection count
/// (blueprint §9), the hub's four KPIs (Phase 6), and the leaf screens'
/// memberships / leads / referrals / channels (Phase 9).
///
/// Almost every method is a `select`; the Network writes React owns —
/// accepting or declining an invitation, creating a referral or a channel,
/// sending a bulk message — stay with the web portal. [updateLeadStatus] is
/// the one exception, added for the Team Workspace's Leads tab, which mirrors
/// a write `TeamLeadsView.tsx:67-82` already makes for a builder team member
/// — not a broker-side write this class was otherwise guarding against.
class NetworkService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Number of accepted network connections for [userId].
  ///
  /// Mirrors ProfileDashboardShell.tsx's `fetchNetworks` +
  /// `acceptedNetworks` — see blueprint §9. React selects every row the user
  /// participates in (as either `builder_id` or `member_id`) and then counts
  /// those with `status === 'accepted'`; a null status is treated as
  /// "pending", so filtering server-side on `status = 'accepted'` yields the
  /// same number without pulling the rows.
  Future<int> getAcceptedCount(String userId) async {
    try {
      final rows = await _supabase
          .from('builder_networks')
          .select('id')
          .or('member_id.eq.$userId,builder_id.eq.$userId')
          .eq('status', 'accepted');

      return (rows as List).length;
    } catch (e) {
      debugPrint('NetworkService.getAcceptedCount failed: $e');
      rethrow;
    }
  }

  /// The Network hub's four KPIs.
  ///
  /// A direct port of `NetworkDashboard.tsx`'s `fetchBuilderStats` /
  /// `fetchMemberStats`. React picks the branch on
  /// `profileData?.user_type === 'builder'`; the caller resolves the same flag
  /// from the already-loaded `AuthProvider.userType` rather than re-querying
  /// `profiles`, which React only reads because it has no auth store to ask.
  ///
  /// Read-only: three `select`s, no writes, no RPCs, and the same columns and
  /// filters the web portal already uses.
  Future<NetworkStats> getNetworkStats(
    String userId, {
    required bool isBuilder,
  }) async {
    try {
      // Builders own a network and see leads they have raised; members belong
      // to networks and see leads assigned to them. The column pairs differ
      // per branch, which is why React keeps two functions.
      final networkColumn = isBuilder ? 'builder_id' : 'member_id';
      final leadColumn = isBuilder ? 'builder_id' : 'assigned_member_id';
      final leadStatuses = isBuilder
          ? ['pending', 'assigned']
          : ['assigned', 'contacted'];

      // Local midnight on the 1st, then sent as UTC — the same instant React's
      // `setDate(1); setHours(0,0,0,0)` + `toISOString()` produces.
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month).toUtc();

      final results = await Future.wait([
        _supabase
            .from('builder_networks')
            .select('id')
            .eq(networkColumn, userId)
            .eq('status', 'accepted'),
        _supabase
            .from('network_leads')
            .select('id')
            .eq(leadColumn, userId)
            .inFilter('status', leadStatuses),
        _supabase
            .from('network_commissions')
            .select('amount')
            .eq(networkColumn, userId)
            .gte('created_at', startOfMonth.toIso8601String()),
      ]);

      final commissionRows = results[2] as List;
      final monthlyCommissions = commissionRows.fold<double>(
        0,
        (sum, row) =>
            sum + (double.tryParse('${(row as Map)['amount'] ?? 0}') ?? 0),
      );

      return NetworkStats(
        totalNetworks: (results[0] as List).length,
        activeLeads: (results[1] as List).length,
        // React: `const referralsCount = 0; // Temporarily disable this query`.
        // Deliberately not implemented here either — see [NetworkStats].
        totalReferrals: 0,
        monthlyCommissions: monthlyCommissions,
      );
    } catch (e) {
      debugPrint('NetworkService.getNetworkStats failed: $e');
      rethrow;
    }
  }

  /// The caller's network connections, from either side of the relationship.
  ///
  /// Ports `NetworkMemberships.tsx`'s membership fetch: `select *` filtered with
  /// `.or(member_id.eq.X, builder_id.eq.X)`, the same predicate
  /// [getAcceptedCount] already uses. Accepting or declining an invitation is a
  /// write and stays with the web portal.
  Future<List<NetworkMembership>> listMemberships(String userId) async {
    try {
      final rows = await _supabase
          .from('builder_networks')
          .select()
          .or('member_id.eq.$userId,builder_id.eq.$userId')
          .order('created_at', ascending: false);

      return (rows as List)
          .map(
            (r) => NetworkMembership.fromJson(
              Map<String, dynamic>.from(r as Map),
              viewerId: userId,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('NetworkService.listMemberships failed: $e');
      rethrow;
    }
  }

  /// Network leads visible to the caller.
  ///
  /// Builders see the leads they raised; members see the ones assigned to them.
  /// The column pair mirrors [getNetworkStats], which is how React splits the
  /// same query between its builder and member branches.
  Future<List<NetworkLead>> listLeads(
    String userId, {
    required bool isBuilder,
  }) async {
    try {
      final column = isBuilder ? 'builder_id' : 'assigned_member_id';
      final rows = await _supabase
          .from('network_leads')
          .select()
          .eq(column, userId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((r) => NetworkLead.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('NetworkService.listLeads failed: $e');
      rethrow;
    }
  }

  /// Sets one lead's status. `LeadDistributionSystem.tsx`'s
  /// `handleUpdateLeadStatus`: an UPDATE by id, no client-side check of who
  /// may call this — `network_leads`'s own RLS (`Team members can update
  /// builder leads`, builder-level, matching [listLeads]'s own `isBuilder`
  /// reads) is what actually authorizes it.
  ///
  /// Also stamps `contacted_at` / `conversion_date` on the matching
  /// transitions, exactly as that handler does — without this, a lead moved
  /// to "contacted" through the app would carry a real `assigned_at` (set
  /// server-side by the `assign-lead-automatically` function regardless of
  /// which platform assigned it) but no `contacted_at`, which is one of the
  /// two columns [getPerformanceMetrics] needs to compute a response time at
  /// all.
  Future<void> updateLeadStatus(String leadId, String status) async {
    try {
      final updates = <String, dynamic>{'status': status};
      if (status == 'contacted') {
        updates['contacted_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (status == 'converted') {
        updates['conversion_date'] = DateTime.now().toUtc().toIso8601String();
      }

      await _supabase.from('network_leads').update(updates).eq('id', leadId);
    } catch (e) {
      debugPrint('NetworkService.updateLeadStatus failed: $e');
      rethrow;
    }
  }

  /// Success rate and average response time over this user's network leads —
  /// the Network hub's "Performance Summary" card.
  ///
  /// Neither figure exists in the portal: `NetworkDashboard.tsx` types `85%`
  /// and `2.3 hrs` directly into the markup with no query behind either.
  /// `network_leads` already carries what both need — `status` for success,
  /// `assigned_at`/`contacted_at` for response time — the same two timestamp
  /// columns an existing RLS predicate
  /// (`20260710123600_audit_optimize_rls_initplan.sql`) already requires
  /// non-null together, which is reused here as the definition of "a lead
  /// that got a real, timed response".
  Future<({double? successRate, double? avgResponseTimeHours})>
  getPerformanceMetrics(String userId, {required bool isBuilder}) async {
    try {
      final column = isBuilder ? 'builder_id' : 'assigned_member_id';
      final rows = await _supabase
          .from('network_leads')
          .select('status, assigned_at, contacted_at')
          .eq(column, userId);

      return computePerformanceMetrics(List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('NetworkService.getPerformanceMetrics failed: $e');
      rethrow;
    }
  }

  /// The arithmetic behind [getPerformanceMetrics], pulled out as a pure
  /// function so it can be unit-tested without a Supabase round trip.
  ///
  /// Success rate: `converted` leads over every lead scoped to this user,
  /// regardless of status — "of everything that ever came to me, how much did
  /// I close". Response time: hours between `assigned_at` and `contacted_at`,
  /// averaged over leads that reached at least `contacted` with both
  /// timestamps set — a lead still `pending`/`assigned` has no response yet
  /// to time, and one missing either timestamp cannot be timed at all.
  ///
  /// Both are null on an empty list — "no data", not "0%"/"0 hrs" — matching
  /// [NetworkStats.successRatePercent]'s own null-means-no-data contract.
  static ({double? successRate, double? avgResponseTimeHours})
  computePerformanceMetrics(List<Map<String, dynamic>> leads) {
    if (leads.isEmpty) {
      return (successRate: null, avgResponseTimeHours: null);
    }

    final converted = leads.where((l) => l['status'] == 'converted').length;
    final successRate = converted / leads.length * 100;

    final responded = leads.where((l) {
      final status = l['status'];
      return (status == 'contacted' || status == 'converted') &&
          l['assigned_at'] != null &&
          l['contacted_at'] != null;
    }).toList();

    if (responded.isEmpty) {
      return (successRate: successRate, avgResponseTimeHours: null);
    }

    final totalHours = responded.fold<double>(0, (sum, l) {
      final assignedAt = DateTime.parse(l['assigned_at'] as String);
      final contactedAt = DateTime.parse(l['contacted_at'] as String);
      return sum + contactedAt.difference(assignedAt).inMinutes / 60.0;
    });

    return (
      successRate: successRate,
      avgResponseTimeHours: totalHours / responded.length,
    );
  }

  /// Referrals, commissions and scored periods in one round trip.
  ///
  /// The Referrals screen's four sub-tabs all read from these three tables, so
  /// they are fetched together rather than re-querying per tab switch.
  ///
  /// Referrals are filtered on `referrer_id`: the screen is "My Referrals", the
  /// ones this user made. Commissions and performance use the builder/member
  /// column pair, same as everywhere else in this service.
  Future<ReferralBundle> getReferralBundle(
    String userId, {
    required bool isBuilder,
  }) async {
    try {
      final column = isBuilder ? 'builder_id' : 'member_id';

      final results = await Future.wait([
        _supabase
            .from('network_referrals')
            .select()
            .eq('referrer_id', userId)
            .order('created_at', ascending: false),
        _supabase
            .from('network_commissions')
            .select()
            .eq(column, userId)
            .order('created_at', ascending: false),
        _supabase
            .from('network_performance')
            .select()
            .eq(column, userId)
            .order('period_start', ascending: true),
      ]);

      return ReferralBundle(
        referrals: (results[0] as List)
            .map(
              (r) =>
                  NetworkReferral.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList(),
        commissions: (results[1] as List)
            .map(
              (r) => NetworkCommission.fromJson(
                Map<String, dynamic>.from(r as Map),
              ),
            )
            .toList(),
        performance: (results[2] as List)
            .map(
              (r) => NetworkPerformance.fromJson(
                Map<String, dynamic>.from(r as Map),
              ),
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('NetworkService.getReferralBundle failed: $e');
      rethrow;
    }
  }

  /// Channels attached to the caller's network.
  ///
  /// `network_channels` is keyed by `builder_id` only — a member has no rows of
  /// their own — so a member sees an empty list, which is the truthful answer
  /// rather than an error.
  Future<List<NetworkChannel>> listChannels(String builderId) async {
    try {
      final rows = await _supabase
          .from('network_channels')
          .select()
          .eq('builder_id', builderId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map(
            (r) => NetworkChannel.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('NetworkService.listChannels failed: $e');
      rethrow;
    }
  }
}
