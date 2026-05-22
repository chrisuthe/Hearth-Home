import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hearth_plugin.dart';
import 'mealie/mealie_plugin.dart';
import 'weather/weather_plugin.dart';

/// First-party plugins. Community contributors add entries here via PR.
/// Order within a category is determined by [HearthPlugin.order].
List<HearthPlugin> _firstPartyPlugins = [
  WeatherPlugin(),
  MealiePlugin(),
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

/// Direct accessor for the registered first-party plugins. Used by
/// non-Riverpod code paths (e.g. [LocalApiServer]) that don't have a
/// [WidgetRef]. Widget code should prefer [allPluginsProvider].
List<HearthPlugin> get firstPartyPlugins => _firstPartyPlugins;
