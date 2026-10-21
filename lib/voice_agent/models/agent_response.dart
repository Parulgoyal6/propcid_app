import 'dart:convert';
import 'intent.dart';

class AgentResponse {
  final Intent intent;
  final Map<String, dynamic> parameters;
  final String response;
  final bool needsConfirmation;
  final List<String> missingFields;
  final bool complete;

  const AgentResponse({
    required this.intent,
    required this.parameters,
    required this.response,
    required this.needsConfirmation,
    required this.missingFields,
    required this.complete,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      intent: IntentExtension.fromString(json['intent'] as String? ?? ''),
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
      response: json['response'] as String? ?? '',
      needsConfirmation: json['needs_confirmation'] as bool? ?? false,
      missingFields:
          (json['missing_fields'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      complete: json['complete'] as bool? ?? true,
    );
  }

  factory AgentResponse.unknown() {
    return const AgentResponse(
      intent: Intent.unknown,
      parameters: {},
      response: 'I could not understand your request. Please try again.',
      needsConfirmation: false,
      missingFields: [],
      complete: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'intent': intent.name,
      'parameters': parameters,
      'response': response,
      'needs_confirmation': needsConfirmation,
      'missing_fields': missingFields,
      'complete': complete,
    };
  }

  String toJson() => jsonEncode(toMap());

  AgentResponse copyWith({
    Intent? intent,
    Map<String, dynamic>? parameters,
    String? response,
    bool? needsConfirmation,
    List<String>? missingFields,
    bool? complete,
  }) {
    return AgentResponse(
      intent: intent ?? this.intent,
      parameters: parameters ?? this.parameters,
      response: response ?? this.response,
      needsConfirmation: needsConfirmation ?? this.needsConfirmation,
      missingFields: missingFields ?? this.missingFields,
      complete: complete ?? this.complete,
    );
  }
}
