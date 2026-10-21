import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation_turn.dart';
import '../models/intent.dart';

class ConversationManager {
  static const int maxHistory = 20;
  static const String _prefsKey = 'va_conversation';

  List<ConversationTurn> _turns = [];

  ConversationManager() {
    _load();
  }

  /// Add a new turn. Trims to [maxHistory] and persists.
  ConversationTurn addTurn({
    required String role,
    required String text,
    String? rawJsonText,
    Intent? intent,
    String? toolExecuted,
    bool? toolSuccess,
  }) {
    final turn = ConversationTurn.create(
      role: role,
      text: text,
      rawJsonText: rawJsonText,
      intent: intent,
      toolExecuted: toolExecuted,
      toolSuccess: toolSuccess,
    );
    _turns.add(turn);
    if (_turns.length > maxHistory) {
      _turns = _turns.sublist(_turns.length - maxHistory);
    }
    _persist();
    return turn;
  }

  List<ConversationTurn> getHistory() => List.unmodifiable(_turns);

  /// All turns except the current (last) one — sent to OpenAI as context.
  List<ConversationTurn> getContextHistory() {
    if (_turns.isEmpty) return const [];
    return List.unmodifiable(_turns.sublist(0, _turns.length - 1));
  }

  /// Replace the entire history.
  /// Phase 3: called after loadRecentTurns() from ai_voice_conversations.
  void replaceAll(List<ConversationTurn> turns) {
    _turns = List.of(turns);
    _persist();
  }

  void clear() {
    _turns = [];
    _persist();
  }

  void _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_turns.map((t) => t.toMap()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // Persistence is best-effort; never throw.
    }
  }

  void _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _turns = list
            .map((e) => ConversationTurn.fromMap(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _turns = [];
    }
  }
}

/// Singleton — one conversation per app session.
final conversationManager = ConversationManager();
