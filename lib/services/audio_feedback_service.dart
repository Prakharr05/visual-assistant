import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays short audio cues so the user always knows the app's state
/// without looking at the screen.
///
/// Since we can't bundle audio files without a build step,
/// this uses system-level tone generation as a fallback.
/// For production, add .wav files to assets/sounds/ and reference them.
class AudioFeedbackService {
  final AudioPlayer _player = AudioPlayer();

  /// Short beep — "I'm listening for your question"
  Future<void> playListeningBeep() async {
    try {
      // In production, use: await _player.play(AssetSource('sounds/listening.wav'));
      // For now, use a URL-based tone or system sound
      await _player.play(
        UrlSource('https://www.soundjay.com/buttons/beep-01a.mp3'),
      );
    } catch (e) {
      debugPrint('[Audio] Could not play beep: $e');
    }
  }

  /// Soft chime — "I heard you, now processing"
  Future<void> playProcessingChime() async {
    try {
      await _player.play(
        UrlSource('https://www.soundjay.com/buttons/beep-08b.mp3'),
      );
    } catch (e) {
      debugPrint('[Audio] Could not play chime: $e');
    }
  }

  /// Error tone — "Something went wrong"
  Future<void> playErrorTone() async {
    try {
      await _player.play(
        UrlSource('https://www.soundjay.com/buttons/beep-03.mp3'),
      );
    } catch (e) {
      debugPrint('[Audio] Could not play error tone: $e');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}