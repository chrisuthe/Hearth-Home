import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../packages/hearth_osk/hearth_osk.dart';
import '../screens/setup/setup_wizard.dart';
import '../services/osk_integration.dart';
import 'hub_shell.dart';

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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: const Color(0xFF646CFF),
        useMaterial3: true,
        fontFamily: 'Roboto',
        dialogTheme: const DialogThemeData(backgroundColor: kDialogBackground),
      ),
      builder: (context, child) {
        final control = HearthOskControl.instance;
        if (control == null || child == null) {
          return child ?? const SizedBox.shrink();
        }
        return HearthOskScope(
          control: control,
          theme: hearthOskTheme,
          child: child,
        );
      },
      home: Scaffold(
        body: needsSetup ? const SetupWizard() : const HubShell(),
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
