import '../models/tool_context.dart';
import '../models/tool_result.dart';

class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};

  void register(ToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  Future<ToolResult> execute(
    String name,
    Map<String, dynamic> params,
    ToolContext ctx,
  ) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.fail('Tool "$name" is not registered.');
    }
    try {
      return await tool.execute(params, ctx);
    } catch (e) {
      return ToolResult.fail(e.toString());
    }
  }

  bool has(String name) => _tools.containsKey(name);
}

/// Singleton — all registration functions call toolRegistry.register().
final toolRegistry = ToolRegistry();
