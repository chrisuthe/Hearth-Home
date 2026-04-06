import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'config/hub_config.dart';
import 'services/home_assistant_service.dart';
import 'services/immich_service.dart';
import 'services/music_assistant_service.dart';
import 'services/frigate_service.dart';
import 'services/display_mode_service.dart';
import 'services/local_api_server.dart';

// media_kit uses native libmpv — not available on web.
// ignore: uri_does_not_exist
import 'package:media_kit/media_kit.dart'
    if (dart.library.html) 'package:media_kit/media_kit.dart';

/// Target resolution: half the 11" AMOLED's native 2368x1728.
/// The panel upscales from this render resolution, giving us smooth
/// performance on the Pi 5 while still looking sharp.
const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for RTSP camera stream playback (native only).
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Load persisted configuration before building the widget tree.
  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  final config = container.read(hubConfigProvider);

  // --- Connect to Home Assistant ---
  if (config.haUrl.isNotEmpty && config.haToken.isNotEmpty) {
    final ha = container.read(homeAssistantServiceProvider);
    try {
      await ha.connectToUrl(config.haUrl, config.haToken);
    } catch (e) {
      debugPrint('HA connection failed: $e');
    }

    if (config.frigateUrl.isNotEmpty) {
      final frigate = container.read(frigateServiceProvider);
      frigate.listenForHaEvents();
      try {
        await frigate.loadCameras();
      } catch (e) {
        debugPrint('Frigate camera load failed: $e');
      }
    }

    final displayMode = container.read(displayModeServiceProvider);
    if (config.nightModeSource == 'ha_entity' &&
        config.nightModeHaEntity != null) {
      displayMode.listenToHaEntity(ha, config.nightModeHaEntity!);
    }
  }

  // --- Connect to Music Assistant ---
  if (config.musicAssistantUrl.isNotEmpty &&
      config.musicAssistantToken.isNotEmpty) {
    final music = container.read(musicAssistantServiceProvider);
    try {
      await music.connectToUrl(
          config.musicAssistantUrl, config.musicAssistantToken);
    } catch (e) {
      debugPrint('Music Assistant connection failed: $e');
    }
  }

  // --- Load Immich memories ---
  if (config.immichUrl.isNotEmpty && config.immichApiKey.isNotEmpty) {
    final immich = container.read(immichServiceProvider);
    try {
      await immich.loadMemories();
      if (!kIsWeb) {
        await immich.prefetchPhotos();
      }
    } catch (e) {
      debugPrint('Immich load failed: $e');
    }
  }

  // --- Start local API server (native only) ---
  if (!kIsWeb) {
    final apiServer = container.read(localApiServerProvider);
    try {
      final port = await apiServer.start();
      debugPrint('Local API server listening on port $port');
    } catch (e) {
      debugPrint('API server start failed: $e');
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HearthApp(),
    ),
  );
}
