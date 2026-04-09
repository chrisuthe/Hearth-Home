import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'hearth_module.dart';

/// All available modules. Order here doesn't matter — defaultOrder controls display.
/// NOTE: Module imports will be added as modules are created in later tasks.
final allModules = <HearthModule>[];

/// Modules that are currently enabled, sorted by defaultOrder.
final enabledModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final enabledIds = config.enabledModules;
  return allModules
      .where((m) => enabledIds.contains(m.id))
      .toList()
    ..sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
});
