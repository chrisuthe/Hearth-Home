import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/plugin_panel.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _DummyPlugin extends HearthPlugin {
  @override String get id => 'hearth.dummy';
  @override String get name => 'Dummy';
  @override IconData get icon => Icons.bug_report;
  @override PluginCategory get category => PluginCategory.feature;
  @override int get order => 0;
  @override bool get isCommunity => false;
  @override PluginConfigStatus statusFor(HubConfig c) => PluginConfigStatus.configured;
  @override Widget buildSettingsWidget(WidgetRef ref) =>
      const Text('Dummy panel content');
  @override String buildSettingsHtml(WebContext ctx) => '';
}

void main() {
  testWidgets('PluginPanel renders the plugin name + the plugin widget',
      (tester) async {
    final plugin = _DummyPlugin();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: PluginPanel(plugin: plugin))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dummy'), findsOneWidget);
    expect(find.text('Dummy panel content'), findsOneWidget);
  });
}
