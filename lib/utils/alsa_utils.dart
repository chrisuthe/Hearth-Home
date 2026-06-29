import 'dart:io';
import '../utils/logger.dart';

/// Set the ALSA "Master" playback volume to [percent] (0–100).
///
/// Uses `amixer set Master <n>%`. No-op on non-Linux platforms. [percent] is
/// clamped to the valid range before being applied.
Future<void> setMasterVolume(int percent) async {
  if (!Platform.isLinux) return;
  final clamped = percent.clamp(0, 100);
  try {
    final result = await Process.run('amixer', ['set', 'Master', '$clamped%']);
    if (result.exitCode != 0) {
      Log.w('ALSA', 'amixer set Master $clamped% '
          'failed (exit ${result.exitCode}): ${result.stderr}');
    }
  } catch (e) {
    Log.w('ALSA', 'Failed to set master volume: $e');
  }
}

/// Read the current ALSA "Master" playback volume as a percentage (0–100).
///
/// Parses the `[NN%]` field from `amixer get Master`. Returns null on
/// non-Linux platforms or if the volume can't be determined.
Future<int?> getMasterVolume() async {
  if (!Platform.isLinux) return null;
  try {
    final result = await Process.run('amixer', ['get', 'Master']);
    if (result.exitCode != 0) {
      Log.w('ALSA', 'amixer get Master failed '
          '(exit ${result.exitCode}): ${result.stderr}');
      return null;
    }
    final match = RegExp(r'\[(\d+)%\]').firstMatch(result.stdout as String);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  } catch (e) {
    Log.w('ALSA', 'Failed to get master volume: $e');
    return null;
  }
}
