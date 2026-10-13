import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/display_orientation.dart';
import '../config/hub_config.dart';
import '../utils/logger.dart';

/// Where the configured orientation stands against what the display is doing.
enum RotationStatus {
  /// Nothing to report: the platform ignores the setting (desktop), applies it
  /// live (Android), or the Pi is already launched at the configured rotation.
  inEffect,

  /// Pi, launched by `hearth-launch` at a different rotation than configured.
  restartNeeded,

  /// Linux without `HEARTH_APPLIED_ROTATION`: the unit still execs flutter-pi
  /// directly, so nothing reads the setting until the launcher is installed.
  launcherMissing,
}

typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Env var `scripts/hearth-launch.sh` exports with the `--rotation` it passed.
const kAppliedRotationEnv = 'HEARTH_APPLIED_ROTATION';

/// Reconciles `HubConfig.displayOrientation` with the running display.
///
/// On the Pi the rotation is fixed for the life of the flutter-pi process, so
/// a change only takes effect when `hearth.service` restarts. Environment,
/// platform and process runner are injected so that is testable off-device.
class DisplayRotationService {
  static const _tag = 'Rotation';

  final Map<String, String> _environment;
  final bool _isLinux;
  final ProcessRunner _run;

  DisplayRotationService({
    Map<String, String>? environment,
    bool? isLinux,
    ProcessRunner? runProcess,
  })  : _environment = environment ?? (kIsWeb ? const {} : Platform.environment),
        _isLinux = isLinux ?? (!kIsWeb && Platform.isLinux),
        _run = runProcess ?? Process.run;

  /// Rotation flutter-pi was launched with, or null when the launcher did not
  /// start this process.
  int? get appliedDegrees => int.tryParse(_environment[kAppliedRotationEnv] ?? '');

  RotationStatus statusFor(DisplayOrientation configured) {
    if (!_isLinux) return RotationStatus.inEffect;
    final applied = appliedDegrees;
    if (applied == null) return RotationStatus.launcherMissing;
    return applied == configured.piRotationDegrees
        ? RotationStatus.inEffect
        : RotationStatus.restartNeeded;
  }

  /// Restarts the kiosk so the launcher re-reads the orientation. Returns
  /// false when the restart could not be issued; on success this process is
  /// killed before the call returns.
  Future<bool> restart() async {
    if (!_isLinux) return false;
    try {
      // -n: fail fast when the sudoers rule is missing instead of waiting on
      // a password prompt nobody can answer.
      final result = await _run(
          'sudo', ['-n', 'systemctl', 'restart', 'hearth.service']);
      if (result.exitCode == 0) return true;
      Log.w(_tag,
          'restart failed (exit ${result.exitCode}): ${result.stderr}');
    } catch (e) {
      Log.w(_tag, 'restart failed: $e');
    }
    return false;
  }
}

final displayRotationServiceProvider =
    Provider<DisplayRotationService>((ref) => DisplayRotationService());

/// Applies an orientation on Android; a no-op everywhere else.
Future<void> applyAndroidOrientation(DisplayOrientation orientation) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await SystemChrome.setPreferredOrientations(orientation.androidOrientations);
}

/// Keeps Android's preferred orientations in step with the setting. Read once
/// at startup; the listener then follows every later change.
final androidOrientationProvider = Provider<void>((ref) {
  ref.listen<String>(
    hubConfigProvider.select((c) => c.displayOrientation),
    (_, wire) => applyAndroidOrientation(DisplayOrientation.fromWire(wire)),
    fireImmediately: true,
  );
});
