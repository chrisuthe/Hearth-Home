import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import '../packages/hearth_osk/hearth_osk.dart';
import '../utils/logger.dart';

/// Hearth-side glue for the `hearth_osk` package.
///
/// Keeps all host-app concerns (HubConfig, Riverpod, Linux-specific keyboard
/// detection, theming to match hearth's palette) out of the package so the
/// package can later be extracted to a standalone Dart package with no
/// code changes.

/// User-facing preference for the on-screen keyboard.
enum OnScreenKeyboardMode {
  /// Show the OSK only when no physical keyboard is detected.
  auto,

  /// Always show the OSK regardless of attached hardware.
  always,

  /// Never show the OSK.
  never;

  static OnScreenKeyboardMode fromWire(String? value) {
    switch (value) {
      case 'always':
        return OnScreenKeyboardMode.always;
      case 'never':
        return OnScreenKeyboardMode.never;
      default:
        return OnScreenKeyboardMode.auto;
    }
  }

  String get wire => switch (this) {
        OnScreenKeyboardMode.auto => 'auto',
        OnScreenKeyboardMode.always => 'always',
        OnScreenKeyboardMode.never => 'never',
      };

  String get label => switch (this) {
        OnScreenKeyboardMode.auto => 'Auto (detect physical keyboard)',
        OnScreenKeyboardMode.always => 'Always on',
        OnScreenKeyboardMode.never => 'Off',
      };
}

/// Hearth's dark AMOLED theme for the OSK. Matches the indigo `0xFF646CFF`
/// accent and true-black backgrounds used elsewhere in the app.
const hearthOskTheme = HearthOskTheme(
  background: Color(0xFF0A0A0A),
  keyFill: Color(0xFF1E1E1E),
  modifierFill: Color(0xFF262626),
  modifierActiveFill: Color(0xFF2F355E),
  accent: Color(0xFF646CFF),
  keyLabel: Colors.white,
  modifierActiveLabel: Colors.white,
  keyHeight: 64,
);

/// Scans `/proc/bus/input/devices` for an attached USB keyboard.
///
/// Returns true if a device whose name contains "keyboard" or "kbd" is
/// present. Deliberately ignores the Pi's power button and the touchscreen
/// device (which reports a "Keyboard" phys path on some builds but not a
/// "Keyboard" name). Safe on non-Linux — returns false.
bool detectPhysicalKeyboard() {
  if (!Platform.isLinux) return false;
  try {
    final file = File('/proc/bus/input/devices');
    if (!file.existsSync()) return false;
    final content = file.readAsStringSync();
    // Entries are separated by blank lines. A real USB keyboard lists a
    // Name with "keyboard" (case-insensitive) in it.
    for (final block in content.split('\n\n')) {
      final nameLine = block
          .split('\n')
          .firstWhere((l) => l.startsWith('N: Name='), orElse: () => '');
      if (nameLine.isEmpty) continue;
      final lower = nameLine.toLowerCase();
      if (lower.contains('keyboard') || lower.contains(' kbd')) {
        // Exclude the touchscreen false-positive.
        if (lower.contains('touchscreen')) continue;
        Log.i('OSK', 'Detected physical keyboard: $nameLine');
        return true;
      }
    }
  } catch (e) {
    Log.w('OSK', 'Physical keyboard detection failed: $e');
  }
  return false;
}

/// Resolves whether the OSK should be enabled given a mode and a
/// physical-keyboard detection result.
bool resolveOskEnabled(OnScreenKeyboardMode mode) {
  switch (mode) {
    case OnScreenKeyboardMode.always:
      return true;
    case OnScreenKeyboardMode.never:
      return false;
    case OnScreenKeyboardMode.auto:
      return !detectPhysicalKeyboard();
  }
}

/// Riverpod provider that watches HubConfig and keeps the installed
/// [HearthOskControl] in sync with the user's preference.
final oskEnabledProvider = Provider<bool>((ref) {
  final modeWire = ref.watch(
      hubConfigProvider.select((c) => c.onScreenKeyboardMode));
  final enabled = resolveOskEnabled(OnScreenKeyboardMode.fromWire(modeWire));
  HearthOskControl.instance?.enabled = enabled;
  return enabled;
});
