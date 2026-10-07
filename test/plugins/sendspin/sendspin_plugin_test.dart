import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/sendspin/sendspin_plugin.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

    test('buildSettingsHtml renders Buffer Size bound to the int field', () {
      // Buffer Size is now editable on web (Enabler A coerces the string the
      // <select> posts into the int field). readOverride renders the current
      // int value as the selected option.
      final p = SendspinPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(
          sendspinPlayerName: 'Kitchen',
          sendspinBufferSeconds: 10,
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.sendspin',
      ));
      expect(html, contains('Buffer Size'));
      expect(html, contains('data-config-path="sendspinBufferSeconds"'));
      // Current value (10) is the selected option.
      expect(RegExp(r'value="10"\s+selected').hasMatch(html), isTrue);
    });

    test('pageScreen is null', () {
      final p = SendspinPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml offers the unpaired access toggle', () {
      final p = SendspinPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(sendspinPlayerName: 'Kitchen'),
        apiBearerToken: 'k',
        pluginActionPrefix: '/api/plugin/hearth.sendspin',
      ));
      expect(html, contains('Allow unpaired servers'));
      expect(html, contains('data-config-path="sendspinUnpairedAccess"'));
    });

    Future<_MemoryHubConfigNotifier> pumpPanel(
      WidgetTester tester,
      HubConfig config,
      SendspinService service,
    ) async {
      final notifier = _MemoryHubConfigNotifier(config);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((_) => notifier),
            // The real provider would open sockets and touch path_provider.
            sendspinServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, __) => SingleChildScrollView(
                    child: SendspinPlugin().buildSettingsWidget(ref)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return notifier;
    }

    testWidgets('enable toggle turns the player on', (tester) async {
      final service = SendspinService();
      addTearDown(service.dispose);
      final notifier = await pumpPanel(
          tester, const HubConfig(sendspinPlayerName: 'Kitchen'), service);
      expect(notifier.state.sendspinEnabled, isFalse);

      // First SwitchListTile in the panel is the enable toggle.
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(notifier.state.sendspinEnabled, isTrue);
    });

    testWidgets('unpaired access toggle writes the setting', (tester) async {
      final service = SendspinService();
      addTearDown(service.dispose);
      final notifier = await pumpPanel(
          tester, const HubConfig(sendspinPlayerName: 'Kitchen'), service);
      expect(notifier.state.sendspinUnpairedAccess, isTrue);

      await tester.tap(
          find.widgetWithText(SwitchListTile, 'Allow unpaired servers'));
      await tester.pumpAndSettle();

      expect(notifier.state.sendspinUnpairedAccess, isFalse);
    });

    testWidgets('pairing token is hidden while the player is disabled',
        (tester) async {
      final service = SendspinService();
      addTearDown(service.dispose);
      service.pairingInfo.value = const SendspinPairingInfo(
          clientId: 'id', pairingToken: 'SP:0TOKEN', pairedServers: 0);
      await pumpPanel(
          tester, const HubConfig(sendspinPlayerName: 'Kitchen'), service);

      expect(find.text('SP:0TOKEN'), findsNothing);
    });

    testWidgets('pairing token is shown as text and QR once loaded',
        (tester) async {
      final service = SendspinService();
      addTearDown(service.dispose);
      await pumpPanel(
        tester,
        const HubConfig(sendspinPlayerName: 'Kitchen', sendspinEnabled: true),
        service,
      );
      // Nothing to show until the service has loaded the identity.
      expect(find.byType(QrImageView), findsNothing);

      service.pairingInfo.value = const SendspinPairingInfo(
          clientId: 'id', pairingToken: 'SP:0TOKEN', pairedServers: 2);
      await tester.pumpAndSettle();

      expect(find.text('SP:0TOKEN'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Paired with 2 servers'), findsOneWidget);
    });
  });
}
