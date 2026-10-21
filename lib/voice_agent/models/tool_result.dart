import 'tool_context.dart';

class ToolResult {
  final bool success;
  final dynamic data;
  final String? error;
  final String? userMessage; // overrides displayed response on failure

  const ToolResult({
    required this.success,
    this.data,
    this.error,
    this.userMessage,
  });

  factory ToolResult.ok({dynamic data, String? userMessage}) {
    return ToolResult(success: true, data: data, userMessage: userMessage);
  }

  factory ToolResult.fail(String error, {String? userMessage}) {
    return ToolResult(success: false, error: error, userMessage: userMessage);
  }
}

typedef ToolExecutor =
    Future<ToolResult> Function(Map<String, dynamic> params, ToolContext ctx);

class ToolDefinition {
  final String name;
  final String description;
  final ToolExecutor execute;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.execute,
  });
}
