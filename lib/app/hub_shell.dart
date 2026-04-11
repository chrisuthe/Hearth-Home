import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'idle_controller.dart';
import 'page_indicator.dart';
import '../models/photo_memory.dart';
import '../modules/module_registry.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/timer/timer_screen.dart';
import '../services/timer_service.dart';
import '../screens/home/home_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/sendspin/sendspin_service.dart';

/// The main shell that manages the layered navigation model.
///
/// Two visual layers, bottom to top:
/// 1. Photo background — always visible, continuously rotates Immich memories.
/// 2. Active layer — PageView with screens over the photo background.
///    Home screen is transparent; other screens use a dark scrim.
///
/// Screen order (horizontal swipe):
///   Media ← Home → Controls → Cameras → Settings
class HubShell extends ConsumerStatefulWidget {
  const HubShell({super.key});

  @override
  ConsumerState<HubShell> createState() => _HubShellState();
}

class _HubShellState extends ConsumerState<HubShell> {
  PageController? _pageController;

  int _homeIndex = 0;
  int _pageCount = 0;
  late final FocusNode _focusNode;
  final _ambientKey = GlobalKey<AmbientScreenState>();
  PhotoMemory? _currentMemory;
  int _currentPage = 0;
  bool _menu1Open = false;
  bool _menu2Open = false;
  static const double _edgeZoneHeight = 80;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _onUserActivity() {
    ref.read(idleControllerProvider).onUserActivity();
  }

  String? _edgeFor(String action) {
    final config = ref.read(hubConfigProvider);
    if (config.topSwipeAction == action) return 'top';
    if (config.bottomSwipeAction == action) return 'bottom';
    return null;
  }

  Widget _configEdgeSwipeZone({
    required AlignmentGeometry alignment,
    required String action,
    required bool swipeDown,
  }) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if ((swipeDown && v > 200) || (!swipeDown && v < -200)) {
            _onUserActivity();
            _dispatchSwipeAction(action);
          }
        },
        child: const SizedBox(
          width: double.infinity,
          height: _edgeZoneHeight,
        ),
      ),
    );
  }

  void _dispatchSwipeAction(String action) {
    switch (action) {
      case 'menu1':
        setState(() { _menu1Open = true; _menu2Open = false; });
      case 'menu2':
        setState(() { _menu2Open = true; _menu1Open = false; });
      case 'settings':
        _pageController!.animateToPage(
          _pageCount - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      case 'nextScreen':
        final current = _pageController!.page?.round() ?? _homeIndex;
        if (current < _pageCount - 1) {
          _pageController!.animateToPage(current + 1,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      case 'previousScreen':
        final current = _pageController!.page?.round() ?? _homeIndex;
        if (current > 0) {
          _pageController!.animateToPage(current - 1,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
    }
  }

  /// Handles arrow key navigation for desktop testing.
  /// Left/Right move between screens, Up = Home, Down = Settings.
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    _onUserActivity();

    final currentPage = _pageController!.page?.round() ?? _homeIndex;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (currentPage > 0) {
        _pageController!.animateToPage(
          currentPage - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (currentPage < _pageCount - 1) {
        _pageController!.animateToPage(
          currentPage + 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _pageController!.animateToPage(
        _pageCount - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.home) {
      _pageController!.animateToPage(
        _homeIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildMenu1({required bool fromTop}) {
    return _MenuTray(
      fromTop: fromTop,
      onDismiss: () => setState(() => _menu1Open = false),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Menu1TimerAction(
            onTap: () {
              setState(() => _menu1Open = false);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TimerScreen()),
              );
            },
          ),
          const SizedBox(width: 12),
          _QuickAction(
            icon: Icons.settings,
            label: 'Settings',
            onTap: () {
              setState(() => _menu1Open = false);
              _pageController!.animateToPage(
                _pageCount - 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenu2({required bool fromTop}) {
    return _MenuTray(
      fromTop: fromTop,
      onDismiss: () => setState(() => _menu2Open = false),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Volume', style: TextStyle(fontSize: 12, color: Colors.white54)),
          SizedBox(height: 4),
          _SystemVolumeSlider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);
    final idleController = ref.read(idleControllerProvider);

    final modules = ref.watch(enabledModulesProvider);
    final hasCustomOrder = config.moduleOrder.isNotEmpty;
    // With custom ordering, all modules go right of Home.
    // With default ordering, negative defaultOrder goes left.
    final leftModules = hasCustomOrder
        ? <dynamic>[]
        : modules.where((m) => m.defaultOrder < 0).toList();
    final rightModules = hasCustomOrder
        ? modules
        : modules.where((m) => m.defaultOrder >= 0).toList();
    final homeIndex = leftModules.length;
    _pageCount = leftModules.length + 1 + rightModules.length + 1; // +Home +Settings

    // Recreate PageController when the module layout changes.
    if (_pageController == null || _homeIndex != homeIndex) {
      _homeIndex = homeIndex;
      _pageController?.dispose();
      _pageController = PageController(initialPage: homeIndex);
      _currentPage = homeIndex;
      _pageController!.addListener(() {
        final page = _pageController!.page?.round() ?? _homeIndex;
        if (page != _currentPage) setState(() => _currentPage = page);
      });
      idleController.onTimeout = () {
        _pageController?.animateToPage(
          _homeIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      };
    }

    final pages = <Widget>[
      ...leftModules.map((m) => m.buildScreen(
          isActive: _currentPage == leftModules.indexOf(m))),
      HomeScreen(
        memoryLabel: _currentMemory?.memoryLabel,
        onSkipPhoto: () => _ambientKey.currentState?.skipForward(),
        onSkipPhotoBack: () => _ambientKey.currentState?.skipBack(),
        onChevronTap: () => _onUserActivity(),
        onNowPlayingTap: () {
          // Navigate to Media screen (first left module)
          final mediaIndex = leftModules.indexWhere((m) => m.id == 'media');
          if (mediaIndex >= 0) {
            _onUserActivity();
            _pageController!.animateToPage(
              mediaIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        },
      ),
      ...rightModules.map((m) => m.buildScreen(
          isActive: _currentPage == homeIndex + 1 + rightModules.indexOf(m))),
      const SettingsScreen(),
    ];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _onUserActivity(),
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

            // Layer 2: Active screens — PageView over the photo background.
            PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              children: pages,
            ),

            // Page position indicator — dot row at the bottom center.
            // Positioned above the bottom edge-swipe zone so it does
            // not interfere with vertical drag gestures.
            Positioned(
              bottom: _edgeZoneHeight + 8,
              left: 0,
              right: 0,
              child: Center(
                child: PageIndicator(
                  pageCount: _pageCount,
                  currentPage: _currentPage,
                ),
              ),
            ),

            // Edge-swipe zones — invisible strips at top/bottom that
            // dispatch configurable actions on vertical drag.
            _configEdgeSwipeZone(
              alignment: Alignment.topCenter,
              action: config.topSwipeAction,
              swipeDown: true,
            ),
            _configEdgeSwipeZone(
              alignment: Alignment.bottomCenter,
              action: config.bottomSwipeAction,
              swipeDown: false,
            ),

            // Menu overlays — slide in from their assigned edge
            if (_menu1Open) _buildMenu1(fromTop: _edgeFor('menu1') == 'top'),
            if (_menu2Open) _buildMenu2(fromTop: _edgeFor('menu2') == 'top'),

            // Timer alert — full-screen overlay when a timer fires.
            // Isolated in its own ConsumerWidget so 200ms timer ticks
            // only rebuild this overlay, not the entire HubShell.
            _TimerAlertOverlay(onWake: _onUserActivity),

            // Event overlay layer (doorbell, alerts)
          ],
        ),
      ),
    );
  }
}

/// Full-screen alert overlay when one or more timers have fired.
///
/// Isolated in its own ConsumerWidget so the 200ms timer tick rebuilds
/// are scoped to this overlay instead of triggering a full HubShell rebuild.
class _TimerAlertOverlay extends ConsumerWidget {
  final VoidCallback onWake;

  const _TimerAlertOverlay({required this.onWake});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerService = ref.watch(timerServiceProvider);
    final fired = timerService.firedTimers;
    if (fired.isEmpty) return const SizedBox.shrink();

    // Wake from idle when a timer fires — deferred to avoid
    // notifyListeners() during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => onWake());

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
}

/// Timer action button for menu1 — isolated so its ref.watch on
/// timerServiceProvider only rebuilds this widget, not the menu tray
/// or the HubShell.
class _Menu1TimerAction extends ConsumerWidget {
  final VoidCallback onTap;

  const _Menu1TimerAction({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerService = ref.watch(timerServiceProvider);
    return _QuickAction(
      icon: Icons.timer,
      label: timerService.hasActiveTimers
          ? timerService.statusLabel
          : 'Timer',
      active: timerService.hasActiveTimers,
      onTap: onTap,
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

class _MenuTray extends StatelessWidget {
  final bool fromTop;
  final VoidCallback onDismiss;
  final Widget child;

  const _MenuTray({
    required this.fromTop,
    required this.onDismiss,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              top: fromTop ? 0 : null,
              bottom: fromTop ? null : 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if ((fromTop && v < -200) || (!fromTop && v > 200)) {
                    onDismiss();
                  }
                },
                onTap: () {},
                child: Container(
                  margin: EdgeInsets.only(
                    top: fromTop ? 12 : 0,
                    bottom: fromTop ? 0 : 12,
                    left: 24,
                    right: 24,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (fromTop) ...[
                        child,
                        const SizedBox(height: 8),
                        Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        child,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// System volume slider synced with Sendspin.
///
/// When Sendspin is active, the slider reflects the Sendspin volume (which
/// the server controls). Slider changes are pushed to both ALSA hardware
/// and reported back to the Sendspin server via client/state.
/// When Sendspin is inactive, the slider controls ALSA directly.
class _SystemVolumeSlider extends ConsumerStatefulWidget {
  const _SystemVolumeSlider();

  @override
  ConsumerState<_SystemVolumeSlider> createState() => _SystemVolumeSliderState();
}

class _SystemVolumeSliderState extends ConsumerState<_SystemVolumeSlider> {
  double _volume = 0.5;
  Timer? _debounce;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _readVolume();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _readVolume() async {
    final vol = await SendspinService.readAlsaVolume();
    if (vol != null && mounted) {
      setState(() => _volume = vol);
    }
  }

  void _onChanged(double value) {
    _userDragging = true;
    setState(() => _volume = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      _userDragging = false;
      // Set ALSA hardware volume (detects correct control name).
      await SendspinService.setAlsaVolume((value * 100).round(), false);
      // If Sendspin is active, report the volume change to the server.
      final sendspin = ref.read(sendspinServiceProvider);
      if (sendspin.state.isActive) {
        sendspin.setVolume(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sync from Sendspin volume when not dragging.
    final ssAsync = ref.watch(sendspinStateProvider);
    final ssState = ssAsync.valueOrNull;
    if (ssState != null && ssState.isActive && !_userDragging) {
      final ssVol = ssState.volume;
      if ((ssVol - _volume).abs() > 0.01) {
        // Schedule to avoid setState during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _volume = ssVol);
        });
      }
    }

    return Row(
      children: [
        const Icon(Icons.volume_down, color: Colors.white54, size: 20),
        Expanded(
          child: Slider(
            value: _volume,
            onChanged: _onChanged,
            activeColor: Colors.white70,
            inactiveColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const Icon(Icons.volume_up, color: Colors.white54, size: 20),
      ],
    );
  }
}
