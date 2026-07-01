import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import '../models/hearth_notification.dart';
import '../utils/logger.dart';
import 'display_mode_service.dart';

/// How long a transient (non-sticky) card lives before auto-dismissing.
const Duration kTransientNotificationLifetime = Duration(seconds: 6);

/// Global notification store — the single list feeding the bottom-deck surface.
///
/// Shape mirrors `TimerService`: a [ChangeNotifier] that owns the active list
/// and drives the UI via `notifyListeners`. Every source (Frigate, Unifi, HA,
/// push, and fired timers) normalizes into a [HearthNotification] and lands
/// here via [ingest].
///
/// Side effects are injected so unit tests exercise ingest/dismiss/expiry with
/// no audio subprocess: [playChime] defaults to a GStreamer one-shot on Linux
/// (a log on other platforms), and [isChimeSuppressed] defaults to never
/// suppressing (the provider wires it to night mode).
class NotificationService extends ChangeNotifier {
  NotificationService({
    Future<void> Function(HearthNotification)? playChime,
    bool Function()? isChimeSuppressed,
    Duration transientLifetime = kTransientNotificationLifetime,
  })  : _playChime = playChime ?? _defaultPlayChime,
        _isChimeSuppressed = isChimeSuppressed ?? (() => false),
        _transientLifetime = transientLifetime;

  final List<HearthNotification> _notifications = [];
  final Map<String, Timer> _autoDismissTimers = {};
  final Future<void> Function(HearthNotification) _playChime;
  final bool Function() _isChimeSuppressed;
  final Duration _transientLifetime;

  /// Active notifications, oldest first → newest last (the deck stacks newest
  /// at the bottom, closest to the hand).
  List<HearthNotification> get notifications =>
      List.unmodifiable(_notifications);

  bool get hasActive => _notifications.isNotEmpty;

  /// Add a notification: append, play its chime (unless muted, suppressed by
  /// night mode, or timer-sourced — `TimerService` owns the looping fired-timer
  /// beep), and arm a 6s auto-dismiss for transient cards.
  void ingest(HearthNotification notification) {
    // Replace any existing card with the same id (e.g. a timer re-ingested)
    // so a stable id can't stack duplicates.
    final existing = _notifications.indexWhere((n) => n.id == notification.id);
    if (existing >= 0) {
      _autoDismissTimers.remove(notification.id)?.cancel();
      _notifications.removeAt(existing);
    }

    _notifications.add(notification);
    notifyListeners();

    final chimeAllowed = !notification.muted &&
        !_isChimeSuppressed() &&
        notification.source != NotificationSource.timer;
    if (chimeAllowed) {
      _playChime(notification);
    }

    if (!notification.sticky) {
      _autoDismissTimers[notification.id] =
          Timer(_transientLifetime, () => dismiss(notification.id));
    }
  }

  /// Remove one notification by id. Idempotent — a no-op if it's already gone,
  /// which keeps the timer-card ↔ `TimerService` dismissal loop from recursing.
  void dismiss(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final removed = _notifications.removeAt(index);
    _autoDismissTimers.remove(id)?.cancel();
    notifyListeners();
    removed.onDismiss?.call();
  }

  /// Remove every active notification and cancel all timers.
  void clearAll() {
    if (_notifications.isEmpty) return;
    final removed = List<HearthNotification>.from(_notifications);
    _notifications.clear();
    for (final timer in _autoDismissTimers.values) {
      timer.cancel();
    }
    _autoDismissTimers.clear();
    notifyListeners();
    for (final n in removed) {
      n.onDismiss?.call();
    }
  }

  @override
  void dispose() {
    for (final timer in _autoDismissTimers.values) {
      timer.cancel();
    }
    _autoDismissTimers.clear();
    super.dispose();
  }

  /// One-shot arrival chime. Alert = an urgent triple beep; info = a single
  /// soft ping. Generated with GStreamer's `audiotestsrc` (no bundled asset),
  /// mirroring `TimerService`'s alarm tone. A log-only no-op off Linux.
  static Future<void> _defaultPlayChime(HearthNotification n) async {
    if (!Platform.isLinux) {
      debugPrint('[NotificationService] chime: ${n.chimeLabel} (${n.priority.name})');
      return;
    }
    try {
      if (n.priority == NotificationPriority.alert) {
        // Ember Alert: urgent triple beep (880 / 1174 / 880 Hz).
        for (final freq in [880, 1174, 880]) {
          await _tone(freq, buffers: 7, volume: 0.35);
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      } else {
        // Soft Ping: a single gentle sine.
        await _tone(740, buffers: 22, volume: 0.16);
      }
    } catch (e) {
      Log.e('Notification', 'Chime playback failed: $e');
    }
  }

  /// Play one short sine tone and wait for it to finish. `buffers` sets the
  /// length (each ~1024/44100 ≈ 23ms), matching `TimerService`'s approach.
  static Future<void> _tone(int freq,
      {required int buffers, required double volume}) async {
    final process = await Process.start('gst-launch-1.0', [
      'audiotestsrc', 'wave=sine', 'freq=$freq', 'num-buffers=$buffers',
      '!', 'audioconvert',
      '!', 'volume', 'volume=$volume',
      '!', 'autoaudiosink',
    ]);
    await process.exitCode;
  }
}

/// Single, stable notification store. Not recreated by Riverpod (nothing is
/// `watch`ed here) so its list survives unrelated config edits. The chime is
/// suppressed while the display is in night mode.
final notificationServiceProvider =
    ChangeNotifierProvider<NotificationService>((ref) {
  return NotificationService(
    isChimeSuppressed: () {
      if (kIsWeb) return false;
      final config = ref.read(hubConfigProvider);
      final mode =
          ref.read(displayModeServiceProvider).resolveMode(config: config);
      return mode == DisplayMode.night;
    },
  );
});
