import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'idle_controller.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/media/media_screen.dart';
import '../screens/controls/controls_screen.dart';
import '../screens/cameras/cameras_screen.dart';
import '../screens/settings/settings_screen.dart';

/// The main shell that manages the two-layer navigation model.
///
/// Layer 1 (Active): A horizontal PageView with snapping physics.
/// Screen order: Media <- Home -> Controls -> Cameras -> Settings
/// Home is the center position (index 1).
///
/// Layer 2 (Ambient): Full-screen photo display that fades in after
/// the idle timeout and fades out on any touch. Tapping ambient
/// always returns to the Home screen.
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _homeIndex);
    // Controls the ambient layer opacity: 0 = active visible, 1 = ambient visible.
    // 800ms gives a gentle crossfade that feels natural on the kiosk display.
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onUserActivity() {
    ref.read(idleControllerProvider).onUserActivity();
  }

  @override
  Widget build(BuildContext context) {
    final idle = ref.watch(idleControllerProvider);

    // Drive the crossfade animation based on idle state.
    // forward() and reverse() are no-ops if already at the target value,
    // so calling them every build is safe and keeps the logic declarative.
    if (idle.isIdle) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }

    return GestureDetector(
      // translucent so the PageView still receives scroll gestures
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _onUserActivity(),
      onPanStart: (_) => _onUserActivity(),
      onPanUpdate: (_) => _onUserActivity(),
      child: Stack(
        children: [
          // Active layer: horizontal PageView with all screens.
          // Disabled scrolling when idle so stray touches don't change pages
          // while the ambient overlay is visible.
          PageView(
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

          // Ambient layer: fades in over the active screens when idle.
          // FadeTransition is driven by _fadeController so the crossfade
          // animates smoothly rather than popping.
          FadeTransition(
            opacity: _fadeController,
            child: IgnorePointer(
              // Only accept taps when the ambient layer is actually visible.
              // This prevents the ambient GestureDetector from stealing taps
              // that should go to the active layer underneath.
              ignoring: !idle.isIdle,
              child: GestureDetector(
                onTap: () {
                  _onUserActivity();
                  // Always return to the Home screen when waking from ambient.
                  // Users expect a consistent landing point after idle.
                  _pageController.jumpToPage(_homeIndex);
                },
                child: const AmbientScreen(),
              ),
            ),
          ),

          // Event overlay layer (doorbell, alerts) — wired in Task 15
        ],
      ),
    );
  }
}
