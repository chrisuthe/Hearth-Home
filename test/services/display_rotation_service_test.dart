import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/display_orientation.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/display_rotation_service.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void main() {
  group('DisplayRotationService.statusFor', () {
    DisplayRotationService pi(String? applied) => DisplayRotationService(
          environment: {if (applied != null) kAppliedRotationEnv: applied},
          isLinux: true,
          runProcess: (_, __) async => ProcessResult(0, 0, '', ''),
        );

    test('in effect when the launch rotation matches the setting', () {
      expect(pi('0').statusFor(DisplayOrientation.auto), RotationStatus.inEffect);
      expect(pi('0').statusFor(DisplayOrientation.landscape),
          RotationStatus.inEffect);
      expect(pi('90').statusFor(DisplayOrientation.portrait),
          RotationStatus.inEffect);
      expect(pi('180').statusFor(DisplayOrientation.landscapeFlipped),
          RotationStatus.inEffect);
      expect(pi('270').statusFor(DisplayOrientation.portraitFlipped),
          RotationStatus.inEffect);
    });

    test('restart needed when they differ', () {
      expect(pi('0').statusFor(DisplayOrientation.portrait),
          RotationStatus.restartNeeded);
      expect(pi('90').statusFor(DisplayOrientation.auto),
          RotationStatus.restartNeeded);
      expect(pi('90').statusFor(DisplayOrientation.portraitFlipped),
          RotationStatus.restartNeeded);
    });

    test('launcher missing when the env var is absent or unparseable', () {
      expect(pi(null).statusFor(DisplayOrientation.portrait),
          RotationStatus.launcherMissing);
      expect(pi(null).statusFor(DisplayOrientation.auto),
          RotationStatus.launcherMissing);
      expect(pi('').statusFor(DisplayOrientation.portrait),
          RotationStatus.launcherMissing);
      expect(pi(null).appliedDegrees, isNull);
      expect(pi('270').appliedDegrees, 270);
    });

    test('always in effect off Linux, whatever the environment says', () {
      for (final env in [<String, String>{}, {kAppliedRotationEnv: '0'}]) {
        final service =
            DisplayRotationService(environment: env, isLinux: false);
        for (final o in DisplayOrientation.values) {
          expect(service.statusFor(o), RotationStatus.inEffect);
        }
      }
    });
  });

  group('DisplayRotationService.restart', () {
    test('restarts hearth.service through non-interactive sudo', () async {
      final calls = <List<String>>[];
      final service = DisplayRotationService(
        environment: const {},
        isLinux: true,
        runProcess: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await service.restart(), isTrue);
      expect(calls, [
        ['sudo', '-n', 'systemctl', 'restart', 'hearth.service']
      ]);
    });

    test('reports failure on a non-zero exit or a spawn error', () async {
      final denied = DisplayRotationService(
        environment: const {},
        isLinux: true,
        runProcess: (_, __) async =>
            ProcessResult(0, 1, '', 'sudo: a password is required'),
      );
      expect(await denied.restart(), isFalse);

      final missing = DisplayRotationService(
        environment: const {},
        isLinux: true,
        runProcess: (_, __) async =>
            throw const ProcessException('sudo', [], 'not found'),
      );
      expect(await missing.restart(), isFalse);
    });

    test('never spawns anything off Linux', () async {
      var spawned = false;
      final service = DisplayRotationService(
        environment: const {},
        isLinux: false,
        runProcess: (_, __) async {
          spawned = true;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await service.restart(), isFalse);
      expect(spawned, isFalse);
    });
  });

  group('Android orientation', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sent = <List<dynamic>>[];

    setUp(() {
      sent.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          sent.add(call.arguments as List<dynamic>);
        }
        return null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    ProviderContainer containerWith(String orientation) {
      final container = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier()
          ..state = HubConfig(displayOrientation: orientation)),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('applied at startup and again on every change', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = containerWith('portrait');

      container.read(androidOrientationProvider);
      await pumpEventQueue();
      expect(sent, [
        ['DeviceOrientation.portraitUp']
      ]);

      await container
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(displayOrientation: 'landscapeFlipped'));
      await pumpEventQueue();
      expect(sent.last, ['DeviceOrientation.landscapeRight']);

      await container
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(displayOrientation: 'auto'));
      await pumpEventQueue();
      expect(sent.last, hasLength(4));
      expect(sent, hasLength(3));
    });

    test('unrelated config changes do not re-apply it', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = containerWith('portrait');
      container.read(androidOrientationProvider);
      await pumpEventQueue();

      await container
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(use24HourClock: true));
      await pumpEventQueue();
      expect(sent, hasLength(1));
    });

    test('does nothing on other platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final container = containerWith('portrait');
      container.read(androidOrientationProvider);
      await pumpEventQueue();
      expect(sent, isEmpty);
    });
  });
}
