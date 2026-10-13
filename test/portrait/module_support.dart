import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/hearth_module.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/services/home_assistant_service.dart';

import 'portrait_harness.dart';

/// Config that never touches disk.
class MemoryConfigNotifier extends HubConfigNotifier {
  MemoryConfigNotifier([HubConfig config = const HubConfig()]) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

/// A connected Home Assistant holding a fixed entity set; service calls are
/// swallowed instead of written to a socket.
class FakeHomeAssistant extends HomeAssistantService {
  FakeHomeAssistant([List<HaEntity> entities = const []])
      : _fixed = {for (final e in entities) e.entityId: e};

  final Map<String, HaEntity> _fixed;

  @override
  Map<String, HaEntity> get entities => _fixed;

  @override
  bool get isConnected => true;

  @override
  void callService({
    required String domain,
    required String service,
    required String entityId,
    Map<String, dynamic>? data,
  }) {}
}

/// The static module with [id], as HubShell would mount it.
HearthModule staticModule(String id) =>
    modulesForConfig(const HubConfig()).firstWhere((m) => m.id == id);

/// Mounts [screen] under a provider scope with a memory-backed config.
Future<void> pumpModule(
  WidgetTester tester,
  Widget screen, {
  HubConfig config = const HubConfig(),
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hubConfigProvider.overrideWith((ref) => MemoryConfigNotifier(config)),
      ...overrides,
    ],
    child: hostScreen(screen),
  ));
  // Post-frame loads and their follow-up frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A long string that still reads like the thing it stands in for.
const kLongName =
    'Upstairs Hallway Ceiling Lights Near The Guest Bedroom Door (Zigbee Group)';
