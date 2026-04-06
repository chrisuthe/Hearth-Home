import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'config/hub_config.dart';
import 'services/home_assistant_service.dart';
import 'services/immich_service.dart';
import 'services/music_assistant_service.dart';
import 'services/frigate_service.dart';
import 'services/display_mode_service.dart';
import 'services/local_api_server.dart';

/// Target resolution: half the 11" AMOLED's native 2368x1728.
/// The panel upscales from this render resolution, giving us smooth
/// performance on the Pi 5 while still looking sharp.
const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for RTSP camera stream playback.
  // Uses libmpv on Windows/Linux desktop, GStreamer on Pi via flutter-pi.
  MediaKit.ensureInitialized();

  // Load persisted configuration before building the widget tree.
  // This ensures all providers have valid config on first frame.
  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  final config = container.read(hubConfigProvider);

  // --- Connect to Home Assistant ---
  // HA is the backbone: Music Assistant, Frigate events, and night mode
  // all flow through the HA WebSocket. Connect first, then start consumers.
  if (config.haUrl.isNotEmpty && config.haToken.isNotEmpty) {
    final ha = container.read(homeAssistantServiceProvider);
    try {
      await ha.connectToUrl(config.haUrl, config.haToken);
    } catch (e) {
      debugPrint('HA connection failed: $e');
    }

    // Music Assistant: filter HA media_player entities for playback state
    final music = container.read(musicAssistantServiceProvider);
    music.startListening();

    // Frigate: real-time events via HA binary_sensor entities
    if (config.frigateUrl.isNotEmpty) {
      final frigate = container.read(frigateServiceProvider);
      frigate.listenForHaEvents();
      try {
        await frigate.loadCameras();
      } catch (e) {
        debugPrint('Frigate camera load failed: $e');
      }
    }

    // Night mode: watch an HA entity (e.g., living room light off = bedtime)
    final displayMode = container.read(displayModeServiceProvider);
    if (config.nightModeSource == 'ha_entity' &&
        config.nightModeHaEntity != null) {
      displayMode.listenToHaEntity(ha, config.nightModeHaEntity!);
    }
  }

  // --- Load Immich memories ---
  // Pre-fetch today's "on this day" photos for the ambient display.
  // Shuffled and cached to disk so transitions are instant.
  if (config.immichUrl.isNotEmpty && config.immichApiKey.isNotEmpty) {
    final immich = container.read(immichServiceProvider);
    try {
      await immich.loadMemories();
      await immich.prefetchPhotos();
    } catch (e) {
      debugPrint('Immich load failed: $e');
    }
  }

  // --- Start local API server ---
  // Allows external devices to control display mode via HTTP.
  final apiServer = container.read(localApiServerProvider);
  try {
    final port = await apiServer.start();
    debugPrint('Local API server listening on port $port');
  } catch (e) {
    debugPrint('API server start failed: $e');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HearthApp(),
    ),
  );
}
