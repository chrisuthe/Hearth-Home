import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';

/// A single countdown timer managed by [TimerService].
///
/// Tracks its own start time and total duration, computing remaining time
/// from the wall clock so it stays accurate even if the UI misses ticks.
/// The [id] is used to identify timers for dismissal.
class HubTimer {
  final int id;
  final Duration totalDuration;
  final DateTime startTime;
  bool _dismissed = false;

  HubTimer({
    required this.id,
    required this.totalDuration,
  }) : startTime = DateTime.now();

  Duration get remaining {
    final elapsed = DateTime.now().difference(startTime);
    final left = totalDuration - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  double get progress {
    if (totalDuration.inMilliseconds == 0) return 0;
    return 1.0 - (remaining.inMilliseconds / totalDuration.inMilliseconds);
  }

  bool get isDone => remaining == Duration.zero;
  bool get isDismissed => _dismissed;

  /// Format remaining time as "H:MM:SS" or "MM:SS".
  String get remainingLabel {
    final r = remaining;
    final h = r.inHours;
    final m = r.inMinutes.remainder(60);
    final s = r.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Global timer service that survives navigation.
///
/// Timers live here instead of in the TimerScreen widget, so they keep
/// counting even when the user navigates back to Home or the display
/// goes ambient. When a timer fires, [firedTimers] is non-empty and
/// the HubShell shows a full-screen alert overlay.
class TimerService extends ChangeNotifier {
  final List<HubTimer> _timers = [];
  Timer? _ticker;
  int _nextId = 0;

  /// All active (non-dismissed) timers.
  List<HubTimer> get timers => _timers.where((t) => !t.isDismissed).toList();

  /// Timers that have finished but haven't been dismissed yet.
  /// The HubShell watches this to show the alert overlay.
  List<HubTimer> get firedTimers =>
      _timers.where((t) => t.isDone && !t.isDismissed).toList();

  /// Whether any timers are actively counting down.
  bool get hasActiveTimers => _timers.any((t) => !t.isDone && !t.isDismissed);

  /// Summary for the home screen button, e.g., "1 timer · 3:42"
  String get statusLabel {
    final active = timers.where((t) => !t.isDone).toList();
    if (active.isEmpty) return '';
    if (active.length == 1) return active.first.remainingLabel;
    return '${active.length} timers';
  }

  void startTimer(Duration duration) {
    _timers.add(HubTimer(id: _nextId++, totalDuration: duration));
    _ensureTicking();
    notifyListeners();
  }

  void dismissTimer(int id) {
    final timer = _timers.firstWhere((t) => t.id == id);
    timer._dismissed = true;
    _alreadyFired.remove(id);
    _timers.removeWhere((t) => t.isDismissed);
    if (firedTimers.isEmpty) _stopAlarmSound();
    if (_timers.isEmpty) _stopTicking();
    notifyListeners();
  }

  /// Dismiss all fired timers at once (e.g., tapping the alert overlay).
  void dismissAllFired() {
    for (final t in firedTimers) {
      t._dismissed = true;
      _alreadyFired.remove(t.id);
    }
    _timers.removeWhere((t) => t.isDismissed);
    _stopAlarmSound();
    if (_timers.isEmpty) _stopTicking();
    notifyListeners();
  }

  /// Start a periodic tick that drives UI updates.
  /// 200ms is fast enough for smooth countdown display without
  /// burning CPU on a kiosk that runs 24/7.
  void _ensureTicking() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  /// Set of timer IDs that have already triggered their alarm.
  /// Prevents the alarm from firing repeatedly on every tick.
  final Set<int> _alreadyFired = {};

  void _onTick() {
    // Check for newly fired timers and play an alarm sound
    for (final timer in _timers) {
      if (timer.isDone && !timer.isDismissed && !_alreadyFired.contains(timer.id)) {
        _alreadyFired.add(timer.id);
        _playAlarmSound();
      }
    }
    notifyListeners();
  }

  Process? _alarmProcess;
  bool _alarmLooping = false;

  /// Play a looping beep when a timer fires. Uses GStreamer's audiotestsrc
  /// to generate a sine tone (no asset bundle dependency) and routes through
  /// autoaudiosink, which picks pipewiresink/alsasink based on what's
  /// available. Loops until [_stopAlarmSound] is called by dismissTimer
  /// or dismissAllFired.
  void _playAlarmSound() {
    if (!Platform.isLinux) {
      Log.i('Timer', 'Would play alarm tone (non-Linux platform)');
      return;
    }
    if (_alarmLooping) return; // already beeping for an earlier timer
    _alarmLooping = true;
    _alarmLoop();
  }

  Future<void> _alarmLoop() async {
    // 880 Hz sine, ~0.46s tone via num-buffers=20 (20 * 1024 / 44100), then
    // ~0.4s of silence in Dart-land before the next subprocess. Result is
    // a "beep ... beep ... beep" pattern at ~1.2 Hz.
    while (_alarmLooping) {
      try {
        _alarmProcess = await Process.start('gst-launch-1.0', [
          'audiotestsrc', 'wave=sine', 'freq=880', 'num-buffers=20',
          '!', 'audioconvert',
          '!', 'volume', 'volume=0.5',
          '!', 'autoaudiosink',
        ]);
        await _alarmProcess!.exitCode;
        if (!_alarmLooping) break;
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (e) {
        Log.e('Timer', 'Alarm playback failed: $e');
        break;
      }
    }
    _alarmProcess = null;
  }

  void _stopAlarmSound() {
    _alarmLooping = false;
    _alarmProcess?.kill();
    _alarmProcess = null;
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopAlarmSound();
    _stopTicking();
    super.dispose();
  }
}

final timerServiceProvider = ChangeNotifierProvider<TimerService>((ref) {
  return TimerService();
});
