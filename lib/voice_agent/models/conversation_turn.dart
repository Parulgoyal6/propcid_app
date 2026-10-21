import 'dart:convert';
import 'dart:math';
import 'intent.dart';

class ConversationTurn {
  final String id;
  final String role; // 'user' | 'assistant'
  final String text;
  final String? rawJsonText; // assistant only — full JSON for OpenAI replay
  final Intent? intent;
  final int timestamp; // milliseconds since epoch
  final String? toolExecuted;
  final bool? toolSuccess;

  ConversationTurn({
    required this.id,
    required this.role,
    required this.text,
    this.rawJsonText,
    this.intent,
    required this.timestamp,
    this.toolExecuted,
    this.toolSuccess,
  });

  factory ConversationTurn.create({
    required String role,
    required String text,
    String? rawJsonText,
    Intent? intent,
    String? toolExecuted,
    bool? toolSuccess,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(99999).toString().padLeft(5, '0');
    return ConversationTurn(
      id: '$now-$rand',
      role: role,
      text: text,
      rawJsonText: rawJsonText,
      intent: intent,
      timestamp: now,
      toolExecuted: toolExecuted,
      toolSuccess: toolSuccess,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'text': text,
      'rawJsonText': rawJsonText,
      'intent': intent?.name,
      'timestamp': timestamp,
      'toolExecuted': toolExecuted,
      'toolSuccess': toolSuccess,
    };
  }

  factory ConversationTurn.fromMap(Map<String, dynamic> map) {
    return ConversationTurn(
      id: map['id'] as String,
      role: map['role'] as String,
      text: map['text'] as String,
      rawJsonText: map['rawJsonText'] as String?,
      intent: map['intent'] != null
          ? IntentExtension.fromString(map['intent'] as String)
          : null,
      timestamp: map['timestamp'] as int,
      toolExecuted: map['toolExecuted'] as String?,
      toolSuccess: map['toolSuccess'] as bool?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ConversationTurn.fromJson(String source) =>
      ConversationTurn.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
