import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'hearth_module.dart';
import 'alarm_clock/alarm_clock_module.dart';
import 'media/media_module.dart';
import 'controls/controls_module.dart';
import 'cameras/cameras_module.dart';
import 'protect/protect_module.dart';
import 'mealie/mealie_module.dart';
import 'webview/webview_module.dart';

/// Static, app-lifetime modules. These don't depend on config.
final List<HearthModule> _staticModules = <HearthModule>[
  AlarmClockModule(),
  MediaModule(),
  ControlsModule(),
  CamerasModule(),
  ProtectModule(),
  MealieModule(),
];

/// All modules for a given config: static modules first, then webviews in
/// their configured order. Plain (non-Riverpod) accessor so code without a
/// [WidgetRef] — e.g. the Screens & Order web panel render — can enumerate
/// modules. Widget code should prefer [allModulesProvider].
List<HearthModule> modulesForConfig(HubConfig config) => [
      ..._staticModules,
      ...config.webviews.map((w) => WebviewModule(config: w)),
    ];

/// All modules available in the app, including dynamic ones derived from
/// the user's webview configuration. Static modules come first; webviews
/// follow in their configured order.
final allModulesProvider = Provider<List<HearthModule>>((ref) {
  return modulesForConfig(ref.watch(hubConfigProvider));
});

/// Modules placed in the swipe PageView, sorted by order.
final swipeModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final all = ref.watch(allModulesProvider);
  final placements = config.modulePlacements;
  // Webviews are always swipe-placed; the user only un-places by removing
  // them, not by re-placing into a menu.
  final modules = all.where((m) {
    if (m is WebviewModule) return true;
    return (placements[m.id] ?? []).contains('swipe');
  }).toList();
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
  final all = ref.watch(allModulesProvider);
  final placements = config.modulePlacements;
  final modules = all
      .where((m) => m is! WebviewModule && (placements[m.id] ?? []).contains(menuId))
      .toList();
  modules.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  return modules;
}
