import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/network/network_plugin.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  group('NetworkPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = NetworkPlugin();
      expect(p.id, 'hearth.network');
      expect(p.name, 'Network');
      expect(p.category, PluginCategory.device);
      expect(p.order, 60);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = NetworkPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('pageScreen is null', () {
      final p = NetworkPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml emits WiFi scan UI', () {
      final p = NetworkPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.network',
      ));
      expect(html, contains('Scan for networks'));
      expect(html, contains('/api/wifi/scan'));
      expect(html, contains('/api/wifi/connect'));
    });

    test('buildSettingsHtml omits PIN display on web', () {
      final p = NetworkPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.network',
      ));
      // PIN is only shown on-device; the web HTML must not leak it.
      expect(html, isNot(contains('Web Portal PIN')));
    });

    testWidgets(
      'buildSettingsWidget shows both URLs and a QR code',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceIpProvider.overrideWith((ref) async => '192.168.1.50'),
              webPinProvider.overrideWithValue('1234'),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) =>
                      NetworkPlugin().buildSettingsWidget(ref),
                ),
              ),
            ),
          ),
        );
        // Let the deviceIpProvider future resolve.
        await tester.pumpAndSettle();

        expect(find.text('http://192.168.1.50:8090'), findsOneWidget);
        expect(find.text('http://hearth.local:8090'), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
      },
    );
  });
}
