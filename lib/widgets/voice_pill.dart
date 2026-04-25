import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../services/voice_assistant_service.dart';

// ── Voice pill overlay ──────────────────────────────────────────────────────

/// Floating pill that shows voice assistant feedback at the bottom of the
/// screen. Watches [voiceAssistantStateProvider] and renders state-specific
/// content with slide-up / fade-out transitions.
///
/// Placed in the HubShell Stack above the page indicator dots. When the voice
/// assistant is idle the widget is fully transparent and ignores pointer events
/// so taps pass through to content below.
class VoicePillOverlay extends ConsumerStatefulWidget {
  const VoicePillOverlay({super.key});

  @override
  ConsumerState<VoicePillOverlay> createState() => _VoicePillOverlayState();
}

class _VoicePillOverlayState extends ConsumerState<VoicePillOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _dismissTimer;
  bool _visible = false;
  VoiceAssistantState _lastActiveState = const VoiceAssistantState();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onStateChanged(VoiceAssistantState state) {
    if (state.state == VoiceState.idle) {
      // Auto-dismiss 3 seconds after returning to idle.
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _visible = false);
      });
    } else {
      _dismissTimer?.cancel();
      _lastActiveState = state;
      if (!_visible) setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFeedback = ref.watch(
      hubConfigProvider.select((c) => c.showVoiceFeedback),
    );
    if (!showFeedback) return const SizedBox.shrink();

    final asyncState = ref.watch(voiceAssistantStateProvider);
    final voiceState = asyncState.valueOrNull ?? const VoiceAssistantState();

    // Track state transitions via post-frame callback to avoid setState
    // during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onStateChanged(voiceState);
    });

    final isIdle = voiceState.state == VoiceState.idle;
    final displayState = isIdle ? _lastActiveState : voiceState;

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: isIdle || !_visible,
          child: AnimatedSlide(
            offset: _visible && !isIdle
                ? Offset.zero
                : const Offset(0, 0.5),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _visible && !isIdle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _PillContent(
                state: displayState,
                pulseAnimation: _pulseController,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pill visual content ─────────────────────────────────────────────────────

class _PillContent extends StatelessWidget {
  final VoiceAssistantState state;
  final Animation<double> pulseAnimation;

  const _PillContent({
    required this.state,
    required this.pulseAnimation,
  });

  static const _accent = Color(0xFF646CFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _buildContent(),
      ),
    );
  }

  List<Widget> _buildContent() {
    switch (state.state) {
      case VoiceState.listening:
        return [
          FadeTransition(
            opacity: Tween<double>(begin: 0.4, end: 1.0)
                .animate(pulseAnimation),
            child: const Icon(Icons.mic, color: _accent, size: 44),
          ),
          const SizedBox(width: 10),
          const Text(
            'Listening...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w400,
            ),
          ),
        ];

      case VoiceState.processing:
        return [
          Flexible(
            child: Text(
              state.transcription ?? 'Processing...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: _accent,
            ),
          ),
        ];

      case VoiceState.responding:
        return [
          const Icon(Icons.volume_up, color: _accent, size: 44),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.responseText ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ];

      case VoiceState.error:
        return [
          const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 44),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.errorMessage ?? 'An error occurred',
              style: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 28,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ];

      case VoiceState.idle:
        return [
          const Text(
            '',
            style: TextStyle(fontSize: 14),
          ),
        ];
    }
  }
}
