import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broker_property_model.dart';

class BrokerPropertyService {
  final _supabase = Supabase.instance.client;

  Future<List<BrokerPropertyModel>> getProperties(String brokerId) async {
    try {
      final response = await _supabase
          .from('properties')
          .select()
          .eq('user_id', brokerId)
          .order('created_at', ascending: false);

      return response
          .map<BrokerPropertyModel>((e) => BrokerPropertyModel.fromSupabase(e))
          .toList();
    } catch (e) {
      print("================================");
      print("BROKER PROPERTY ERROR");
      print(e);
      print("================================");

      return [];
    }
  }
}
