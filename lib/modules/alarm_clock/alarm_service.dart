import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/logger.dart';
import 'alarm_models.dart';

// dart:io and path_provider compile to stubs on web — guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Persistence and scheduling service for alarms.
///
/// Follows the same ChangeNotifier pattern as [TimerService]. Alarms are
/// persisted to `alarms.json` in the app support directory. A 30-second
/// periodic ticker checks whether any enabled alarm should fire.
class AlarmService extends ChangeNotifier {
  List<Alarm> _alarms = [];
  Alarm? _firedAlarm;
  DateTime? _snoozedUntil;
  Timer? _ticker;

  /// Track which alarm IDs have already fired in the current minute window
  /// to avoid repeated triggers on successive ticks.
  final Set<String> _alreadyFired = {};

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All alarms, sorted by time.
  List<Alarm> get alarms => List.unmodifiable(_alarms);

  /// The alarm currently firing (awaiting snooze/dismiss), or null.
  Alarm? get firedAlarm => _firedAlarm;

  /// If snoozed, when the snooze expires. Null otherwise.
  DateTime? get snoozedUntil => _snoozedUntil;

  /// The next alarm to fire: returns (alarm, fireTime) for the soonest
  /// enabled alarm, or null if none are scheduled.
  (Alarm, DateTime)? get nextAlarm {
    final now = DateTime.now();
    (Alarm, DateTime)? best;
    for (final alarm in _alarms) {
      final next = alarm.nextFireTime(now);
      if (next != null && (best == null || next.isBefore(best.$2))) {
        best = (alarm, next);
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Load alarms from disk. Called once at app startup.
  Future<void> load() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/alarms.json');
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List<dynamic>;
        _alarms = list
            .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      Log.e('AlarmService', 'Failed to load alarms.json: $e');
      _alarms = [];
    }
    _ensureTicking();
    notifyListeners();
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/alarms.json');
      await file.writeAsString(jsonEncode(_alarms.map((a) => a.toJson()).toList()));
    } catch (e) {
      Log.e('AlarmService', 'Failed to save alarms.json: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  void addAlarm(Alarm alarm) {
    _alarms.add(alarm);
    _save();
    _ensureTicking();
    notifyListeners();
  }

  void updateAlarm(Alarm alarm) {
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) {
      _alarms[idx] = alarm;
      _save();
      notifyListeners();
    }
  }

  void deleteAlarm(String id) {
    _alarms.removeWhere((a) => a.id == id);
    _alreadyFired.remove(id);
    _save();
    if (_alarms.isEmpty) _stopTicking();
    notifyListeners();
  }

  void toggleEnabled(String id) {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _alarms[idx] = _alarms[idx].copyWith(enabled: !_alarms[idx].enabled);
      _alreadyFired.remove(id);
      _save();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Ticker
  // ---------------------------------------------------------------------------

  /// Start a 30-second periodic ticker to check alarm fire times.
  void _ensureTicking() {
    _ticker ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onTick(),
    );
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    final now = DateTime.now();

    // Check snooze expiry.
    if (_snoozedUntil != null && now.isAfter(_snoozedUntil!)) {
      _snoozedUntil = null;
      // Re-check alarms immediately — the snoozed alarm may still match.
    }

    if (_firedAlarm != null) return; // Already firing, wait for user action.

    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      if (_alreadyFired.contains(alarm.id)) continue;

      final fireTime = alarm.nextFireTime(now);
      if (fireTime == null) continue;

      // Fire if within a 60-second window.
      final diff = fireTime.difference(now).inSeconds;
      if (diff >= -60 && diff <= 0) {
        _fireAlarm(alarm);
        return;
      }
    }
  }

  void _fireAlarm(Alarm alarm) {
    _alreadyFired.add(alarm.id);
    _firedAlarm = alarm;
    _snoozedUntil = null;
    notifyListeners();
  }

  /// Test-only: simulate an alarm firing without waiting for the ticker.
  @visibleForTesting
  void fireAlarmForTest(Alarm alarm) => _fireAlarm(alarm);

  // ---------------------------------------------------------------------------
  // Snooze / Dismiss
  // ---------------------------------------------------------------------------

  /// Snooze the currently firing alarm.
  void snooze() {
    if (_firedAlarm == null) return;
    _snoozedUntil = DateTime.now().add(
      Duration(minutes: _firedAlarm!.snoozeDuration),
    );
    _firedAlarm = null;
    notifyListeners();
  }

  /// Dismiss the currently firing alarm. One-time alarms are auto-disabled.
  void dismiss() {
    if (_firedAlarm == null) return;
    final alarm = _firedAlarm!;
    _firedAlarm = null;

    // Auto-disable one-time alarms after dismissal.
    if (alarm.oneTime || alarm.days.isEmpty) {
      final idx = _alarms.indexWhere((a) => a.id == alarm.id);
      if (idx >= 0) {
        _alarms[idx] = _alarms[idx].copyWith(enabled: false);
        _save();
      }
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _stopTicking();
    super.dispose();
  }
}

final alarmServiceProvider = ChangeNotifierProvider<AlarmService>((ref) {
  return AlarmService();
});
