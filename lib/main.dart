import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'config/hub_config.dart';

/// Target resolution: half the 11" AMOLED's native 2368x1728.
/// The panel upscales from this render resolution, giving us smooth
/// performance on the Pi 5 while still looking sharp.
const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted configuration before building the widget tree.
  // This ensures all providers have valid config on first frame.
  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HomeHubApp(),
    ),
  );
}
