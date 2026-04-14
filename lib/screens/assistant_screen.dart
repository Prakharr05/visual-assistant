import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

import '../services/hotword_service.dart';
import '../services/stt_service.dart';
import '../services/vision_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/audio_feedback_service.dart';
import '../widgets/status_indicator.dart';
import 'dart:async';
import 'package:flutter/services.dart';

/// The main screen. No buttons to tap — everything is voice-triggered.
///
/// Flow:
/// 1. App starts → speaks welcome message → hotword engine listens
/// 2. User says "Jarvis" (or custom wake word)
/// 3. Beep plays → STT listens for the question
/// 4. Camera captures a frame silently
/// 5. Image + question sent to GPT-4o
/// 6. Response spoken aloud via TTS
/// 7. Back to step 2
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with WidgetsBindingObserver {
  // Services
  late final HotwordService _hotword;
  final SttService _stt = SttService();
  final VisionService _vision = VisionService();
  late final LlmService _llm;
  final TtsService _tts = TtsService();
  final AudioFeedbackService _audio = AudioFeedbackService();

  // State
  AssistantState _state = AssistantState.idle;
  String _statusText = 'Initializing...';
  String _lastQuestion = '';
  String _lastAnswer = '';
  String _partialTranscript = '';
  bool _isFullyInitialized = false;
  bool _hotwordEnabled = false;
  String? _capturedImage;
  StreamSubscription? _volumeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services with API keys from .env
    _hotword = HotwordService(
      accessKey: dotenv.env['PICOVOICE_ACCESS_KEY'] ?? '',
    );
    _llm = LlmService(
      apiKey: dotenv.env['OPENAI_API_KEY'] ?? '',
    );

    // Wire up the wake word callback
    _hotword.onWakeWordDetected = _onWakeWord;

    // Listen for volume button press as hands-free trigger
    const volumeChannel = EventChannel('volume_key_channel');
    _volumeSub = volumeChannel.receiveBroadcastStream().listen((event) {
      _onWakeWord();
    });

    // Start initialization
    _initializeAll();
  }

  /// Initialize all services in sequence.
  Future<void> _initializeAll() async {
    try {
      // 1. Request permissions
      _updateState(AssistantState.idle, 'Requesting permissions...');
      await _requestPermissions();

      // 2. Init TTS first so we can speak status updates
      await _tts.initialize();

      // 3. Init camera
      _updateState(AssistantState.idle, 'Starting camera...');
      await _vision.initialize();

      // 4. Init speech recognition
      _updateState(AssistantState.idle, 'Setting up speech...');
      await _stt.initialize();

      // 5. Start hotword engine (optional — works without Picovoice key)
      final picoKey = dotenv.env['PICOVOICE_ACCESS_KEY'] ?? '';
      if (picoKey.isNotEmpty && picoKey != 'your-picovoice-access-key-here') {
        _updateState(AssistantState.idle, 'Starting wake word...');
        try {
          await _hotword.start();
          _hotwordEnabled = true;
        } catch (e) {
          debugPrint('[Init] Hotword failed, tap-only mode: $e');
          _hotwordEnabled = false;
        }
      } else {
        _hotwordEnabled = false;
        debugPrint('[Init] No Picovoice key — tap-only mode');
      }

      // All ready!
      _isFullyInitialized = true;
      if (_hotwordEnabled) {
        _updateState(AssistantState.idle, 'Say "Jarvis" to ask a question');
        await _tts.speak(
          'Visual assistant ready. Say Jarvis to ask a question.',
        );
      } else {
        _updateState(AssistantState.idle, 'Tap the mic button to ask a question');
        await _tts.speak(
          'Visual assistant ready. Tap the microphone button to ask a question.',
        );
      }
    } catch (e) {
      _updateState(
        AssistantState.error,
        'Setup failed: ${e.toString().substring(0, 80)}',
      );
      await _tts.speak(
        'Sorry, I had trouble starting up. Please restart the app.',
      );
    }
  }

  /// Request microphone and camera permissions.
  Future<void> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final camStatus = await Permission.camera.request();

    if (micStatus.isDenied || camStatus.isDenied) {
      await _tts.speak(
        'I need microphone and camera permissions to help you. '
        'Please grant them in your phone settings.',
      );
      throw Exception('Permissions denied');
    }
  }

  // ─── Pipeline stages ─────────────────────────────────────────────

  /// Stage 1: Wake word detected.
  void _onWakeWord() async {
    if (_state != AssistantState.idle) return;

    debugPrint('[Pipeline] Wake word triggered');

    if (_hotwordEnabled) await _hotword.pause();

    // Cancel any leftover STT session
    await _stt.cancel();

    setState(() {
      _partialTranscript = '';
      _lastQuestion = '';
      _capturedImage = null;
    });

    _updateState(AssistantState.listening, 'Listening...');

    // Capture image RIGHT NOW while the user is still pointing the camera
    _vision.captureBase64Frame().then((img) {
      _capturedImage = img;
      debugPrint('[Pipeline] Image pre-captured');
    });

    bool questionSent = false;

    await _stt.startListening(
      onResult: (text, isFinal) {
        debugPrint('[Pipeline] STT result: "$text" | final: $isFinal');
        setState(() => _partialTranscript = text);

        if (isFinal && text.isNotEmpty && !questionSent) {
          questionSent = true;
          _onQuestionReceived(text);
        }
      },
      onDone: () {
        debugPrint('[Pipeline] STT done | partial: "$_partialTranscript" | questionSent: $questionSent');
        if (!questionSent && _state == AssistantState.listening) {
          if (_partialTranscript.isNotEmpty) {
            questionSent = true;
            _onQuestionReceived(_partialTranscript);
          } else {
            _handleNoSpeech();
          }
        }
      },
    );
  }

  /// Stage 2: User's question is transcribed.
  void _onQuestionReceived(String question) async {
    debugPrint('[Pipeline] Question received: "$question" | State: $_state');

    if (_state != AssistantState.listening) {
      debugPrint('[Pipeline] Ignoring stale question');
      return;
    }

    setState(() {
      _lastQuestion = question;
      _partialTranscript = '';
    });

    _updateState(AssistantState.processing, 'Thinking...');

    // Use pre-captured image, or capture now as fallback
    final imageBase64 = _capturedImage ?? await _vision.captureBase64Frame();

    if (imageBase64 == null) {
      await _tts.speak('Sorry, I could not capture an image. Please try again.');
      _resetToIdle();
      return;
    }

    final answer = await _llm.askAboutImage(
      question: question,
      imageBase64: imageBase64,
    );

    _onAnswerReceived(answer);
  }

  /// Stage 3: GPT-4o response received — speak it.
  void _onAnswerReceived(String answer) async {
    debugPrint('[Pipeline] Answer: $answer');

    setState(() => _lastAnswer = answer);
    _updateState(AssistantState.speaking, 'Speaking...');

    await _tts.speak(answer);

    // Small delay to let TTS finish, then reset
    await Future.delayed(const Duration(milliseconds: 500));
    _resetToIdle();
  }

  /// Handle case where STT detected nothing.
  void _handleNoSpeech() async {
    await _tts.speak(_hotwordEnabled
        ? "I didn't hear a question. Say Jarvis to try again."
        : "I didn't hear a question. Tap the mic button to try again.");
    _resetToIdle();
  }

  /// Return to idle state, resume hotword listening.
  void _resetToIdle() async {
    final idleText = _hotwordEnabled
        ? 'Say "Jarvis" to ask a question'
        : 'Tap the mic button to ask a question';
    _updateState(AssistantState.idle, idleText);
    _partialTranscript = '';
    if (_hotwordEnabled) await _hotword.resume();
  }

  /// Update state and status text together.
  void _updateState(AssistantState state, String text) {
    if (mounted) {
      setState(() {
        _state = state;
        _statusText = text;
      });
    }
  }

  // ─── Lifecycle ────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause/resume hotword when app goes to background/foreground
    if (state == AppLifecycleState.paused) {
      _hotword.pause();
    } else if (state == AppLifecycleState.resumed && _isFullyInitialized) {
      if (_state == AssistantState.idle) {
        _hotword.resume();
      }
    }
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _hotword.dispose();
    _vision.dispose();
    _tts.dispose();
    _audio.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────────

  Color _stateAccentColor() {
    switch (_state) {
      case AssistantState.idle:
        return const Color(0xFF3B82F6);
      case AssistantState.listening:
        return const Color(0xFF22C55E);
      case AssistantState.processing:
        return const Color(0xFFF59E0B);
      case AssistantState.speaking:
        return const Color(0xFF8B5CF6);
      case AssistantState.error:
        return const Color(0xFFEF4444);
    }
  }

  IconData _stateIcon() {
    switch (_state) {
      case AssistantState.idle:
        return Icons.mic_none_rounded;
      case AssistantState.listening:
        return Icons.graphic_eq_rounded;
      case AssistantState.processing:
        return Icons.visibility_rounded;
      case AssistantState.speaking:
        return Icons.volume_up_rounded;
      case AssistantState.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _stateAccentColor();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          // ── Layer 1: Full-screen camera viewfinder ──
          if (_vision.isInitialized && _vision.controller != null)
            Positioned.fill(
              child: CameraPreview(_vision.controller!),
            )
          else
            Positioned.fill(
              child: Container(color: const Color(0xFF0A0A0A)),
            ),

          // ── Layer 2: Gradient overlay for readability ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.85),
                  ],
                  stops: const [0.0, 0.15, 0.5, 0.85],
                ),
              ),
            ),
          ),

          // ── Layer 3: Top status bar ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                          boxShadow: [
                            BoxShadow(color: accent.withOpacity(0.6), blurRadius: 6),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Visual Assistant',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(0.3), width: 0.5),
                  ),
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Layer 4: Center state indicator (shows during non-idle states) ──
          if (_state != AssistantState.idle)
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.5),
                  border: Border.all(color: accent.withOpacity(0.5), width: 2),
                ),
                child: Icon(
                  _stateIcon(),
                  size: 40,
                  color: accent,
                ),
              ),
            ),

          // ── Layer 5: Conversation panel at bottom ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding + 16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111).withOpacity(0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_partialTranscript.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _partialTranscript,
                          style: TextStyle(
                            fontSize: 14,
                            color: const Color(0xFF22C55E).withOpacity(0.8),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    if (_lastQuestion.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Q  ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _lastQuestion,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_lastAnswer.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('A  ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accent.withOpacity(0.6),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _lastAnswer,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                height: 1.5,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                    if (_partialTranscript.isEmpty && _lastQuestion.isEmpty && _lastAnswer.isEmpty)
                      Center(
                        child: Text(
                          _state == AssistantState.idle ? 'Tap the mic to ask a question' : _statusText,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 6: Mic button — ALWAYS in same position ──
          Positioned(
            bottom: bottomPadding + 210,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _state == AssistantState.idle ? _onWakeWord : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _state == AssistantState.idle
                        ? accent
                        : accent.withOpacity(0.3),
                    boxShadow: _state == AssistantState.idle
                        ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)]
                        : [],
                  ),
                  child: Icon(
                    _stateIcon(),
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}