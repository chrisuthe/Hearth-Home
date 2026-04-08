import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'config/hub_config.dart';
import 'services/local_api_server.dart';
import 'services/sendspin/sendspin_service.dart';

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

  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

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

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HearthApp(),
    ),
  );
}
