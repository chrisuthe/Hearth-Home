import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/sendspin/sendspin_plugin.dart';

/// In-memory notifier: stores state without touching the path_provider
/// platform channel (which isn't available in widget tests).
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  _MemoryHubConfigNotifier(HubConfig initial) {
    state = initial;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void main() {
  group('SendspinPlugin', () {
    test('id and category are correct', () {
      final p = SendspinPlugin();
      expect(p.id, 'hearth.sendspin');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
      expect(p.order, 80);
    });

    test('statusFor returns needsSetup when player name is empty', () {
      final p = SendspinPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.needsSetup);
    });

    test('statusFor returns configured when player name set and disabled', () {
      final p = SendspinPlugin();
      expect(
        p.statusFor(const HubConfig(sendspinPlayerName: 'Kitchen')),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns configured when player name set and enabled', () {
      final p = SendspinPlugin();
      expect(
        p.statusFor(const HubConfig(
          sendspinPlayerName: 'Kitchen',
          sendspinEnabled: true,
        )),
        PluginConfigStatus.configured,
      );
    });

    test('buildSettingsHtml contains enable, player name, and server URL', () {
      final p = SendspinPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          sendspinPlayerName: 'Kitchen Display',
          sendspinServerUrl: 'ws://192.168.1.5:8095',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.sendspin',
      ));
      expect(html, contains('Enable Sendspin Player'));
      expect(html, contains('data-config-path="sendspinEnabled"'));
      expect(html, contains('Player Name'));
      expect(html, contains('value="Kitchen Display"'));
      expect(html, contains('data-config-path="sendspinPlayerName"'));
      expect(html, contains('Server URL'));
      expect(html, contains('value="ws://192.168.1.5:8095"'));
      expect(html, contains('data-config-path="sendspinServerUrl"'));
    });

    test('buildSettingsHtml omits Buffer Size (on-device only)', () {
      final p = SendspinPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(sendspinPlayerName: 'Kitchen'),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.sendspin',
      ));
      expect(html, isNot(contains('Buffer Size')));
      expect(html, isNot(contains('sendspinBufferSeconds')));
    });

    test('pageScreen is null', () {
      final p = SendspinPlugin();
      expect(p.pageScreen, isNull);
    });

    testWidgets(
        'enable toggle generates sendspinClientId on first enable when empty',
        (tester) async {
      // Seed config with a player name (so toggle is enabled) and empty
      // clientId. Tapping the switch on should set sendspinEnabled=true AND
      // generate a non-empty sendspinClientId in a single write.
      final notifier = _MemoryHubConfigNotifier(
        const HubConfig(sendspinPlayerName: 'Kitchen'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((_) => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, __) =>
                    SingleChildScrollView(child: SendspinPlugin().buildSettingsWidget(ref)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: pre-tap state.
      expect(notifier.state.sendspinEnabled, isFalse);
      expect(notifier.state.sendspinClientId, isEmpty);

      // First SwitchListTile in the panel is the enable toggle.
      final switchTile = find.byType(SwitchListTile).first;
      await tester.tap(switchTile);
      await tester.pumpAndSettle();

      expect(notifier.state.sendspinEnabled, isTrue);
      expect(notifier.state.sendspinClientId, isNotEmpty);
      expect(notifier.state.sendspinClientId.length, 32);
    });

    testWidgets(
        'enable toggle preserves existing clientId when re-enabling',
        (tester) async {
      const existingId = 'pre-existing-client-id-value-123';
      final notifier = _MemoryHubConfigNotifier(
        const HubConfig(
          sendspinPlayerName: 'Kitchen',
          sendspinClientId: existingId,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [hubConfigProvider.overrideWith((_) => notifier)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, __) =>
                    SingleChildScrollView(child: SendspinPlugin().buildSettingsWidget(ref)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(notifier.state.sendspinEnabled, isTrue);
      // ClientId must not be regenerated when one already exists.
      expect(notifier.state.sendspinClientId, existingId);
    });
  });
}
