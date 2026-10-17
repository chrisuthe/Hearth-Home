import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/screen_background.dart';
import '../modules/module_registry.dart';
import 'theme/theme_providers.dart';

/// The shell's live PageView page: `home`, `settings` or a module id.
/// HubShell sets it on every page change, including while a route covers it.
final basePageProvider = StateProvider<String>((ref) => 'home');

/// Name of the topmost opaque page route pushed over the shell, or null when
/// none is. [PageRouteObserver] sets it.
final openRouteProvider = StateProvider<String?>((ref) => null);

/// Id of the page on screen: the shell's page, or `route:<name>` while an
/// opaque route (an edge-menu module, the timer, the alarm editor) covers it.
final currentPageProvider = Provider<String>((ref) {
  final route = ref.watch(openRouteProvider);
  return route == null ? ref.watch(basePageProvider) : 'route:$route';
});

/// The app's [PageRouteObserver], registered on `MaterialApp`. One instance,
/// since it keeps the route stack it has seen.
final pageRouteObserverProvider = Provider<PageRouteObserver>((ref) =>
    PageRouteObserver((name) => ref.read(openRouteProvider.notifier).state = name));

/// Reports the topmost opaque [PageRoute] pushed above the navigator's first
/// route, by its [RouteSettings.name] (`pushed` when it has none), or null
/// once the navigator is back at the first route. Dialogs, popups and
/// see-through routes are not page routes covering the shell, so it ignores
/// them.
class PageRouteObserver extends NavigatorObserver {
  PageRouteObserver(this.onChanged);

  final ValueChanged<String?> onChanged;

  /// The tracked routes, bottom to top.
  final _routes = <Route<dynamic>>[];
  String? _published;

  static bool _covers(Route<dynamic>? route) =>
      route is PageRoute && route.opaque;

  void _publish() {
    final name =
        _routes.isEmpty ? null : (_routes.last.settings.name ?? 'pushed');
    if (name == _published) return;
    _published = name;
    onChanged(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // No previous route: this is the first one, the shell itself.
    if (previousRoute == null || !_covers(route)) return;
    _routes.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i < 0) return;
    if (_covers(newRoute)) {
      _routes[i] = newRoute!;
    } else {
      _routes.removeAt(i);
    }
    _publish();
  }
}

/// Whether the memory photo shows through the current page. Home and
/// Settings always show it; a module shows it when it tints the photo or
/// when the Background setting is blurred.
final photoVisibleProvider = Provider<bool>((ref) {
  final page = ref.watch(currentPageProvider);
  if (page == 'home' || page == 'settings') return true;
  final blurred =
      ref.watch(screenBackgroundProvider) == ScreenBackground.blurred;
  // A pushed route is opaque and covers the shell's photo, so only the
  // blurred backdrop it paints itself shows one.
  if (page.startsWith('route:')) return blurred;
  if (blurred) return true;
  final modules = ref.watch(allModulesProvider);
  return modules.any((m) => m.id == page && m.showsPhoto);
});
