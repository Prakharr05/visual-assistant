import 'package:flutter/foundation.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';

class HotwordService {
  PorcupineManager? _porcupineManager;
  final String _accessKey;
  VoidCallback? onWakeWordDetected;
  bool _isListening = false;

  HotwordService({required String accessKey}) : _accessKey = accessKey;

  bool get isListening => _isListening;

  Future<void> start() async {
    if (_porcupineManager != null) return;

    try {
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey,
        [], // No custom keyword paths needed for now
        _onWakeWord,
        errorCallback: (dynamic error) {
          debugPrint('[HotwordService] Error: $error');
        },
      );

      await _porcupineManager!.start();
      _isListening = true;
      debugPrint('[HotwordService] Listening for wake word...');
    } catch (e) {
      debugPrint('[HotwordService] Failed to start: $e');
      rethrow;
    }
  }

  void _onWakeWord(int keywordIndex) {
    debugPrint('[HotwordService] Wake word detected!');
    onWakeWordDetected?.call();
  }

  Future<void> pause() async {
    if (_porcupineManager != null && _isListening) {
      await _porcupineManager!.stop();
      _isListening = false;
    }
  }

  Future<void> resume() async {
    if (_porcupineManager != null && !_isListening) {
      await _porcupineManager!.start();
      _isListening = true;
    }
  }

  Future<void> dispose() async {
    await _porcupineManager?.stop();
    await _porcupineManager?.delete();
    _porcupineManager = null;
    _isListening = false;
  }
}