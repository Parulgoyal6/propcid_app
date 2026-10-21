import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation_turn.dart';
import '../models/intent.dart';

/// Voice assistant conversation history — durable persistence to Supabase.
///
/// Mirrors the web portal's `src/services/rag/conversationHistoryService.ts`:
/// writes each chat turn to the owner-only `ai_voice_conversations` table
/// (RLS guarantees a user only ever touches their own rows). All writers are
/// fire-and-forget and swallow errors — history is an enhancement, never a
/// hard dependency, so a failure (offline, guest user) must not break the
/// live voice flow. The in-memory/SharedPreferences copy in
/// ConversationManager still drives the panel; this layer adds cross-session
/// durability, same as the portal.
class StoredTurn {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String? intent;
  final String? toolExecuted;
  final bool? toolSuccess;
  final String createdAt;

  StoredTurn({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.intent,
    this.toolExecuted,
    this.toolSuccess,
    required this.createdAt,
  });

  factory StoredTurn.fromMap(Map<String, dynamic> map) {
    return StoredTurn(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      role: map['role'] as String,
      content: map['content'] as String,
      intent: map['intent'] as String?,
      toolExecuted: map['tool_executed'] as String?,
      toolSuccess: map['tool_success'] as bool?,
      createdAt: map['created_at'] as String,
    );
  }
}

class ConversationHistoryService {
  static const _table = 'ai_voice_conversations';

  // A stable per-app-run id so all turns from one session group together,
  // matching the web portal's per-tab sessionStorage id. Reset on
  // sign-in/sign-out/explicit clear via resetSessionId().
  String? _sessionId;

  String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = (now % 999999).toString().padLeft(6, '0');
    return '$now-$rand';
  }

  String getSessionId() {
    return _sessionId ??= _generateSessionId();
  }

  /// Start a fresh session (call on sign-in / sign-out / explicit clear).
  void resetSessionId() {
    _sessionId = null;
  }

  /// Persist a single turn. Best-effort, fire-and-forget: never throws,
  /// never blocks. No-op for guests (RLS needs auth).
  void saveTurn(String? userId, ConversationTurn turn) {
    if (userId == null) return;
    () async {
      try {
        await Supabase.instance.client.from(_table).insert({
          'user_id': userId,
          'session_id': getSessionId(),
          'role': turn.role,
          'content': turn.text,
          'intent': turn.intent?.name,
          'tool_executed': turn.toolExecuted,
          'tool_success': turn.toolSuccess,
        });
      } catch (_) {
        // best-effort
      }
    }();
  }

  /// Load a user's most recent turns (returned oldest-first, ready to
  /// render). Never throws — returns [] on any failure.
  Future<List<StoredTurn>> loadRecentTurns(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final data = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = (data as List)
          .map((e) => StoredTurn.fromMap(e as Map<String, dynamic>))
          .toList();
      return rows.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete all stored turns for a user. Best-effort.
  Future<void> clearStoredHistory(String userId) async {
    try {
      await Supabase.instance.client
          .from(_table)
          .delete()
          .eq('user_id', userId);
    } catch (_) {
      // best-effort
    }
  }
}

/// Convert a DB row back into a [ConversationTurn] for the active session.
ConversationTurn storedTurnToConversationTurn(StoredTurn stored) {
  return ConversationTurn(
    id: stored.id,
    role: stored.role,
    text: stored.content,
    intent: stored.intent != null
        ? IntentExtension.fromString(stored.intent!)
        : null,
    timestamp:
        DateTime.parse(stored.createdAt).millisecondsSinceEpoch,
    toolExecuted: stored.toolExecuted,
    toolSuccess: stored.toolSuccess,
  );
}

/// Singleton — mirrors the portal's module-level service functions.
final conversationHistoryService = ConversationHistoryService();
