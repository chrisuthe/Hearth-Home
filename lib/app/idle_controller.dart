import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';

/// Inactivity timer that fires a callback after a configurable timeout.
///
/// Used by HubShell to navigate back to Home after the user stops
/// interacting. Video playback can suppress the timer so camera
/// streams aren't interrupted.
class IdleController {
  Timer? _timer;
  int _timeoutSeconds;
  bool _suppressed = false;

  /// Called when the inactivity timeout fires.
  void Function()? onTimeout;

  IdleController({required int timeoutSeconds})
      : _timeoutSeconds = timeoutSeconds;

  bool get isSuppressed => _suppressed;

  set timeoutSeconds(int value) {
    _timeoutSeconds = value;
    if (!_suppressed) _startTimer();
  }

  /// Call on every user touch event to reset the inactivity countdown.
  void onUserActivity() {
    _startTimer();
  }

  /// Pause the timer (e.g., while video is playing).
  void suppress() {
    _suppressed = true;
    _timer?.cancel();
  }

  /// Resume the timer after suppression.
  void unsuppress() {
    _suppressed = false;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_suppressed) return;
    _timer = Timer(Duration(seconds: _timeoutSeconds), () {
      onTimeout?.call();
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

final idleControllerProvider = Provider<IdleController>((ref) {
  final timeout = ref.read(hubConfigProvider).idleTimeoutSeconds;
  final controller = IdleController(timeoutSeconds: timeout);
  ref.listen(hubConfigProvider.select((c) => c.idleTimeoutSeconds),
      (_, newTimeout) {
    controller.timeoutSeconds = newTimeout;
  });
  ref.onDispose(() => controller.dispose());
  return controller;
});
