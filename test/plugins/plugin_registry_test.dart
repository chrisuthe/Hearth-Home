import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/plugin_registry.dart';

class _Fake extends HearthPlugin {
  @override final String id;
  @override final String name;
  @override final IconData icon = Icons.extension;
  @override final PluginCategory category;
  @override final int order;
  @override final bool isCommunity;
  _Fake({
    required this.id,
    required this.name,
    required this.category,
    required this.order,
    this.isCommunity = false,
  });
  @override PluginConfigStatus statusFor(HubConfig c) => PluginConfigStatus.configured;
  @override Widget buildSettingsWidget(WidgetRef ref) => const SizedBox();
  @override String buildSettingsHtml(WebContext ctx) => '';
}

void main() {
  group('sortPlugins', () {
    test('groups by category then by order ascending', () {
      final plugins = [
        _Fake(id: 'a', name: 'A', category: PluginCategory.device, order: 20),
        _Fake(id: 'b', name: 'B', category: PluginCategory.feature, order: 30),
        _Fake(id: 'c', name: 'C', category: PluginCategory.feature, order: 10),
        _Fake(id: 'd', name: 'D', category: PluginCategory.device, order: 10),
      ];
      final sorted = sortPlugins(plugins);
      expect(sorted.map((p) => p.id), ['c', 'b', 'd', 'a']);
    });

    test('within same category and order, community comes after first-party', () {
      final plugins = [
        _Fake(id: 'community.x', name: 'CX', category: PluginCategory.feature, order: 10, isCommunity: true),
        _Fake(id: 'hearth.y', name: 'HY', category: PluginCategory.feature, order: 10, isCommunity: false),
      ];
      final sorted = sortPlugins(plugins);
      expect(sorted.map((p) => p.id), ['hearth.y', 'community.x']);
    });
  });
}
