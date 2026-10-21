import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'openai_proxy.dart';

// ── Silence-detection constants ───────────────────────────────────────────────
const double _kSilenceThresholdDb = -35.0; // dBFS
const int _kSilenceHoldMs = 1500; // ms of silence before auto-stop
const int _kMaxDurationMs = 15000; // hard cap on recording length
const int _kMinSpeechMs = 400; // ignore accidental taps < 400 ms

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  // ── M1: TTS fields ────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _isTtsEnabled = false;
  bool _isSpeaking = false;
  Completer<void>? _playCompleter;

  // ── M2: STT fields ────────────────────────────────────────────────────────
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  bool _isListening = false;
  DateTime? _recordingStartedAt;
  DateTime? _silenceSince;
  StreamSubscription<RecordingDisposition>? _progressSub;
  Timer? _maxDurationTimer;
  void Function(String)? _onResult;
  void Function(String)? _onError;

  // ── Public state ──────────────────────────────────────────────────────────
  bool get isTtsEnabled => _isTtsEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  // ─────────────────────────────────────────────────────────────────────────
  // M1 — TTS API
  // ─────────────────────────────────────────────────────────────────────────

  void setTtsEnabled(bool value) => _isTtsEnabled = value;

  /// Synthesizes [text] via openai-proxy/audio/speech and plays it.
  /// Resolves when playback ends or [cancelSpeech] is called.
  /// Never throws — TTS is non-critical.
  Future<void> speak(String text) async {
    if (!_isTtsEnabled || text.trim().isEmpty) return;
    cancelSpeech();

    try {
      final response = await http.post(
        Uri.parse(OpenAiProxy.proxyUrl('/audio/speech')),
        headers: OpenAiProxy.jsonHeaders(),
        body: jsonEncode({'input': text, 'response_format': 'mp3'}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[SpeechService] TTS failed (${response.statusCode})');
        return;
      }

      _isSpeaking = true;
      _playCompleter = Completer<void>();

      _player.onPlayerComplete.first
          .then((_) => _resolvePlay())
          .catchError((_) => _resolvePlay());

      await _player.play(BytesSource(response.bodyBytes));
      await _playCompleter!.future;
    } catch (e) {
      debugPrint('[SpeechService] TTS error: $e');
    } finally {
      _isSpeaking = false;
      _playCompleter = null;
    }
  }

  /// Stops any in-progress TTS audio immediately.
  void cancelSpeech() {
    _resolvePlay();
    _player.stop();
    _isSpeaking = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // M2 — STT API
  // ─────────────────────────────────────────────────────────────────────────

  /// Records Opus/WebM audio and transcribes via openai-proxy/audio/transcriptions.
  ///
  /// Transcription fires automatically when silence is detected or the
  /// 15-second hard cap is reached.
  ///
  /// [onResult] receives the final trimmed transcript.
  /// [onError]  receives a user-visible error string.
  Future<void> startRecording({
    required void Function(String transcript) onResult,
    required void Function(String error) onError,
  }) async {
    if (_isListening) return;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    _onResult = onResult;
    _onError = onError;
    _isListening = true;
    _recordingStartedAt = DateTime.now();
    _silenceSince = null;

    try {
      if (!_recorderOpen) {
        await _recorder.openRecorder();
        _recorderOpen = true;
      }

      final dir = await getTemporaryDirectory();
      // pcm16WAV is the only codec in FlautoRecorderEngine that writes a real
      // container to disk (WAV header + 16-bit PCM). All other codecs — including
      // aacMP4 — write nothing to the file (writeData32 never calls
      // outputStream.write). WAV/PCM 16-bit is in OpenAI's supported format list.
      final tempPath = '${dir.path}/va_recording.wav';

      await _recorder.setSubscriptionDuration(
        const Duration(milliseconds: 100),
      );

      _progressSub = _recorder.onProgress!.listen((e) {
        if (!_isListening) return;
        _checkSilence(e.decibels ?? -100.0);
      });

      await _recorder.startRecorder(
        toFile: tempPath,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
        numChannels: 1,
      );
    } catch (e, st) {
      debugPrint('[STT-ERR] startRecorder() exception: $e');
      debugPrint('[STT-ERR] stack: $st');

      _isListening = false;
      _onResult = null;
      _onError = null;
      await _progressSub?.cancel();
      _progressSub = null;
      onError('Could not access the microphone: $e');
    }

    // Hard-cap: auto-stop after _kMaxDurationMs.
    if (_isListening) {
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(
        const Duration(milliseconds: _kMaxDurationMs),
        () {
          if (_isListening) {
            unawaited(stopRecording());
          }
        },
      );
    }
  }

  /// Stops recording and sends the captured audio to Whisper for transcription.
  /// [_onResult] is called with the transcript, or [_onError] on failure.
  Future<void> stopRecording() async {
    debugPrint('[STT-A] stopRecording() called _isListening=$_isListening');

    if (!_isListening) {
      debugPrint('[STT-A] stopRecording() early-exit: not listening');
      return;
    }

    _isListening = false;

    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    final elapsedMs = _recordingStartedAt != null
        ? DateTime.now().difference(_recordingStartedAt!).inMilliseconds
        : -1;

    debugPrint('[STT-B] elapsed=${elapsedMs}ms _onResult=${_onResult != null}');

    await _progressSub?.cancel();
    _progressSub = null;

    String? path;

    try {
      debugPrint('[STT-C] calling _recorder.stopRecorder()');
      path = await _recorder.stopRecorder();

      debugPrint(
        '[STT-D] stopRecorder() returned path=$path '
        '_onResult=${_onResult != null}',
      );
    } catch (e, st) {
      debugPrint('[STT-ERR] stopRecorder() exception: $e');
      debugPrint('[STT-ERR] stack: $st');

      final errorCb = _onError;
      _onResult = null;
      _onError = null;

      errorCb?.call(
        'Could not finish the microphone recording. Please try again.',
      );
      return;
    }

    if (path == null) {
      debugPrint('[STT-D] recorder returned a null path');

      final errorCb = _onError;
      _onResult = null;
      _onError = null;

      errorCb?.call(
        'The microphone did not produce a recording. Please try again.',
      );
      return;
    }

    if (_onResult == null) {
      debugPrint('[STT-D] result callback is unavailable');

      final errorCb = _onError;
      _onError = null;

      errorCb?.call('The recording could not be processed. Please try again.');
      return;
    }

    await _transcribe(filePath: path);
  }

  /// Stops recording and discards the audio without transcribing.
  /// Use this when the user manually cancels input.
  Future<void> cancelRecording() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    _onResult = null;
    _onError = null;
    if (!_isListening) return;
    _isListening = false;

    await _progressSub?.cancel();
    _progressSub = null;

    final path = await _recorder.stopRecorder();
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _checkSilence(double dBfs) {
    if (!_isListening || _recordingStartedAt == null) return;

    final now = DateTime.now();
    final elapsedMs = now.difference(_recordingStartedAt!).inMilliseconds;

    if (dBfs < _kSilenceThresholdDb) {
      _silenceSince ??= now;
      final heldMs = now.difference(_silenceSince!).inMilliseconds;
      if (heldMs >= _kSilenceHoldMs && elapsedMs >= _kMinSpeechMs) {
        unawaited(stopRecording());
      }
    } else {
      _silenceSince = null;
    }
  }

  /// Uploads [filePath] as Opus/WebM to the openai-proxy STT endpoint.
  /// The proxy hardcodes filename "audio.webm" server-side; sending actual WebM
  /// bytes ensures OpenAI's format detector (driven by filename extension) succeeds.
  Future<void> _transcribe({required String filePath}) async {
    debugPrint('[STT-E] _transcribe() entered  filePath=$filePath');
    final resultCb = _onResult;
    final errorCb = _onError;
    _onResult = null;
    _onError = null;

    try {
      final file = File(filePath);
      final exists = file.existsSync();
      final sizeBytes = exists ? file.lengthSync() : 0;
      debugPrint('[STT-F] file.exists=$exists  size=${sizeBytes}B');
      if (!exists) {
        debugPrint('[STT-F] recorded file does not exist');
        errorCb?.call('The microphone did not produce an audio file.');
        return;
      }

      if (sizeBytes <= 44) {
        debugPrint('[STT-F] WAV file contains no audio data');
        errorCb?.call(
          'No audio was captured. Please check the microphone and try again.',
        );
        return;
      }
      final bytes = await file.readAsBytes();
      debugPrint(
        '[STT-G] uploading ${bytes.length}B as audio/wav to ${OpenAiProxy.proxyUrl('/audio/transcriptions')}',
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(OpenAiProxy.proxyUrl('/audio/transcriptions')),
      );

      request.headers.addAll(OpenAiProxy.rawHeaders());

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: 'audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      debugPrint('[STT-H] sending MultipartRequest...');
      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      debugPrint(
        '[STT-I] status=${streamed.statusCode}  body=${body.length > 300 ? body.substring(0, 300) : body}',
      );

      if (streamed.statusCode == 401) {
        errorCb?.call('AI service authorization failed. Please sign in again.');
        return;
      }
      if (streamed.statusCode == 429) {
        errorCb?.call('OpenAI rate limit reached.');
        return;
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final snippet = body.length > 200 ? body.substring(0, 200) : body;
        errorCb?.call('Transcription error (${streamed.statusCode}): $snippet');
        return;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final text = (decoded['text'] as String? ?? '').trim();
      debugPrint(
        '[STT-J] transcript="${text.length > 80 ? text.substring(0, 80) : text}"  empty=${text.isEmpty}',
      );
      if (text.isEmpty) {
        errorCb?.call(
          'No speech was detected. Please speak clearly and try again.',
        );
        return;
      }
      debugPrint('[STT-K] calling resultCb  resultCb=${resultCb != null}');
      resultCb?.call(text);
    } catch (e) {
      debugPrint('[STT-ERR] _transcribe error: $e');
      errorCb?.call('Transcription error: $e');
    } finally {
      try {
        final temporaryFile = File(filePath);

        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } catch (e) {
        debugPrint('[STT] Temporary-file cleanup failed: $e');
      }
    } // <-- closes finally
  } // <-- closes _transcribe()

  void _resolvePlay() {
    if (_playCompleter != null && !_playCompleter!.isCompleted) {
      _playCompleter!.complete();
    }
  }

  void dispose() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    cancelSpeech();
    _progressSub?.cancel();
    _player.dispose();

    if (_recorderOpen) {
      _recorder.closeRecorder();
      _recorderOpen = false;
    }
  }
}

/// Global singleton — use this everywhere instead of instantiating directly.
final speechService = SpeechService();
