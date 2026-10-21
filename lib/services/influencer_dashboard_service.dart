import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/influencer_dashboard_model.dart';

class InfluencerDashboardService {
  final _supabase = Supabase.instance.client;

  Future<InfluencerDashboardModel> getDashboardStats(
    String influencerId,
  ) async {
    try {
      final videos = await _supabase
          .from('influencer_videos')
          .select('views,status')
          .eq('user_id', influencerId);

      final totalVideos = videos.length;

      final activeCampaigns = videos
          .where((e) => e['status'] == 'active')
          .length;

      int totalViews = 0;

      for (final video in videos) {
        totalViews += ((video['views'] ?? 0) as num).toInt();
      }

      // We'll connect real earnings later
      const totalEarnings = 0.0;

      return InfluencerDashboardModel(
        totalVideos: totalVideos,
        activeCampaigns: activeCampaigns,
        totalViews: totalViews,
        totalEarnings: totalEarnings,
      );
    } catch (e) {
      print("================================");
      print("INFLUENCER DASHBOARD ERROR");
      print(e);
      print("================================");

      return InfluencerDashboardModel.empty();
    }
  }
}
