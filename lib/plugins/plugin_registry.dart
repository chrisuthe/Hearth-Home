import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import 'hearth_plugin.dart';

/// First-party plugins. Community contributors add entries here via PR.
/// Order within a category is determined by [HearthPlugin.order].
List<HearthPlugin> _firstPartyPlugins = const [
  // Plugins appear here as they are implemented. WeatherPlugin lands
  // in Task 11 of the Phase 1 plan.
];

/// All plugins, sorted by category then order. Community plugins fall
/// after first-party plugins within the same `(category, order)` bucket.
final allPluginsProvider = Provider<List<HearthPlugin>>((ref) {
  return sortPlugins(_firstPartyPlugins);
});

/// Stable sort: category (feature first), then order ascending, then
/// first-party-before-community as the tiebreaker.
List<HearthPlugin> sortPlugins(List<HearthPlugin> plugins) {
  final list = [...plugins];
  list.sort((a, b) {
    final byCategory = a.category.index.compareTo(b.category.index);
    if (byCategory != 0) return byCategory;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    // First-party before community.
    if (a.isCommunity != b.isCommunity) return a.isCommunity ? 1 : -1;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// Test/integration helper to inspect the registered first-party plugins.
/// Production code consumes [allPluginsProvider]; this getter is exposed
/// for symmetry but is not the recommended entry point.
@visibleForTesting
List<HearthPlugin> get firstPartyPlugins => _firstPartyPlugins;
