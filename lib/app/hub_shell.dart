import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'idle_controller.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/ambient/ambient_overlays.dart';
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
        onTapDown: (_) => _onUserActivity(),
        onPanStart: (_) => _onUserActivity(),
        onPanUpdate: (_) => _onUserActivity(),
        child: Stack(
          children: [
            // Layer 1: Photo background — always visible behind everything.
            // The AmbientScreen handles its own photo rotation and caching.
            const AmbientScreen(),

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

            // Layer 3: Ambient overlays (clock, weather, memory label) —
            // only visible when idle. Uses a reversed animation so they
            // fade OUT when active screens fade IN.
            FadeTransition(
              opacity: ReverseAnimation(_fadeController),
              child: const IgnorePointer(
                child: AmbientOverlays(),
              ),
            ),

            // Event overlay layer (doorbell, alerts)
          ],
        ),
      ),
    );
  }
}
