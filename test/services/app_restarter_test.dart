import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/app_restarter.dart';
import 'package:hearth/services/display_rotation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux restarts hearth.service', () async {
    final calls = <List<String>>[];
    final restarter = AppRestarter(
      android: false,
      linux: true,
      linuxRestart: DisplayRotationService(
        isLinux: true,
        environment: const {},
        runProcess: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      ),
    );
    expect(restarter.canRestart, isTrue);
    expect(await restarter.restart(), isTrue);
    expect(calls, [
      ['sudo', '-n', 'systemctl', 'restart', 'hearth.service']
    ]);
  });

  test('Android asks the app to relaunch itself', () async {
    const channel = MethodChannel('test/app_update');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });
    final restarter =
        AppRestarter(android: true, linux: false, channel: channel);
    expect(restarter.canRestart, isTrue);
    expect(await restarter.restart(), isTrue);
    expect(methods, ['restartApp']);
  });

  test('elsewhere the kiosk cannot restart itself', () async {
    final restarter = AppRestarter(android: false, linux: false);
    expect(restarter.canRestart, isFalse);
    expect(await restarter.restart(), isFalse);
  });
}
