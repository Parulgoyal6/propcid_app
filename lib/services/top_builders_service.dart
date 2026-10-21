// services/top_builders_service.dart
//
// Read-only access to `public.top_builders_city`, the admin-curated
// per-city builder rail, joined onto `profiles` for display info — mirrors
// the portal's "Top Builders" sidebar widget (`fetchProjects` in
// `PublicHomePage.tsx` / `AuthenticatedHomePage.tsx`).
//
// Distinct from [PeopleSearchService.listPopularAgents] (Popular Brokers /
// Popular Influencers): that one reads `profiles` directly with no curation
// table. Builders get their own admin-curated table because the portal
// treats "top builder" as a per-city editorial pick, not just "approved
// builder" — reproduced here via the FK `top_builders_city.builder_id ->
// profiles.user_id`.
//
// Falls back to approved `profiles` where `user_type = 'builder'` only when
// the curated table has zero rows, matching the portal's own fallback
// (`AuthenticatedHomePage.tsx`'s `buildersQuery` branch) — not a hardcoded
// substitute, just a looser real-data query when nothing has been curated
// yet.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'people_search_service.dart';

class TopBuildersService {
  TopBuildersService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<UserProfile>> listActive({int limit = 10}) async {
    try {
      final curatedRows = await _supabase
          .from('top_builders_city')
          .select(
            'id, builder_id, display_order, '
            'profiles(${PeopleSearchService.columns})',
          )
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .limit(limit);

      final curated = <UserProfile>[];
      for (final row in List<Map<String, dynamic>>.from(curatedRows)) {
        final profileRow = row['profiles'] as Map<String, dynamic>?;
        if (profileRow == null) continue;
        final profile = UserProfile.fromMap(
          Map<String, dynamic>.from(profileRow),
        );
        if (profile.userId.isNotEmpty) curated.add(profile);
      }
      if (curated.isNotEmpty) return curated;

      final fallbackRows = await _supabase
          .from('profiles')
          .select(PeopleSearchService.columns)
          .eq('user_type', 'builder')
          .eq('approval_status', 'approved')
          .not('is_blocked', 'is', true)
          .limit(limit);

      return List<Map<String, dynamic>>.from(fallbackRows)
          .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
          .where((profile) => profile.userId.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('TopBuildersService.listActive failed: $e');
      rethrow;
    }
  }
}
