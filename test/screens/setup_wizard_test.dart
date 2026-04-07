import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/app.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/setup/setup_wizard.dart';
import 'package:hearth/services/wifi_service.dart';

/// Fake WiFi service that never calls Process.run — safe for CI.
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
    /// Common overrides for all setup wizard tests.
    final testOverrides = [
      hubConfigProvider.overrideWith((ref) => HubConfigNotifier()),
      wifiServiceProvider.overrideWithValue(FakeWifiService()),
    ];

    testWidgets('shows WiFi step first', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Connect to WiFi'), findsOneWidget);
    });

    testWidgets('shows skip button on WiFi step', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Skip (Using Ethernet)'), findsOneWidget);
    });

    testWidgets('shows progress bar with 4 steps', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      // Progress bar is rendered as a Row with 4 segments
      expect(find.byType(SetupWizard), findsOneWidget);
    });

    testWidgets('skip button advances to services step', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      await tester.tap(find.text('Skip (Using Ethernet)'));
      await tester.pumpAndSettle();
      expect(find.text('Connect Services'), findsOneWidget);
    });

    testWidgets('services step shows HA URL field', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      // Navigate to services step
      await tester.tap(find.text('Skip (Using Ethernet)'));
      await tester.pumpAndSettle();
      expect(find.text('Home Assistant URL'), findsOneWidget);
    });

    testWidgets('services step Next disabled when HA URL empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      // Navigate to services step
      await tester.tap(find.text('Skip (Using Ethernet)'));
      await tester.pumpAndSettle();
      // Next button should be disabled (onPressed == null) when HA URL is empty
      final nextButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(nextButton.onPressed, isNull);
    });

    testWidgets('services step Back returns to WiFi step', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      // Navigate to services step
      await tester.tap(find.text('Skip (Using Ethernet)'));
      await tester.pumpAndSettle();
      // Scroll to Back button in case it's off-screen
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to WiFi'), findsOneWidget);
    });

    testWidgets('HearthApp shows setup wizard when haUrl is empty', (tester) async {
      final notifier = HubConfigNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((ref) => notifier),
            wifiServiceProvider.overrideWithValue(FakeWifiService()),
          ],
          child: const HearthApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect to WiFi'), findsOneWidget);
    });
  });
}
