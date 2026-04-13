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

    // Pause hotword engine
    if (_hotwordEnabled) await _hotword.pause();

    // Clear all previous data immediately
    setState(() {
      _partialTranscript = '';
      _lastQuestion = '';
    });

    // Move to listening state FIRST so the UI updates
    _updateState(AssistantState.listening, 'Listening...');

    // Start speech recognition immediately — no delay
    
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
        // Only handle "no speech" if we never got a final result
        // AND we're still in listening state
        if (!questionSent && _state == AssistantState.listening) {
          if (_partialTranscript.isNotEmpty) {
            // We heard something but it never became "final" — use it anyway
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
    
    // Ignore if we're not in listening state (stale callback)
    if (_state != AssistantState.listening) {
      debugPrint('[Pipeline] Ignoring stale question');
      return;
    }

    setState(() {
      _lastQuestion = question;
      _partialTranscript = '';
    });

    // Play processing chime
    await _audio.playProcessingChime();
    _updateState(AssistantState.processing, 'Looking...');

    // Capture camera frame
    final imageBase64 = await _vision.captureBase64Frame();

    if (imageBase64 == null) {
      await _tts.speak(
        'Sorry, I could not capture an image. Please try again.',
      );
      _resetToIdle();
      return;
    }

    // Send to GPT-4o
    _updateState(AssistantState.processing, 'Thinking...');
    final answer = await _llm.askAboutImage(
      question: question,
      imageBase64: imageBase64,
    );

    // Speak the answer
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
    _lastQuestion = '';
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
    WidgetsBinding.instance.removeObserver(this);
    _hotword.dispose();
    _vision.dispose();
    _tts.dispose();
    _audio.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            // Camera preview (small, top of screen — for sighted observers)
            if (_vision.isInitialized && _vision.controller != null)
              Container(
                height: 200,
                margin: const EdgeInsets.all(16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: CameraPreview(_vision.controller!),
              ),

            // Main status area (center of screen)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: StatusIndicator(
                    state: _state,
                    statusText: _statusText,
                  ),
                ),
              ),
            ),

            // Transcript and answer display (bottom — for demos)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show partial transcript while listening
                  if (_partialTranscript.isNotEmpty) ...[
                    Text(
                      'Hearing: $_partialTranscript',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Last question
                  if (_lastQuestion.isNotEmpty) ...[
                    Text(
                      'Q: $_lastQuestion',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Last answer
                  if (_lastAnswer.isNotEmpty)
                    Text(
                      'A: $_lastAnswer',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),

                  // Empty state
                  if (_lastQuestion.isEmpty && _partialTranscript.isEmpty)
                    Text(
                      'Your conversation will appear here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),

      // Manual trigger button (tap anywhere fallback)
      floatingActionButton: _state == AssistantState.idle
          ? Padding(
              padding: const EdgeInsets.only(bottom: 65),
              child: FloatingActionButton.large(
                onPressed: _onWakeWord,
                backgroundColor: const Color(0xFF1A73E8),
                tooltip: 'Tap to ask a question',
                child: const Icon(Icons.mic, size: 36),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}