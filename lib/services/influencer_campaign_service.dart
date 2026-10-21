import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/influencer_campaign_model.dart';

class InfluencerCampaignService {
  final _supabase = Supabase.instance.client;

  Future<List<InfluencerCampaignModel>> getVideos(String userId) async {
    try {
      final response = await _supabase
          .from('influencer_videos')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return response
          .map<InfluencerCampaignModel>(
            (e) => InfluencerCampaignModel.fromSupabase(e),
          )
          .toList();
    } catch (e) {
      print("================================");
      print("INFLUENCER VIDEO ERROR");
      print(e);
      print("================================");

      return [];
    }
  }
}
