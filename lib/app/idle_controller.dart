import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';

/// Tracks user touch activity and triggers ambient mode after idle timeout.
///
/// The kiosk spends ~90% of its time in ambient mode showing photos.
/// When the user touches the screen, we switch to the active layer
/// (PageView with Home/Media/Controls etc.) and start a countdown.
/// If no further touches arrive before the timeout, we fade back to ambient.
class IdleController extends ChangeNotifier {
  Timer? _timer;
  bool _isIdle = false;
  int _timeoutSeconds;

  IdleController({int timeoutSeconds = 120})
      : _timeoutSeconds = timeoutSeconds {
    _startTimer();
  }

  bool get isIdle => _isIdle;

  set timeoutSeconds(int value) {
    _timeoutSeconds = value;
    resetTimer();
  }

  /// Call this on every user touch event to reset the idle countdown.
  /// If we're currently idle, this wakes us up immediately.
  void onUserActivity() {
    if (_isIdle) {
      _isIdle = false;
      notifyListeners();
    }
    _startTimer();
  }

  void resetTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _timeoutSeconds), () {
      _isIdle = true;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final idleControllerProvider = ChangeNotifierProvider<IdleController>((ref) {
  final config = ref.watch(hubConfigProvider);
  return IdleController(timeoutSeconds: config.idleTimeoutSeconds);
});
