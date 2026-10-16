import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/screen_background.dart';
import '../modules/module_registry.dart';
import 'theme/theme_providers.dart';

/// Id of the page on screen: `home`, `settings` or a module id. HubShell
/// sets it on every page change. While a route is pushed over the shell
/// (an edge-menu module, the timer) it reads `route:<id>`.
final currentPageProvider = StateProvider<String>((ref) => 'home');

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
