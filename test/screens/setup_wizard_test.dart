import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/app.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/setup/setup_wizard.dart';
import 'package:hearth/services/wifi_service.dart';

class FakeWifiService extends WifiService {
  @override
  Future<List<WifiNetwork>> scan() async => [];
  @override
  Future<bool> connect(String ssid, String password) async => false;
  @override
  Future<bool> connectOpen(String ssid) async => false;
  @override
  Future<String?> activeConnection() async => null;
  @override
  Future<bool> disconnect() async => false;
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
}
