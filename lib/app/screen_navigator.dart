import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import '../modules/hearth_module.dart';
import '../modules/module_registry.dart';
import 'current_screen_provider.dart';

/// One page of HubShell's PageView.
class ShellScreen {
  /// A module id, or "home"/"settings" for the two non-module pages.
  final String id;
  final String name;

  const ShellScreen({required this.id, required this.name});
}

/// HubShell's page order: [left] modules, Home, [right] modules, Settings.
class ShellLayout {
  final List<HearthModule> left;
  final List<HearthModule> right;

  const ShellLayout({required this.left, required this.right});

  int get homeIndex => left.length;

  /// Every page, in PageView order.
  List<ShellScreen> get screens => [
        for (final m in left) ShellScreen(id: m.id, name: m.name),
        const ShellScreen(id: 'home', name: 'Home'),
        for (final m in right) ShellScreen(id: m.id, name: m.name),
        const ShellScreen(id: 'settings', name: 'Settings'),
      ];
}

/// The swipe row as HubShell lays it out. Shared with [ScreenNavigator] so a
/// page index means the same thing to the API, MQTT and the PageView.
final shellLayoutProvider = Provider<ShellLayout>((ref) {
  final modules = ref.watch(swipeModulesProvider);
  final hasCustomOrder =
      ref.watch(hubConfigProvider.select((c) => c.moduleOrder.isNotEmpty));
  // With custom ordering, all modules go right of Home.
  // With default ordering, negative defaultOrder goes left.
  if (hasCustomOrder) return ShellLayout(left: const [], right: modules);
  return ShellLayout(
    left: modules.where((m) => m.defaultOrder < 0).toList(),
    right: modules.where((m) => m.defaultOrder >= 0).toList(),
  );
});

/// Lets code outside HubShell (the local API, MQTT) change the page.
///
/// HubShell subscribes to [requests] and animates to each screen it receives,
/// treating the request as user activity.
class ScreenNavigator {
  ScreenNavigator(this._ref);

  final Ref _ref;
  final _requests = StreamController<String>.broadcast();

  /// Screen ids HubShell should show, in request order.
  Stream<String> get requests => _requests.stream;

  List<ShellScreen> get screens => _ref.read(shellLayoutProvider).screens;

  CurrentScreen get current => _ref.read(currentScreenProvider);

  /// The screen [idOrName] names: an exact id first, else a case-insensitive
  /// name (what a Home Assistant select sends). Null when none matches.
  ShellScreen? resolve(String idOrName) {
    final key = idOrName.trim();
    final all = screens;
    for (final s in all) {
      if (s.id == key) return s;
    }
    final lower = key.toLowerCase();
    for (final s in all) {
      if (s.name.toLowerCase() == lower) return s;
    }
    return null;
  }

  /// Asks HubShell to show [idOrName]. Returns the screen, or null when it is
  /// not in the swipe row.
  ShellScreen? show(String idOrName) {
    final screen = resolve(idOrName);
    if (screen != null) _requests.add(screen.id);
    return screen;
  }

  void dispose() => _requests.close();
}

final screenNavigatorProvider = Provider<ScreenNavigator>((ref) {
  final navigator = ScreenNavigator(ref);
  ref.onDispose(navigator.dispose);
  return navigator;
});
