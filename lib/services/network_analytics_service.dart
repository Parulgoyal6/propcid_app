import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_analytics.dart';

/// Reads for Network ▸ Analytics — a new, additive service rather than an
/// addition to `NetworkService`, which documents itself as read-only and
/// deliberately untouched (see that file's own header, and every other
/// Network service added this way in this module).
///
/// Every query mirrors `NetworkAnalyticsDashboard.tsx` exactly: always
/// `.eq('builder_id', builderId)` — the portal runs this same component
/// (and hence these same queries) for that builder's own network only.
class NetworkAnalyticsService {
  NetworkAnalyticsService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _supabase => _clientOverride ?? Supabase.instance.client;

  /// The six counts/sums behind the four KPI tiles and the Network Health
  /// card's two progress bars, fetched in parallel — the same six the
  /// portal's `Promise.all` fetches (just via row lists rather than a
  /// `count: 'exact', head: true` head-request, matching how every other
  /// count in this module — e.g. `NetworkService.getAcceptedCount` — is
  /// already read in this codebase).
  Future<NetworkAnalyticsStats> getStats(String builderId) async {
    final results = await Future.wait([
      _supabase
          .from('builder_networks')
          .select('id')
          .eq('builder_id', builderId),
      _supabase
          .from('builder_networks')
          .select('id')
          .eq('builder_id', builderId)
          .eq('status', 'accepted'),
      _supabase.from('network_leads').select('id').eq('builder_id', builderId),
      _supabase
          .from('network_leads')
          .select('id')
          .eq('builder_id', builderId)
          .eq('status', 'converted'),
      _supabase
          .from('network_commissions')
          .select('amount')
          .eq('builder_id', builderId)
          .eq('status', 'paid'),
      _supabase
          .from('network_referrals')
          .select('id')
          .eq('builder_id', builderId),
    ]);

    final commissionRows = List<Map<String, dynamic>>.from(results[4] as List);
    final totalCommissionsPaid = commissionRows.fold<double>(
      0,
      (sum, row) => sum + (double.tryParse('${row['amount'] ?? 0}') ?? 0),
    );

    return NetworkAnalyticsStats(
      totalMembers: (results[0] as List).length,
      activeMembers: (results[1] as List).length,
      totalLeadsDistributed: (results[2] as List).length,
      convertedLeads: (results[3] as List).length,
      totalCommissionsPaid: totalCommissionsPaid,
      totalReferrals: (results[5] as List).length,
    );
  }

  /// The Performance leaderboard for one period, newest-scored first.
  /// Mirrors the portal's `network_performance` read (`builder_id` +
  /// `period_start`/`period_end` range, ordered by `performance_score`
  /// descending) plus a batched `profiles_public` join, the same
  /// `inFilter`-after-select pattern every other Network service in this
  /// module uses instead of a PostgREST embed.
  Future<List<NetworkPerformanceEntry>> listPerformance(
    String builderId, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final rows = await _supabase
        .from('network_performance')
        .select()
        .eq('builder_id', builderId)
        .gte('period_start', _dateOnly(periodStart))
        .lte('period_end', _dateOnly(periodEnd))
        .order('performance_score', ascending: false);

    final base = List<Map<String, dynamic>>.from(
      rows as List,
    ).where((r) => r['member_id'] != null).toList();
    if (base.isEmpty) return const [];

    final memberIds = base.map((r) => r['member_id'].toString()).toSet();
    final profileRows = await _supabase
        .from('profiles_public')
        .select('user_id, display_name, avatar_url, user_type')
        .inFilter('user_id', memberIds.toList());

    final profilesById = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(profileRows as List)) {
      final id = row['user_id']?.toString();
      if (id != null) profilesById[id] = row;
    }

    return base.map((r) {
      final memberId = r['member_id'].toString();
      final profile = profilesById[memberId];
      return NetworkPerformanceEntry.fromSupabase(
        r,
        displayName: profile?['display_name'] as String?,
        avatarUrl: profile?['avatar_url'] as String?,
        userType: profile?['user_type'] as String?,
      );
    }).toList();
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
}
