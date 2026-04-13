import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service that speaks GPT-4o responses to the user.
/// Configured for clarity: moderate speed, natural pitch, consistent volume.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  /// Initialize TTS engine with accessibility-optimized settings.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Speech rate: 0.0 (slowest) to 1.0 (fastest)
    // 0.45 is a comfortable listening speed for most users
    await _tts.setSpeechRate(0.45);

    // Natural pitch
    await _tts.setPitch(1.0);

    // Full volume
    await _tts.setVolume(1.0);

    // Use the best available English voice
    if (Platform.isIOS) {
      // iOS has excellent built-in voices
      await _tts.setLanguage('en-US');
      // Try to use the enhanced Siri voice
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } else if (Platform.isAndroid) {
      await _tts.setLanguage('en-US');
      // Use Google's TTS engine if available
      final engines = await _tts.getEngines;
      if (engines is List) {
        for (final engine in engines) {
          if (engine.toString().contains('google')) {
            await _tts.setEngine(engine.toString());
            break;
          }
        }
      }
    }

    // Track speaking state
    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('[TTS] Error: $msg');
    });

    _isInitialized = true;
    debugPrint('[TTS] Ready');
  }

  /// Speak the given text aloud.
  ///
  /// If already speaking, stops current speech and starts new.
  /// Returns a Future that completes when speech finishes.
  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();

    // Stop any ongoing speech
    if (_isSpeaking) {
      await _tts.stop();
    }

    debugPrint('[TTS] Speaking: $text');
    _isSpeaking = true;
    await _tts.speak(text);
  }

  /// Stop speaking immediately.
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Adjust speech rate (0.0 to 1.0).
  /// Called via keyboard shortcuts or accessibility settings.
  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  }

  /// Clean up resources.
  Future<void> dispose() async {
    await _tts.stop();
  }
}