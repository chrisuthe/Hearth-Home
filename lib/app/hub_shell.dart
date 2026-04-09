import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'idle_controller.dart';
import '../models/photo_memory.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/ambient/ambient_overlays.dart';
import '../screens/timer/timer_screen.dart';
import '../services/timer_service.dart';
import '../screens/home/home_screen.dart';
import '../modules/media/media_screen.dart';
import '../modules/controls/controls_screen.dart';
import '../modules/cameras/cameras_screen.dart';
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
  PhotoMemory? _currentMemory;
  int _currentPage = _homeIndex;
  bool _quickTrayOpen = false;

  static const double _edgeZoneHeight = 80;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _pageController = PageController(initialPage: _homeIndex);
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? _homeIndex;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
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

  /// Builds an invisible edge-swipe zone that navigates to [targetPage]
  /// when dragged in [direction] (positive = down, negative = up).
  Widget _edgeSwipeZone({
    required AlignmentGeometry alignment,
    required int targetPage,
    required bool swipeDown,
  }) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        // Translucent so taps pass through to content below (e.g., zone
        // picker) while vertical drags are still captured by this zone.
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if ((swipeDown && v > 200) || (!swipeDown && v < -200)) {
            _onUserActivity();
            _pageController.animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        },
        child: SizedBox(
          width: double.infinity,
          height: _edgeZoneHeight,
        ),
      ),
    );
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

    // Wake from idle when a timer fires — deferred to avoid
    // notifyListeners() during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUserActivity());

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

  Widget _buildQuickTray() {
    final timerService = ref.watch(timerServiceProvider);
    return GestureDetector(
      // Tap scrim to dismiss
      onTap: () => setState(() => _quickTrayOpen = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Column(
          children: [
            const Spacer(),
            // Swipe down on the tray to dismiss
            GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 200) {
                  setState(() => _quickTrayOpen = false);
                }
              },
              onTap: () {}, // absorb taps on tray so scrim dismiss doesn't fire
              child: Container(
                margin: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _QuickAction(
                      icon: Icons.timer,
                      label: timerService.hasActiveTimers
                          ? timerService.statusLabel
                          : 'Timer',
                      active: timerService.hasActiveTimers,
                      onTap: () {
                        setState(() => _quickTrayOpen = false);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TimerScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Small handle indicator
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
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
      if (_quickTrayOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _quickTrayOpen = false);
        });
      }
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
        child: Stack(
          children: [
            // Layer 1: Photo background — always visible behind everything.
            // The AmbientScreen handles its own photo rotation and caching.
            AmbientScreen(
              key: _ambientKey,
              onMemoryChanged: (memory) {
                setState(() => _currentMemory = memory);
              },
            ),

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
                  children: [
                    const MediaScreen(),
                    const HomeScreen(),
                    const ControlsScreen(),
                    CamerasScreen(isActive: _currentPage == 3),
                    const SettingsScreen(),
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
                  IgnorePointer(
                    child: AmbientOverlays(
                      memoryLabel: _currentMemory?.memoryLabel,
                    ),
                  ),
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

            // Edge-swipe zones — invisible strips at top/bottom that navigate
            // on vertical drag. Sit above content so they always win the
            // gesture arena over inner scrollables.
            if (!idle.isIdle) ...[
              _edgeSwipeZone(
                alignment: Alignment.topCenter,
                targetPage: _pageCount - 1,
                swipeDown: true,
              ),
              // Bottom edge: swipe up to open quick actions tray
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (_) {},
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -200) {
                      _onUserActivity();
                      setState(() => _quickTrayOpen = true);
                    }
                  },
                  child: SizedBox(
                    width: double.infinity,
                    height: _edgeZoneHeight,
                  ),
                ),
              ),
            ],

            // Quick actions tray — slides up from bottom
            if (_quickTrayOpen && !idle.isIdle) _buildQuickTray(),

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

/// A single square item in the quick actions tray.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF646CFF).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: active
              ? Border.all(
                  color: const Color(0xFF646CFF).withValues(alpha: 0.5))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 28,
                color: active ? const Color(0xFF646CFF) : Colors.white70),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
