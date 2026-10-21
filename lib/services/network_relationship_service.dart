import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_relationship.dart';

/// Reads every `builder_networks` row the viewer is a party to and classifies
/// each one via [classifyRelationship] — the single source of truth for
/// "owned network member" vs. "joined builder network" vs. "just a peer
/// connection" that Dashboard counts, My Networks, Bulk Message eligibility
/// and Channel auto-join all now share instead of re-deriving contradictory
/// answers.
///
/// A new, additive file rather than an addition to `NetworkService` — that
/// service documents itself as read-only-and-untouched-by-design (see
/// `network_service.dart`'s own header comment and
/// `ProfileConnectionService`'s explanation for why *its* writes live in a
/// separate file too), and every one of its existing methods/tests is left
/// exactly as it was.
class NetworkRelationshipService {
  NetworkRelationshipService({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _supabase => _clientOverride ?? Supabase.instance.client;

  /// Every `builder_networks` row naming [viewerId] as either party, hydrated
  /// with the counterpart's real profile and classified from [viewerId]'s
  /// perspective. Newest first, matching `NetworkService.listMemberships`'s
  /// existing ordering.
  ///
  /// A profile-hydration failure for one counterpart degrades that row to
  /// [NetworkRelationshipKind.unknownLegacyRelationship] (see
  /// [classifyRelationship]) rather than dropping the row — a relationship a
  /// user can see must never silently disappear from a list or a count just
  /// because its counterpart's name failed to resolve.
  Future<List<NetworkRelationship>> listRelationships(String viewerId) async {
    final rows = await _supabase
        .from('builder_networks')
        .select()
        .or('member_id.eq.$viewerId,builder_id.eq.$viewerId')
        .order('created_at', ascending: false);

    final base = List<Map<String, dynamic>>.from(rows as List);
    if (base.isEmpty) return const [];

    final counterpartIds = <String>{};
    for (final row in base) {
      final builderId = row['builder_id']?.toString();
      final memberId = row['member_id']?.toString();
      if (builderId == null || memberId == null) continue;
      counterpartIds.add(builderId == viewerId ? memberId : builderId);
    }
    counterpartIds.remove('');

    final profiles = await _fetchProfiles(counterpartIds);

    return base
        .where((row) {
          // A row missing either id can't be attributed to a counterpart at all —
          // skip rather than crash on a malformed row.
          return row['builder_id'] != null && row['member_id'] != null;
        })
        .map((row) {
          final builderId = row['builder_id'].toString();
          final memberId = row['member_id'].toString();
          final counterpartId = builderId == viewerId ? memberId : builderId;
          final profile = profiles[counterpartId];

          return NetworkRelationship.classify(
            row,
            viewerId: viewerId,
            counterpartDisplayName: profile?['display_name'] as String?,
            counterpartAvatarUrl: profile?['avatar_url'] as String?,
            counterpartCompanyName: profile?['company_name'] as String?,
            counterpartUserType: profile?['user_type'] as String?,
          );
        })
        .toList();
  }

  /// Real count of referrals this user has made — `network_referrals` where
  /// `referrer_id = userId`, the same column `NetworkService.
  /// getReferralBundle` already reads correctly for both roles.
  ///
  /// The Dashboard's "Total Referrals" KPI has never had a real query behind
  /// it on either platform (`NetworkDashboard.tsx`'s own
  /// `fetchBuilderStats`/`fetchMemberStats` both hardcode
  /// `const referralsCount = 0` with a `// Temporarily disable this query`
  /// comment) even though `network_referrals` and its RLS
  /// (`"Users can view their referrals"`, `referrer_id = auth.uid()` among
  /// its OR'd predicates) already support it — so this fills in a real,
  /// already-supported gap rather than perpetuating the portal's own
  /// placeholder.
  Future<int> countReferralsMade(String userId) async {
    final rows = await _supabase
        .from('network_referrals')
        .select('id')
        .eq('referrer_id', userId);
    return (rows as List).length;
  }

  /// Batched profile read for every counterpart in one round trip — the same
  /// `profiles_public` view `ProfileConnectionService` already reads
  /// elsewhere in this app (it carries `user_type`/`company_name`, unlike the
  /// narrower projection `MessagingService` uses), so this reuses an
  /// already-vetted safe-to-read-about-strangers source rather than the raw
  /// `profiles` table.
  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('profiles_public')
          .select('user_id, display_name, avatar_url, company_name, user_type')
          .inFilter('user_id', userIds.toList());

      return {
        for (final row in List<Map<String, dynamic>>.from(rows as List))
          if (row['user_id'] != null) row['user_id'].toString(): row,
      };
    } catch (e) {
      // A hydration failure must not take the whole list down — every row
      // just degrades to `unknownLegacyRelationship` (see
      // `NetworkRelationship.classify`'s null-userType handling) instead of
      // throwing away relationships the user can otherwise see.
      debugPrint('NetworkRelationshipService._fetchProfiles failed: $e');
      return const {};
    }
  }
}
