import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../packages/hearth_osk/hearth_osk.dart';
import '../screens/setup/setup_wizard.dart';
import '../services/osk_integration.dart';
import '../widgets/touch_indicator_overlay.dart';
import 'hub_shell.dart';
import 'scale/hearth_scale.dart';
import 'theme/hearth_colors.dart';
import 'theme/hearth_theme.dart';
import 'theme/memories_accent_scope.dart';
import 'theme/theme_providers.dart';

/// Root widget for the Hearth application.
///
/// Uses a dark theme optimized for an always-on AMOLED display — true black
/// background saves power and looks great on the 11" panel. Material 3 with
/// a subtle indigo accent keeps the UI modern without being distracting.
/// Dialog/sheet background — slightly lighter than true black for visual
/// separation from the AMOLED background.
const kDialogBackground = Color(0xFF1E1E1E);

class HearthApp extends ConsumerWidget {
  const HearthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final needsSetup = !config.setupComplete;

    // Watch the OSK-enabled provider so changes to the user's preference
    // immediately re-evaluate `HearthOskControl.enabled`.
    ref.watch(oskEnabledProvider);

    return MaterialApp(
      title: 'Hearth',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _TouchScrollBehavior(),
      theme: buildHearthTheme(ref.watch(hearthColorsProvider)),
      // HearthColors.lerp snaps, so an animated change would flicker.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final control = HearthOskControl.instance;
        // Fades the Memories accent without rebuilding this theme.
        return MemoriesAccentHost(
          child: control == null
              ? child
              : HearthOskScope(
                  control: control,
                  theme: HearthColors.of(context).osk,
                  child: child,
                ),
        );
      },
      home: Scaffold(
        body: needsSetup
            ? const SetupWizard()
            : HearthScaleScope(
                child: TouchIndicatorOverlay(
                  // Master toggle gates the overlay entirely — users who haven't
                  // enabled capture tools never pay the overlay cost even if
                  // TouchIndicatorConfig.enabled was somehow true in their config.
                  config: config.captureToolsEnabled
                      ? config.touchIndicator
                      : const TouchIndicatorConfig(),
                  child: const HubShell(),
                ),
              ),
      ),
    );
  }
}

/// Enables drag-to-scroll for mouse input on desktop.
/// Flutter defaults to touch-only drag scrolling, which makes PageView
/// and ListView unusable with a mouse on Windows/Linux. On the Pi with
/// a touchscreen this is a no-op since touch is already enabled.
class _TouchScrollBehavior extends MaterialScrollBehavior {
  const _TouchScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
      };
}
