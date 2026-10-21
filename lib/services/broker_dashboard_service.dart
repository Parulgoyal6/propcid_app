import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broker_dashboard_model.dart';

class BrokerDashboardService {
  final _supabase = Supabase.instance.client;

  Future<BrokerDashboardModel> getDashboardStats(String brokerId) async {
    try {
      final properties = await _supabase
          .from('properties')
          .select('status,views')
          .eq('user_id', brokerId);

      final totalListings = properties.length;

      final activeListings = properties
          .where((e) => e['status'] == 'active')
          .length;

      int totalViews = 0;

      for (final property in properties) {
        totalViews += ((property['views'] ?? 0) as num).toInt();
      }

      // We will connect ratings later
      const averageRating = 0.0;

      return BrokerDashboardModel(
        totalListings: totalListings,
        activeListings: activeListings,
        totalViews: totalViews,
        averageRating: averageRating,
      );
    } catch (e) {
      print("================================");
      print("BROKER DASHBOARD ERROR");
      print(e);
      print("================================");

      return BrokerDashboardModel.empty();
    }
  }
}
