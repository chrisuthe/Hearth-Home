import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'display_rotation_service.dart';

/// Restarts Hearth so every setting is read fresh, as a restore needs:
/// the timezone, the Pi's rotation and the MQTT client id are only read at
/// startup.
///
/// * Linux (the Pi): `systemctl restart hearth.service`, through
///   [DisplayRotationService.restart].
/// * Android: the app relaunches its own process (`restartApp` on
///   `com.hearth/app_update`).
/// * Anywhere else (the Windows dev build): it cannot, and says so.
class AppRestarter {
  static const _tag = 'Restart';

  final bool _android;
  final bool _linux;
  final DisplayRotationService _linuxRestart;
  final MethodChannel _channel;

  AppRestarter({
    bool? android,
    bool? linux,
    DisplayRotationService? linuxRestart,
    MethodChannel? channel,
  })  : _android = android ?? (!kIsWeb && Platform.isAndroid),
        _linux = linux ?? (!kIsWeb && Platform.isLinux),
        _linuxRestart = linuxRestart ?? DisplayRotationService(),
        _channel = channel ?? const MethodChannel('com.hearth/app_update');

  bool get canRestart => _android || _linux;

  /// False when the restart could not be issued. On success this process
  /// is usually gone before the call returns.
  Future<bool> restart() async {
    if (_linux) return _linuxRestart.restart();
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('restartApp') ?? false;
    } catch (e) {
      Log.w(_tag, 'restart failed: $e');
      return false;
    }
  }
}

final appRestarterProvider = Provider<AppRestarter>((ref) =>
    AppRestarter(linuxRestart: ref.read(displayRotationServiceProvider)));
