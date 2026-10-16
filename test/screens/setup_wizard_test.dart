import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/app.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/setup/setup_wizard.dart';
import 'package:hearth/services/wifi_service.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

class FakeWifiService extends WifiService {
  int scans = 0;
  @override
  Future<List<WifiNetwork>> scan() async {
    scans++;
    return [];
  }
  @override
  Future<bool> connect(String ssid, String password) async => false;
  @override
  Future<bool> connectOpen(String ssid) async => false;
  @override
  Future<String?> activeConnection() async => null;
}

void main() {
  group('SetupWizard', () {
    final testOverrides = [
      hubConfigProvider.overrideWith((ref) => HubConfigNotifier()),
      wifiServiceProvider.overrideWithValue(FakeWifiService()),
    ];

    testWidgets('shows welcome message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Welcome to Hearth'), findsOneWidget);
    });

    testWidgets('shows skip button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('HearthApp shows setup wizard when haUrl is empty',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((ref) => HubConfigNotifier()),
            wifiServiceProvider.overrideWithValue(FakeWifiService()),
          ],
          child: const HearthApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Hearth'), findsOneWidget);
    });
  });

  group('SetupWizard when the OS owns Wi-Fi', () {
    setUp(() => debugWifiManagedBySystemOverride = true);
    tearDown(() => debugWifiManagedBySystemOverride = null);

    testWidgets('skips the Wi-Fi step and offers Continue', (tester) async {
      final wifi = FakeWifiService();
      final config = _MemoryConfigNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((ref) => config),
            wifiServiceProvider.overrideWithValue(wifi),
          ],
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      await tester.pump();

      expect(wifi.scans, 0);
      expect(find.text("Hearth uses this device's Wi-Fi connection"),
          findsOneWidget);
      expect(find.text('Continue setup from a browser:'), findsOneWidget);
      expect(find.text('Rescan'), findsNothing);
      expect(find.text('Skip'), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(config.state.setupComplete, isTrue);
    });
  });
}
