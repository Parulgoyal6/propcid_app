import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/builder_dashboard_model.dart';

class BuilderDashboardService {
  final _supabase = Supabase.instance.client;

  Future<BuilderDashboardModel> getDashboardStats(String builderId) async {
    try {
      // ===========================
      // Projects
      // ===========================

      final projects = await _supabase
          .from('builder_projects')
          .select('id,status')
          .eq('builder_id', builderId);

      final totalProjects = projects.length;

      final activeProjects = projects
          .where((e) => e['status'] == 'active')
          .length;

      final deliveredProjects = projects
          .where(
            (e) => e['status'] == 'completed' || e['status'] == 'delivered',
          )
          .length;

      // ===========================
      // Network Members
      // ===========================

      final networks = await _supabase
          .from('builder_networks')
          .select('id')
          .eq('builder_id', builderId)
          .eq('status', 'accepted');

      final networkMembers = networks.length;

      // `builder_ratings`/`builder_testimonials` were dropped entirely by
      // 20270916080000_drop_builder_ratings_and_testimonials.sql ("the
      // Ratings & Testimonials builder feature was removed entirely ...
      // the Average Rating dashboard stat"). This method used to query
      // `builder_ratings` here, unconditionally, inside this same try block
      // — querying a table that no longer exists throws, which the catch
      // below turned into `BuilderDashboardModel.empty()`, silently
      // discarding the totalProjects/activeProjects/networkMembers already
      // computed above. There is no replacement data source: the portal
      // removed the corresponding stat at the same time.
      const customerRating = 0.0;
      const brokerRating = 0.0;

      return BuilderDashboardModel(
        totalProjects: totalProjects,
        activeProjects: activeProjects,
        deliveredProjects: deliveredProjects,
        networkMembers: networkMembers,
        customerRating: customerRating,
        brokerRating: brokerRating,
      );
    } catch (e) {
      print("==================================");
      print("BUILDER DASHBOARD ERROR");
      print(e);
      print("==================================");

      return BuilderDashboardModel.empty();
    }
  }
}
