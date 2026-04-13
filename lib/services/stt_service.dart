import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Handles speech-to-text after the wake word fires.
/// Listens for the user's question and returns the transcription.
class SttService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  /// One-time init — checks mic permission and locale availability.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        debugPrint('[STT] Error: ${error.errorMsg}');
      },
      onStatus: (status) {
        debugPrint('[STT] Status: $status');
      },
    );

    if (!_isInitialized) {
      debugPrint('[STT] Failed to initialize speech recognition');
    }
    return _isInitialized;
  }

  /// Start listening for the user's question.
  ///
  /// [onResult] fires with partial and final results.
  /// [onDone] fires when the user stops speaking.
  /// [listenDuration] is the max time to listen (default 10 seconds).
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    VoidCallback? onDone,
    Duration listenDuration = const Duration(seconds: 15),
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    // Make sure previous session is fully stopped
    if (_speech.isListening) {
      await _speech.stop();
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      onSoundLevelChange: (level) {
        // Keeps the listener active
      },
      listenFor: listenDuration,
      pauseFor: const Duration(seconds: 5),
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );

    // Wait for listening to actually finish, then call onDone
    _speech.statusListener = (status) {
      debugPrint('[STT] Status changed: $status');
      if (status == 'done' || status == 'notListening') {
        onDone?.call();
      }
    };
  }
  /// Stop listening early.
  Future<void> stopListening() async {
    await _speech.stop();
  }

  /// Cancel without processing partial results.
  Future<void> cancel() async {
    await _speech.cancel();
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _isInitialized;
}