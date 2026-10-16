import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/alarm_clock/alarm_models.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';
import 'package:hearth/services/backup/backup_service.dart';
import 'package:hearth/services/backup/sendspin_secret_files.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

class _FakeSendspinFiles implements SendspinSecretFiles {
  Map<String, String> files;
  final writes = <Map<String, String>>[];
  _FakeSendspinFiles([this.files = const {}]);

  @override
  Future<Map<String, String>> read() async => files;

  @override
  Future<void> write(Map<String, String> files) async => writes.add(files);
}

/// Records the config's apiKey at the moment the secrets are written.
class _OrderCheckingSendspinFiles implements SendspinSecretFiles {
  final String Function() _apiKey;
  String? apiKeyAtWrite;
  _OrderCheckingSendspinFiles(this._apiKey);

  @override
  Future<Map<String, String>> read() async => const {};

  @override
  Future<void> write(Map<String, String> files) async =>
      apiKeyAtWrite = _apiKey();
}

class _FailingSendspinFiles implements SendspinSecretFiles {
  @override
  Future<Map<String, String>> read() async => const {};

  @override
  Future<void> write(Map<String, String> files) =>
      throw const FileSystemException('disk full');
}

void main() {
  /// The restoring kiosk's directory.
  late Directory dir;

  /// The backed-up kiosk's, so its alarm saves never land in [dir].
  late Directory sourceDir;

  /// Alarm seeding saves; awaited before the directories are deleted.
  final seeding = <Future<void>>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hearth_backup_test');
    sourceDir = await Directory.systemTemp.createTemp('hearth_backup_src');
  });

  tearDown(() async {
    await Future.wait(seeding);
    seeding.clear();
    await dir.delete(recursive: true);
    await sourceDir.delete(recursive: true);
  });

  const sourceConfig = HubConfig(
    apiKey: 'source-key',
    haUrl: 'http://ha.local:8123',
    haToken: 'secret-ha-token',
    mqttDeviceName: 'Kitchen',
    mqttDeviceId: 'hearth_kitchen',
    plexClientId: 'plex-client-1',
  );
  const alarm = Alarm(id: 'a1', time: '06:30', label: 'Work', days: [1, 2]);
  final sendspinFiles = {
    'sendspin_identity.key': base64Encode([1, 2, 3]),
    'sendspin_pairing.json': base64Encode(utf8.encode('{"psk":"x"}')),
  };

  BackupService service({
    HubConfig config = const HubConfig(apiKey: 'target-key'),
    List<Alarm> alarms = const [],
    _FakeSendspinFiles? sendspin,
    String platform = 'linux',
    String version = '1.22.0',
    Directory? at,
  }) {
    final path = (at ?? dir).path;
    final alarmService = AlarmService(directory: () async => path);
    if (alarms.isNotEmpty) seeding.add(alarmService.replaceAll(alarms));
    return BackupService(
      config: _MemoryConfigNotifier(config),
      alarms: alarmService,
      sendspin: sendspin ?? _FakeSendspinFiles(),
      platform: platform,
      installedVersion: () async => version,
      directory: () async => path,
      now: () => DateTime.utc(2026, 10, 16, 14, 2, 11),
    );
  }

  Future<Map<String, dynamic>> sourceBackup({
    String platform = 'linux',
    String version = '1.22.0',
  }) =>
      service(
        config: sourceConfig,
        alarms: [alarm],
        sendspin: _FakeSendspinFiles(sendspinFiles),
        platform: platform,
        version: version,
        at: sourceDir,
      ).create();

  /// Asserts nothing was written by a rejected restore.
  void expectUntouched(BackupService target, _FakeSendspinFiles fake) {
    expect(target.config.current.apiKey, 'target-key');
    expect(target.alarms.alarms, isEmpty);
    expect(fake.writes, isEmpty);
    expect(dir.listSync().where((e) => e.path.endsWith('.pre-restore')),
        isEmpty);
  }

  group('create', () {
    test('carries config, alarms, sendspin and metadata', () async {
      final backup = await sourceBackup();
      expect(backup['hearthBackup'], 1);
      expect(backup['hearthVersion'], '1.22.0');
      expect(backup['platform'], 'linux');
      expect(backup['createdAt'], '2026-10-16T14:02:11.000Z');
      expect(backup['config'], sourceConfig.toJson());
      expect((backup['config'] as Map)['haToken'], 'secret-ha-token');
      expect(backup['alarms'], [alarm.toJson()]);
      expect(backup['sendspin'], {'platform': 'linux', 'files': sendspinFiles});
    });

    test('fileName sanitises the device name', () {
      final named = service(
          config: const HubConfig(mqttDeviceName: 'Kitchen / "Hub"'));
      expect(named.fileName(), 'hearth-backup-kitchen-hub-2026-10-16.json');
      expect(service().fileName(), 'hearth-backup-hearth-2026-10-16.json');
    });
  });

  group('restore', () {
    test('round trip restores config, alarms and sendspin', () async {
      final backup = jsonDecode(jsonEncode(await sourceBackup()))
          as Map<String, dynamic>;
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake);

      final result = await target.restore(backup);

      expect(result, SendspinRestore.restored);
      expect(target.config.current.toJson(), sourceConfig.toJson());
      expect(target.alarms.alarms.map((a) => a.toJson()), [alarm.toJson()]);
      expect(fake.writes, [sendspinFiles]);
    });

    test('rejects a newer format', () async {
      final backup = {...await sourceBackup(), 'hearthBackup': 2};
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake);
      await expectLater(
        target.restore(backup),
        throwsA(isA<BackupRejected>().having((e) => e.message, 'message',
            'This backup needs a newer version of Hearth.')),
      );
      expectUntouched(target, fake);
    });

    test('rejects a missing format', () async {
      final backup = {...await sourceBackup()}..remove('hearthBackup');
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake);
      await expectLater(
        target.restore(backup),
        throwsA(isA<BackupRejected>().having((e) => e.message, 'message',
            'This file is not a valid Hearth backup.')),
      );
      expectUntouched(target, fake);
    });

    test('rejects a backup from a newer Hearth', () async {
      final backup = await sourceBackup(version: '1.22.0');
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake, version: '1.21.0');
      await expectLater(
        target.restore(backup),
        throwsA(isA<BackupRejected>().having(
            (e) => e.message,
            'message',
            'This backup is from Hearth 1.22.0; update this kiosk to 1.22.0 '
                'or later first.')),
      );
      expectUntouched(target, fake);
    });

    test('accepts a backup from the same or an older Hearth', () async {
      final same = await sourceBackup(version: '1.22.0');
      await service(version: '1.22.0').restore(same);
      final older = await sourceBackup(version: '1.20.3');
      await service(version: '1.22.0').restore(older);
    });

    test('skips the version check when either version is empty', () async {
      final backup = await sourceBackup(version: '1.22.0');
      final target = service(version: '');
      await target.restore(backup);
      expect(target.config.current.apiKey, 'source-key');

      final unversioned = {...await sourceBackup(), 'hearthVersion': ''};
      await service(version: '1.0.0').restore(unversioned);
    });

    test('rejects a missing or non-object config', () async {
      for (final config in [null, 'x', 3, <dynamic>[]]) {
        final backup = {...await sourceBackup(), 'config': config};
        final fake = _FakeSendspinFiles();
        final target = service(sendspin: fake);
        await expectLater(target.restore(backup),
            throwsA(isA<BackupRejected>()), reason: 'config: $config');
        expectUntouched(target, fake);
      }
    });

    test('rejects a config with a mistyped value', () async {
      final backup = await sourceBackup();
      (backup['config'] as Map<String, dynamic>)['uiScale'] = 'huge';
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake);
      await expectLater(
          target.restore(backup), throwsA(isA<BackupRejected>()));
      expectUntouched(target, fake);
    });

    test('rejects bad alarms', () async {
      for (final alarms in [
        'x',
        [1],
        [
          {'id': 'a', 'days': ['monday']}
        ],
      ]) {
        final backup = {...await sourceBackup(), 'alarms': alarms};
        final fake = _FakeSendspinFiles();
        final target = service(sendspin: fake);
        await expectLater(target.restore(backup),
            throwsA(isA<BackupRejected>()), reason: 'alarms: $alarms');
        expectUntouched(target, fake);
      }
    });

    test('writes the Sendspin keys before the config goes live', () async {
      // The live config rebuild starts Sendspin, which would mint a key of
      // its own if the restored one were not already on disk.
      late final _MemoryConfigNotifier notifier;
      final fake = _OrderCheckingSendspinFiles(() => notifier.current.apiKey);
      notifier = _MemoryConfigNotifier(const HubConfig(apiKey: 'target-key'));
      final target = BackupService(
        config: notifier,
        alarms: AlarmService(directory: () async => dir.path),
        sendspin: fake,
        platform: 'linux',
        installedVersion: () async => '1.22.0',
        directory: () async => dir.path,
      );
      await target.restore(await sourceBackup());
      expect(fake.apiKeyAtWrite, 'target-key');
      expect(notifier.current.apiKey, 'source-key');
    });

    test('a failed Sendspin write changes nothing else', () async {
      final target = BackupService(
        config: _MemoryConfigNotifier(const HubConfig(apiKey: 'target-key')),
        alarms: AlarmService(directory: () async => dir.path),
        sendspin: _FailingSendspinFiles(),
        platform: 'linux',
        installedVersion: () async => '1.22.0',
        directory: () async => dir.path,
      );
      await expectLater(target.restore(await sourceBackup()),
          throwsA(isA<FileSystemException>()));
      expect(target.config.current.apiKey, 'target-key');
      expect(target.alarms.alarms, isEmpty);
    });

    test('a dev build accepts any backup', () async {
      final target = service(version: 'dev');
      await target.restore(await sourceBackup(version: '1.22.0'));
      expect(target.config.current.apiKey, 'source-key');
    });

    test('pre-release suffixes are compared by their numbers', () async {
      await expectLater(
        service(version: '1.22.0')
            .restore(await sourceBackup(version: '1.22.1-rc.1')),
        throwsA(isA<BackupRejected>().having((e) => e.message, 'message',
            contains('Hearth 1.22.1-rc.1'))),
      );
      await service(version: '1.22.1+5')
          .restore(await sourceBackup(version: '1.22.1-rc.1'));
    });

    test('skips Sendspin from another platform', () async {
      final backup = await sourceBackup(platform: 'android');
      final fake = _FakeSendspinFiles();
      final target = service(sendspin: fake, platform: 'linux');
      expect(await target.restore(backup), SendspinRestore.skipped);
      expect(fake.writes, isEmpty);
      expect(target.config.current.apiKey, 'source-key');
    });

    test('no Sendspin files is none', () async {
      final absent = {...await sourceBackup()}..remove('sendspin');
      final fake = _FakeSendspinFiles();
      expect(await service(sendspin: fake).restore(absent),
          SendspinRestore.none);
      final empty = {
        ...await sourceBackup(),
        'sendspin': {'platform': 'linux', 'files': <String, String>{}},
      };
      expect(await service(sendspin: fake).restore(empty),
          SendspinRestore.none);
      expect(fake.writes, isEmpty);
    });

    test('keeps pre-restore copies', () async {
      final config = File('${dir.path}/hub_config.json');
      final alarms = File('${dir.path}/alarms.json');
      await config.writeAsString('{"apiKey":"old"}');
      await alarms.writeAsString('[]');

      await service().restore(await sourceBackup());

      expect(await File('${config.path}.pre-restore').readAsString(),
          '{"apiKey":"old"}');
      expect(await File('${alarms.path}.pre-restore').readAsString(), '[]');
    });
  });

  group('FileSendspinSecretFiles', () {
    test('round-trips bytes and keeps a pre-restore copy', () async {
      final files = FileSendspinSecretFiles(directory: () async => dir.path);
      final identity = File('${dir.path}/sendspin_identity.key');
      await identity.writeAsBytes([9, 9]);

      await files.write({'sendspin_identity.key': base64Encode([1, 2, 3])});

      expect(await identity.readAsBytes(), [1, 2, 3]);
      expect(await File('${identity.path}.pre-restore').readAsBytes(), [9, 9]);
      expect(File('${dir.path}/sendspin_pairing.json').existsSync(), isFalse);
      expect(await files.read(),
          {'sendspin_identity.key': base64Encode([1, 2, 3])});
    });

    test('ignores names it does not own', () async {
      final files = FileSendspinSecretFiles(directory: () async => dir.path);
      await files.write({'../evil': base64Encode([1])});
      expect(dir.listSync(), isEmpty);
    });
  });
}
