import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/builder_project_model.dart';

class BuilderProjectService {
  final _supabase = Supabase.instance.client;

  Future<List<BuilderProjectModel>> getProjects(String builderId) async {
    try {
      final response = await _supabase
          .from('builder_projects')
          .select()
          .eq('builder_id', builderId)
          .order('created_at', ascending: false);

      return response
          .map<BuilderProjectModel>((e) => BuilderProjectModel.fromSupabase(e))
          .toList();
    } catch (e) {
      print("================================");
      print("BUILDER PROJECT ERROR");
      print(e);
      print("================================");

      return [];
    }
  }
}
