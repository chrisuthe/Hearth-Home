import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'hearth_module.dart';
import 'alarm_clock/alarm_clock_module.dart';
import 'media/media_module.dart';
import 'controls/controls_module.dart';
import 'cameras/cameras_module.dart';
import 'mealie/mealie_module.dart';

/// All available modules. Order here doesn't matter — defaultOrder controls display.
final allModules = <HearthModule>[
  AlarmClockModule(),
  MediaModule(),
  ControlsModule(),
  CamerasModule(),
  MealieModule(),
];

/// Modules placed in the swipe PageView, sorted by order.
final swipeModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final placements = config.modulePlacements;
  final modules = allModules
      .where((m) => (placements[m.id] ?? []).contains('swipe'))
      .toList();
  if (config.moduleOrder.isNotEmpty) {
    final order = config.moduleOrder;
    modules.sort((a, b) {
      final ai = order.indexOf(a.id);
      final bi = order.indexOf(b.id);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.defaultOrder.compareTo(b.defaultOrder);
    });
  } else {
    modules.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  }
  return modules;
});

/// Modules placed in the given menu, sorted by order.
List<HearthModule> menuModules(WidgetRef ref, String menuId) {
  final config = ref.watch(hubConfigProvider);
  final placements = config.modulePlacements;
  final modules = allModules
      .where((m) => (placements[m.id] ?? []).contains(menuId))
      .toList();
  modules.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  return modules;
}

/// Keep backward compat alias — returns swipe modules.
final enabledModulesProvider = swipeModulesProvider;
