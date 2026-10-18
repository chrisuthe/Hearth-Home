import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/alarm_clock/alarm_service.dart';
import 'android_apps.dart';
import 'dlna/dlna_service.dart';
import 'notification_service.dart';
import 'plex/livetv/plex_livetv_service.dart';
import 'plex/livetv/plex_livetv_state.dart';
import 'plex/plex_service.dart';

/// What would wake Hearth right now: the conditions the five full-screen
/// overlays in `HubShell` render on.
class WakeSnapshot {
  const WakeSnapshot({
    required this.notifications,
    required this.alarm,
    required this.dlna,
    required this.plex,
    required this.liveTv,
  });

  final int notifications;
  final bool alarm;
  final bool dlna;
  final bool plex;
  final bool liveTv;
}

/// True when something new arrived between [before] and [after]: another
/// notification, or an alarm, DLNA cast, Plex cast or Live TV starting.
/// Something ending or staying put never summons.
bool shouldSummon(WakeSnapshot before, WakeSnapshot after) =>
    after.notifications > before.notifications ||
    (after.alarm && !before.alarm) ||
    (after.dlna && !before.dlna) ||
    (after.plex && !before.plex) ||
    (after.liveTv && !before.liveTv);

/// Brings Hearth forward over a launched app whenever something would wake
/// it. Read once at boot on Android.
///
/// Listens to the sources directly rather than through a widget: with Hearth
/// in the background Flutter draws no frames, so the overlays never build.
/// Native decides whether `bringToFront` does anything (Hearth already in
/// front, or no "Display over other apps").
final foregroundSummonerProvider = Provider<void>((ref) {
  WakeSnapshot read() {
    final liveTv = ref.read(plexLiveTvStateProvider).valueOrNull;
    return WakeSnapshot(
      notifications: ref.read(notificationServiceProvider).notifications.length,
      alarm: ref.read(alarmServiceProvider).firedAlarm != null,
      dlna: ref.read(dlnaRendererStateProvider).valueOrNull?.hasMedia ?? false,
      plex: ref.read(plexPlayerStateProvider).valueOrNull?.hasMedia ?? false,
      liveTv:
          liveTv != null &&
          (liveTv.hasMedia || liveTv.phase == LiveTvPhase.error),
    );
  }

  var last = read();
  void check() {
    final next = read();
    if (shouldSummon(last, next)) {
      ref.read(androidAppsBridgeProvider).bringToFront();
    }
    last = next;
  }

  ref.listen(notificationServiceProvider, (_, _) => check());
  ref.listen(alarmServiceProvider, (_, _) => check());
  ref.listen(dlnaRendererStateProvider, (_, _) => check());
  ref.listen(plexPlayerStateProvider, (_, _) => check());
  ref.listen(plexLiveTvStateProvider, (_, _) => check());
});
