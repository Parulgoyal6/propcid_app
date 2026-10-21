// services/voice_search_service.dart
//
// Voice Search — uses on-device speech recognition (Android SpeechRecognizer
// / iOS Speech framework via the speech_to_text package) rather than the
// website's server-side STT (openai-proxy's /audio/transcriptions), since
// that requires audio-file recording/upload plumbing this app doesn't have.
// The user-facing result is the same either way (tap mic, speak, see it
// transcribed into the search box); this is simply a different, more
// mobile-native implementation path. No backend changes either way.
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceSearchService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onError: (e) => debugPrint('[VoiceSearch] error: $e'),
      onStatus: (s) => debugPrint('[VoiceSearch] status: $s'),
    );
    return _isInitialized;
  }

  /// Starts listening, invoking [onResult] with the transcribed text as it
  /// updates (both partial and final results — check `isFinal` to know
  /// which). Returns false if speech recognition isn't available/permitted
  /// on this device.
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    final available = await initialize();
    if (!available) return false;

    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
    );
    return true;
  }

  Future<void> stopListening() => _speech.stop();

  Future<void> cancelListening() => _speech.cancel();
}
