import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/setup/setup_wizard.dart';
import 'package:hearth/services/wifi_service.dart';

import 'portrait_harness.dart';

const _home = 'The home network with a deliberately long SSID';

class _FakeWifi extends WifiService {
  _FakeWifi({this.active, this.scanGate, this.connects = false});

  /// SSID reported as already connected, if any.
  final String? active;

  /// When set, `scan` waits on it — holds the wizard in its scanning state.
  final Completer<void>? scanGate;

  final bool connects;

  @override
  Future<List<WifiNetwork>> scan() async {
    await scanGate?.future;
    return [
      const WifiNetwork(ssid: _home, signalStrength: 92, security: 'WPA2 WPA3'),
      for (var i = 0; i < 14; i++)
        WifiNetwork(
          ssid: 'A neighbouring network with a long SSID $i',
          signalStrength: 85 - i * 6,
          security: i.isEven ? 'WPA2' : '',
        ),
    ];
  }

  @override
  Future<bool> connect(String ssid, String password) async => connects;
  @override
  Future<bool> connectOpen(String ssid) async => connects;
  @override
  Future<String?> activeConnection() async => active;
}

class _MemoryConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

Future<void> _pumpWizard(WidgetTester tester, _FakeWifi wifi) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier()),
      wifiServiceProvider.overrideWithValue(wifi),
    ],
    child: hostScreen(const SetupWizard()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testLayouts('setup wizard: scanning', (tester, canvas) async {
    final gate = Completer<void>();
    await _pumpWizard(tester, _FakeWifi(scanGate: gate));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    gate.complete();
    await tester.pump();
  });

  testLayouts('setup wizard: network list, not connected',
      (tester, canvas) async {
    await _pumpWizard(tester, _FakeWifi());
    expect(find.text(_home), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    // The actions stay on screen below the list rather than being pushed off.
    expect(tester.getBottomLeft(find.text('Skip')).dy, lessThan(canvas.height));
    expect(tester.getBottomRight(find.text('Rescan')).dx,
        lessThan(canvas.width));
  });

  testLayouts('setup wizard: connected, with the portal address',
      (tester, canvas) async {
    await _pumpWizard(tester, _FakeWifi(active: _home));
    expect(find.text('Connected to $_home'), findsOneWidget);
    expect(find.text('Continue setup from a browser:'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Continue')).dy,
        lessThan(canvas.height));
    expect(tester.getBottomRight(find.text('Continue')).dx,
        lessThan(canvas.width));
  });

  testLayouts('setup wizard: password prompt, then a failed connection',
      (tester, canvas) async {
    await _pumpWizard(tester, _FakeWifi());
    await tester.tap(find.text(_home));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter password for $_home'), findsOneWidget);
    expectNoLayoutErrors(tester, 'password prompt at $canvas');

    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Wrong password or connection failed'), findsOneWidget);
  });

  testLayouts('setup wizard: open network that fails to join',
      (tester, canvas) async {
    await _pumpWizard(tester, _FakeWifi());
    await tester.tap(find.text('A neighbouring network with a long SSID 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Failed to connect to'), findsOneWidget);
  });
  testLayouts('setup wizard: joining an open network offers Continue',
      (tester, canvas) async {
    await _pumpWizard(tester, _FakeWifi(connects: true));
    const ssid = 'A neighbouring network with a long SSID 1';
    await tester.tap(find.text(ssid));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Connected to $ssid'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Continue')).dx,
        lessThan(canvas.width));
  });
}
