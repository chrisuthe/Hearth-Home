import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'hearth_module.dart';
import 'media/media_module.dart';
import 'controls/controls_module.dart';
import 'cameras/cameras_module.dart';
import 'mealie/mealie_module.dart';

/// All available modules. Order here doesn't matter — defaultOrder controls display.
final allModules = <HearthModule>[
  MediaModule(),
  ControlsModule(),
  CamerasModule(),
  MealieModule(),
];

/// Modules that are currently enabled, ordered by moduleOrder (if set) or defaultOrder.
final enabledModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final enabledIds = config.enabledModules;
  final enabled = allModules.where((m) => enabledIds.contains(m.id)).toList();

  if (config.moduleOrder.isNotEmpty) {
    // Custom order: sort by position in moduleOrder list.
    // Modules not in the list go at the end, sorted by defaultOrder.
    enabled.sort((a, b) {
      final aIdx = config.moduleOrder.indexOf(a.id);
      final bIdx = config.moduleOrder.indexOf(b.id);
      if (aIdx >= 0 && bIdx >= 0) return aIdx.compareTo(bIdx);
      if (aIdx >= 0) return -1;
      if (bIdx >= 0) return 1;
      return a.defaultOrder.compareTo(b.defaultOrder);
    });
  } else {
    enabled.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  }

  return enabled;
});
