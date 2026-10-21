import '../models/tool_result.dart';
import 'registry.dart';

void registerFavoritesTool() {
  toolRegistry.register(
    ToolDefinition(
      name: 'show_saved_properties',
      description: 'Navigate to the saved / shortlisted properties screen.',
      execute: (params, ctx) async {
        // Flutter's shortlist screen is /shortlist, not /social-profile (website).
        ctx.navigate('/shortlist');
        return ToolResult.ok();
      },
    ),
  );
}
