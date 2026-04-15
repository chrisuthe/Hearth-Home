import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'utils/logger.dart';
import 'utils/alsa_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'config/hub_config.dart';
import 'packages/hearth_osk/hearth_osk.dart';
import 'services/local_api_server.dart';
import 'services/osk_integration.dart';
import 'services/timezone_service.dart';
import 'modules/alarm_clock/alarm_service.dart';
import 'services/sendspin/sendspin_service.dart';
import 'services/video/media_kit_player.dart';
import 'services/video/gstreamer_player.dart';
// media_kit uses native libmpv — not available on web.
import 'package:media_kit/media_kit.dart';

/// Target resolution: half the 11" AMOLED's native 2368x1728.
/// The panel upscales from this render resolution, giving us smooth
/// performance on the Pi 5 while still looking sharp.
const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit (libmpv) on desktop platforms only.
  // On Pi with flutter-pi, video is handled by GStreamer — libmpv is not available.
  // dart:io Platform.environment check avoids calling into FFI on unsupported platforms.
  if (!kIsWeb && !Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
    MediaKit.ensureInitialized();
  }

  // Register platform video player
  if (!kIsWeb) {
    if (!Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
      registerMediaKitPlayer();
    } else {
      registerGstreamerPlayer();
    }
  }

  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  // Install the on-screen keyboard control before any UI is mounted so that
  // the very first TextField focus can surface the OSK. The control starts
  // enabled; oskEnabledProvider will reconcile it against user preference
  // once the widget tree comes up.
  final oskControl = HearthOskControl.install();
  final initialMode = OnScreenKeyboardMode.fromWire(
      container.read(hubConfigProvider).onScreenKeyboardMode);
  oskControl.enabled = resolveOskEnabled(initialMode);

  // Apply configured timezone before anything else reads the clock.
  // On Linux (Pi), this sets the system timezone via timedatectl or
  // /etc/localtime. On Windows/web, this is a no-op.
  if (!kIsWeb) {
    final tz = container.read(hubConfigProvider).timezone;
    if (tz.isNotEmpty) {
      final tzService = container.read(timezoneServiceProvider);
      await tzService.applyTimezone(tz);
    }
  }

  // Apply persisted mic mute state to ALSA capture device.
  if (!kIsWeb) {
    final micMuted = container.read(hubConfigProvider).micMuted;
    if (micMuted) {
      await setMicMuted(true);
    }
  }

  // Start local API server (native only — dart:io HttpServer).
  // The server reads config and display state per-request, so it
  // doesn't need to restart when settings change.
  if (!kIsWeb) {
    final apiServer = container.read(localApiServerProvider);
    try {
      final port = await apiServer.start();
      Log.i('App', 'Local API server listening on port $port');
    } catch (e) {
      Log.e('App', 'API server start failed: $e');
    }

  }

  // All other services (HA, MA, Immich, Frigate, DisplayMode) are
  // self-initializing providers — they watch their config fields and
  // connect automatically. When config changes in Settings, Riverpod
  // disposes the old instance and creates a new one that reconnects.

  // Sendspin player is also self-initializing but needs an eager read
  // to start mDNS advertisement when config says enabled.
  if (!kIsWeb) {
    container.read(sendspinServiceProvider);
  }

  // Eager-load AlarmService so persisted alarms are loaded and the
  // 30-second ticker starts checking fire times immediately.
  final alarmService = container.read(alarmServiceProvider);
  await alarmService.load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HearthApp(),
    ),
  );
}
