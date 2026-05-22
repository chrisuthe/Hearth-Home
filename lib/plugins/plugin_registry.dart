import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alarm_clock/alarm_clock_plugin.dart';
import 'display/display_plugin.dart';
import 'frigate/frigate_plugin.dart';
import 'hearth_plugin.dart';
import 'home_assistant/home_assistant_plugin.dart';
import 'immich/immich_plugin.dart';
import 'mealie/mealie_plugin.dart';
import 'music_assistant/music_assistant_plugin.dart';
import 'network/network_plugin.dart';
import 'sendspin/sendspin_plugin.dart';
import 'voice/voice_plugin.dart';
import 'weather/weather_plugin.dart';
import 'webview/webview_plugin.dart';

/// First-party plugins. Community contributors add entries here via PR.
/// Order within a category is determined by [HearthPlugin.order].
List<HearthPlugin> _firstPartyPlugins = [
  WeatherPlugin(),
  HomeAssistantPlugin(),
  MealiePlugin(),
  ImmichPlugin(),
  MusicAssistantPlugin(),
  FrigatePlugin(),
  AlarmClockPlugin(),
  SendspinPlugin(),
  WebviewPlugin(),
  DisplayPlugin(),
  VoicePlugin(),
  NetworkPlugin(),
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
