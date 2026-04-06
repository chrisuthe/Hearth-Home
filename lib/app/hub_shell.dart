import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'idle_controller.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/ambient/ambient_overlays.dart';
import '../screens/timer/timer_screen.dart';
import '../services/timer_service.dart';
import '../screens/home/home_screen.dart';
import '../screens/media/media_screen.dart';
import '../screens/controls/controls_screen.dart';
import '../screens/cameras/cameras_screen.dart';
import '../screens/settings/settings_screen.dart';

/// The main shell that manages the two-layer navigation model.
///
/// Three visual layers, bottom to top:
/// 1. Photo background — always visible, provides the ambient photo behind
///    every screen. Continuously rotates Immich memories.
/// 2. Active layer — PageView with screens. Has a dark scrim so content
///    is readable over the photo. Fades OUT when idle.
/// 3. Ambient overlays — clock, weather, memory label. Fades IN when idle.
///
/// Screen order (horizontal swipe):
///   Media ← Home → Controls → Cameras → Settings
class HubShell extends ConsumerStatefulWidget {
  const HubShell({super.key});

  @override
  ConsumerState<HubShell> createState() => _HubShellState();
}

class _HubShellState extends ConsumerState<HubShell>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _fadeController;

  /// Home sits at index 1. Media is left (0), Controls+ are right (2-4).
  static const int _homeIndex = 1;
  static const int _pageCount = 5;
  late final FocusNode _focusNode;
  final _ambientKey = GlobalKey<AmbientScreenState>();

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _pageController = PageController(initialPage: _homeIndex);
    // Controls the active/ambient crossfade:
    // 0.0 = idle (ambient overlays visible, active screens hidden)
    // 1.0 = active (screens visible, ambient overlays hidden)
    // Starts at 0.0 so the photo display is the first thing visible.
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onUserActivity() {
    ref.read(idleControllerProvider).onUserActivity();
  }

  /// Handles arrow key navigation for desktop testing.
  /// Left/Right move between screens, Up = Home, Down = Settings.
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    _onUserActivity();

    final idle = ref.read(idleControllerProvider);
    if (idle.isIdle) {
      _pageController.jumpToPage(_homeIndex);
      return;
    }

    final currentPage = _pageController.page?.round() ?? _homeIndex;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (currentPage > 0) {
        _pageController.animateToPage(
          currentPage - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (currentPage < _pageCount - 1) {
        _pageController.animateToPage(
          currentPage + 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _pageController.animateToPage(
        _pageCount - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.home) {
      _pageController.animateToPage(
        _homeIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Full-screen alert overlay when one or more timers have fired.
  /// Wakes the display from idle and shows a big "Time's up!" with
  /// the countdown rings. Tap anywhere to dismiss all fired timers.
  Widget _buildTimerAlert() {
    final timerService = ref.watch(timerServiceProvider);
    final fired = timerService.firedTimers;
    if (fired.isEmpty) return const SizedBox.shrink();

    // Wake from idle when a timer fires
    _onUserActivity();

    return GestureDetector(
      onTap: () => timerService.dismissAllFired(),
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, size: 48, color: Color(0xFFFF9800)),
              const SizedBox(height: 16),
              Text(
                fired.length == 1 ? "Time's up!" : "${fired.length} timers done!",
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w200,
                  color: Color(0xFFFF9800),
                ),
              ),
              const SizedBox(height: 32),
              // Show the fired timer rings
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: fired.map((t) => TimerDisplay(
                  timer: t,
                  size: fired.length == 1 ? 220 : 160,
                )).toList(),
              ),
              const SizedBox(height: 32),
              Text(
                'Tap anywhere to dismiss',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idle = ref.watch(idleControllerProvider);

    // Drive the crossfade: forward = show active screens, reverse = show ambient
    if (idle.isIdle) {
      _fadeController.reverse();
    } else {
      _fadeController.forward();
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Only track activity when not idle — during idle, taps are handled
        // by the ambient overlay (wake) and chevron buttons (skip photo).
        // This prevents the skip buttons from accidentally waking the screen.
        onTapDown: idle.isIdle ? null : (_) => _onUserActivity(),
        onPanStart: (_) => _onUserActivity(),
        onPanUpdate: (_) => _onUserActivity(),
        child: Stack(
          children: [
            // Layer 1: Photo background — always visible behind everything.
            // The AmbientScreen handles its own photo rotation and caching.
            AmbientScreen(key: _ambientKey),

            // Layer 2: Active screens with dark scrim — fades in on activity.
            // The scrim ensures text/controls are readable over the photo.
            FadeTransition(
              opacity: _fadeController,
              child: IgnorePointer(
                ignoring: idle.isIdle,
                child: PageView(
                  controller: _pageController,
                  physics: idle.isIdle
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  children: const [
                    MediaScreen(),
                    HomeScreen(),
                    ControlsScreen(),
                    CamerasScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
            ),

            // Layer 3: Ambient overlays + photo skip buttons —
            // only visible when idle. Uses a reversed animation so they
            // fade OUT when active screens fade IN.
            FadeTransition(
              opacity: ReverseAnimation(_fadeController),
              child: IgnorePointer(
                ignoring: !idle.isIdle,
                child: Stack(
                children: [
                  // Tap anywhere on the ambient display to wake — but the
                  // chevron buttons sit on top and absorb their own taps.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: idle.isIdle
                        ? () {
                            _onUserActivity();
                            _pageController.jumpToPage(_homeIndex);
                          }
                        : null,
                    child: const SizedBox.expand(),
                  ),
                  const IgnorePointer(child: AmbientOverlays()),
                  // Skip buttons — subtle arrows on the left/right edges.
                  // Tapping these advances photos without waking the display.
                  if (idle.isIdle) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _ambientKey.currentState?.skipBack(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.chevron_left,
                                color: Colors.white.withValues(alpha: 0.4),
                                size: 28),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _ambientKey.currentState?.skipForward(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.chevron_right,
                                color: Colors.white.withValues(alpha: 0.4),
                                size: 28),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              ),
            ),

            // Layer 4: Timer alert — full-screen overlay when a timer fires.
            // Shows on top of everything (including ambient) so you never
            // miss a timer, even if the display is idle showing photos.
            _buildTimerAlert(),

            // Event overlay layer (doorbell, alerts)
          ],
        ),
      ),
    );
  }
}
