import 'dart:io';
import '../utils/logger.dart';

/// Mute or unmute the ALSA capture device.
///
/// Uses `amixer set Capture nocap/cap` to control the hardware mic.
/// No-op on non-Linux platforms.
Future<void> setMicMuted(bool muted) async {
  if (!Platform.isLinux) return;
  try {
    final result = await Process.run(
      'amixer', ['set', 'Capture', muted ? 'nocap' : 'cap'],
    );
    if (result.exitCode != 0) {
      Log.w('ALSA', 'amixer set Capture ${muted ? "nocap" : "cap"} '
          'failed (exit ${result.exitCode}): ${result.stderr}');
    }
  } catch (e) {
    Log.w('ALSA', 'Failed to set mic mute: $e');
  }
}
