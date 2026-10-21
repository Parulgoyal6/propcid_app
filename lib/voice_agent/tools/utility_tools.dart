import '../models/tool_result.dart';
import 'registry.dart';

void registerUtilityTools() {
  // Sentinel / no-op tools — the model's "response" text IS the answer.
  // VoiceAgentProvider reads shouldExecuteTool() = false for these and
  // displays response text directly without calling execute().
  // These registrations exist so toolRegistry.has(name) returns true.

  for (final name in [
    'confirm',
    'unknown',
    'ask_platform',
    'auth_required',
    'suggest_signup',
    'ask_about_platform',
    'ask_property_info',
  ]) {
    toolRegistry.register(
      ToolDefinition(
        name: name,
        description:
            'Sentinel tool — handled by VoiceAgentProvider state machine.',
        execute: (params, ctx) async => ToolResult.ok(),
      ),
    );
  }
}
