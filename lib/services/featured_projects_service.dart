// services/featured_projects_service.dart
//
// Read-only access to `public.featured_projects`, the admin-curated join
// table onto `builder_projects` — mirrors the portal's
// `featured_projects -> builder_projects` query (`PublicHomePage.tsx` /
// `AuthenticatedHomePage.tsx`, `fetchProjects`).
//
// WHY THIS IS SEPARATE FROM `HotPropertiesService`
// -------------------------------------------------
// Confirmed against the live schema: `featured_projects.property_id` is a
// foreign key to `builder_projects.id`, NOT `properties.id`, despite the
// column name. `hot_properties.property_id` (read by [HotPropertiesService])
// really does point at `properties.id`. Projects and properties are
// different entities with different shapes ([ProjectModel] vs
// [PropertyModel], different card fields — a price *range* and unit counts
// instead of a single price and beds/baths) and different detail screens
// (`/project-detail` vs `/property-detail`). Sharing one query or one card
// between them would silently mix the two, which is exactly what this
// service exists to avoid.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/project_model.dart';

class FeaturedProjectsService {
  FeaturedProjectsService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'featured_projects';

  /// Active-admin-curated projects, in the admin's configured order.
  ///
  /// Rethrows on failure so the caller can distinguish "no curated projects
  /// yet" from "the request failed" — same reasoning as
  /// [HotPropertiesService.listActive].
  Future<List<ProjectModel>> listActive({int limit = 10}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(
            'id, property_id, display_order, '
            'builder_projects(${ProjectModel.columns})',
          )
          .order('display_order', ascending: true)
          .limit(limit);

      final result = <ProjectModel>[];
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final projectRow = row['builder_projects'] as Map<String, dynamic>?;
        if (projectRow == null) continue;

        final project = ProjectModel.fromSupabase(projectRow);
        if (project.id.isEmpty) continue;
        if (!project.isPubliclyVisible || !project.isApproved) continue;

        result.add(project);
      }
      return result;
    } catch (e) {
      debugPrint('FeaturedProjectsService.listActive failed: $e');
      rethrow;
    }
  }
}
