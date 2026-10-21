import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_response.dart';
import '../models/conversation_turn.dart';
import 'openai_proxy.dart';

/// Calls openai-proxy/chat/completions and returns a parsed AgentResponse.
/// Single responsibility: HTTP + JSON parse only. Orchestration lives in VoiceAgentProvider.
Future<AgentResponse> processVoiceCommand({
  required String userText,
  required List<ConversationTurn> history,
  required String systemPrompt,
  String knowledgeContext = '', // Phase 3: RAG context injected here
}) async {
  final messages = _buildMessages(
    history,
    userText,
    systemPrompt,
    knowledgeContext,
  );
  final headers = OpenAiProxy.jsonHeaders();
  final url = Uri.parse(OpenAiProxy.proxyUrl('/chat/completions'));

  final body = jsonEncode({
    'messages': messages,
    'response_format': {'type': 'json_object'},
    'max_completion_tokens': 4096,
  });

  late http.Response response;
  try {
    response = await http.post(url, headers: headers, body: body);
  } catch (e) {
    throw 'Network error: $e';
  }

  if (response.statusCode == 429) {
    throw 'Rate limit reached. Please wait a moment.';
  }
  if (response.statusCode == 401) {
    throw 'Authorization failed. Please sign in again.';
  }
  if (response.statusCode != 200) {
    throw 'Request failed (${response.statusCode}).';
  }

  try {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        decoded['choices']?[0]?['message']?['content'] as String? ?? '';
    return _parseResponse(content);
  } catch (_) {
    return AgentResponse.unknown();
  }
}

List<Map<String, dynamic>> _buildMessages(
  List<ConversationTurn> history,
  String userText,
  String systemPrompt,
  String knowledgeContext,
) {
  // Append knowledge context to system prompt when present (Phase 3).
  final fullSystemPrompt = knowledgeContext.isNotEmpty
      ? '$systemPrompt\n\nPROPCID KNOWLEDGE CONTEXT:\n$knowledgeContext'
      : systemPrompt;

  return [
    {'role': 'system', 'content': fullSystemPrompt},
    // History: assistant turns use rawJsonText for multi-turn coherence.
    for (final turn in history)
      {
        'role': turn.role,
        'content': turn.role == 'assistant'
            ? (turn.rawJsonText ?? turn.text)
            : turn.text,
      },
    {'role': 'user', 'content': userText},
  ];
}

AgentResponse _parseResponse(String raw) {
  try {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      return AgentResponse.fromJson(
        jsonDecode(trimmed) as Map<String, dynamic>,
      );
    }
    // Extract first {...} block if model prefixed with explanation text.
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(trimmed);
    if (match != null) {
      return AgentResponse.fromJson(
        jsonDecode(match.group(0)!) as Map<String, dynamic>,
      );
    }
  } catch (_) {
    // Fall through to unknown.
  }
  return AgentResponse.unknown();
}
