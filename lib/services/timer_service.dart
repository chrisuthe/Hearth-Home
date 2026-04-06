import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Clean up fully dismissed timers
    _timers.removeWhere((t) => t.isDismissed);
    if (_timers.isEmpty) _stopTicking();
    notifyListeners();
  }

  /// Dismiss all fired timers at once (e.g., tapping the alert overlay).
  void dismissAllFired() {
    for (final t in firedTimers) {
      t._dismissed = true;
    }
    _timers.removeWhere((t) => t.isDismissed);
    if (_timers.isEmpty) _stopTicking();
    notifyListeners();
  }

  /// Start a periodic tick that drives UI updates.
  /// 200ms is fast enough for smooth countdown display without
  /// burning CPU on a kiosk that runs 24/7.
  void _ensureTicking() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => notifyListeners(),
    );
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicking();
    super.dispose();
  }
}

final timerServiceProvider = ChangeNotifierProvider<TimerService>((ref) {
  return TimerService();
});
