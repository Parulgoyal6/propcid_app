import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OpenAiProxy {
  static String proxyUrl(String path) {
    final base = dotenv.env['SUPABASE_URL']!;
    return '$base/functions/v1/openai-proxy$path';
  }

  /// Auth headers for JSON body requests (includes Content-Type).
  static Map<String, String> jsonHeaders() {
    final token = _currentToken();
    return {
      'apikey': dotenv.env['SUPABASE_ANON_KEY']!,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Auth headers for multipart/binary requests (no Content-Type).
  /// Used by Phase 2 STT (audio/transcriptions) and TTS (audio/speech).
  static Map<String, String> rawHeaders() {
    final token = _currentToken();
    return {
      'apikey': dotenv.env['SUPABASE_ANON_KEY']!,
      'Authorization': 'Bearer $token',
    };
  }

  static String _currentToken() {
    return Supabase.instance.client.auth.currentSession?.accessToken ??
        dotenv.env['SUPABASE_ANON_KEY']!;
  }
}
