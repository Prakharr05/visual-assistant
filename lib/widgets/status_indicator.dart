import 'package:flutter/material.dart';

/// The app's current processing state.
enum AssistantState {
  idle,       // Waiting for wake word
  listening,  // Hearing the user's question
  processing, // Capturing image + calling GPT-4o
  speaking,   // Reading the answer aloud
  error,      // Something went wrong
}

/// Large pulsing circle that shows the current state.
///
/// Even though this is a visual indicator (and the target user is blind),
/// it's useful for:
/// 1. Sighted helpers watching over someone's shoulder
/// 2. Demos and interviews
/// 3. Partially sighted users who can see color/motion
class StatusIndicator extends StatefulWidget {
  final AssistantState state;
  final String statusText;

  const StatusIndicator({
    super.key,
    required this.state,
    required this.statusText,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pulse when actively listening or processing
    if (widget.state == AssistantState.listening ||
        widget.state == AssistantState.processing) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _stateColor() {
    switch (widget.state) {
      case AssistantState.idle:
        return const Color(0xFF4A90D9); // Calm blue
      case AssistantState.listening:
        return const Color(0xFF34C759); // Active green
      case AssistantState.processing:
        return const Color(0xFFFF9F0A); // Amber
      case AssistantState.speaking:
        return const Color(0xFF5E5CE6); // Purple
      case AssistantState.error:
        return const Color(0xFFFF3B30); // Red
    }
  }

  IconData _stateIcon() {
    switch (widget.state) {
      case AssistantState.idle:
        return Icons.hearing;
      case AssistantState.listening:
        return Icons.mic;
      case AssistantState.processing:
        return Icons.visibility;
      case AssistantState.speaking:
        return Icons.volume_up;
      case AssistantState.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.4), width: 3),
            ),
            child: Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.3),
                ),
                child: Icon(
                  _stateIcon(),
                  size: 48,
                  color: color,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          widget.statusText,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}