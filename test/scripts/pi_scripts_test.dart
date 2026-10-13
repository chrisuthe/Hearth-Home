@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/display_orientation.dart';

/// Drives the Pi shell scripts with stubbed system commands. They are the only
/// thing standing between a config value and the kiosk booting, so the
/// fallbacks get the same coverage as the Dart side.
void main() {
  late Directory tmp;
  late String stubBin;

  void writeStub(String name, String body) {
    final f = File('$stubBin/$name')..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', f.path]);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hearth_scripts_');
    stubBin = '${tmp.path}/bin';
    Directory(stubBin).createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('hearth-launch.sh', () {
    String launch({String? config, bool configExists = true}) {
      writeStub('flutter-pi', r'echo "$* applied=$HEARTH_APPLIED_ROTATION"');
      final configFile = File('${tmp.path}/hub_config.json');
      if (config != null) configFile.writeAsStringSync(config);
      final result = Process.runSync('sh', [
        'scripts/hearth-launch.sh'
      ], environment: {
        'HEARTH_FLUTTER_PI': '$stubBin/flutter-pi',
        'HEARTH_CONFIG_FILE': configExists ? configFile.path : '',
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    String expected(int degrees) => '--release --rotation $degrees '
        '--mirror-connector HDMI-A-2 /opt/hearth/bundle applied=$degrees';

    test('passes the same rotation DisplayOrientation maps to', () {
      for (final o in DisplayOrientation.values) {
        final out = launch(
            config: '{"uiScale":1.0,"displayOrientation":"${o.wire}","x":"y"}');
        expect(out, expected(o.piRotationDegrees), reason: o.wire);
      }
    });

    test('falls back to 0 for a missing key, garbage value or broken file',
        () {
      expect(launch(config: '{"uiScale":1.0}'), expected(0));
      expect(launch(config: '{"displayOrientation":"sideways"}'), expected(0));
      expect(launch(config: '{"displayOrientation":90}'), expected(0));
      expect(launch(config: 'not json'), expected(0));
      expect(launch(config: ''), expected(0));
    });

    test('falls back to 0 when there is no config file', () {
      expect(launch(), expected(0));
      expect(launch(configExists: false), expected(0));
    });
  });

  group('hearth-updater.sh --migrate-only', () {
    late String root;
    late String bundle;
    late File calls;

    const legacyUnit = '[Service]\n'
        'ExecStart=/usr/local/bin/flutter-pi --release --mirror-connector '
        'HDMI-A-2 /opt/hearth/bundle\n';

    ProcessResult migrate() => Process.runSync('sh', [
          'scripts/hearth-updater.sh',
          '--migrate-only'
        ], environment: {
          'PATH': '$stubBin:${Platform.environment['PATH']}',
          'HEARTH_SYSROOT': root,
          'HEARTH_BUNDLE_DIR': bundle,
        });

    /// Every file under the fake root with its content and mode.
    Map<String, String> snapshot() => {
          for (final f in Directory(root)
              .listSync(recursive: true)
              .whereType<File>())
            f.path:
                '${f.statSync().modeString()} ${f.statSync().modified} ${f.readAsStringSync()}',
        };

    setUp(() {
      root = '${tmp.path}/root';
      bundle = '${tmp.path}/bundle';
      calls = File('${tmp.path}/calls');
      Directory('$root/etc/systemd/system').createSync(recursive: true);
      Directory('$root/etc/sudoers.d').createSync(recursive: true);
      Directory(bundle).createSync();
      File('$root/etc/systemd/system/hearth.service')
          .writeAsStringSync(legacyUnit);
      File('scripts/hearth-launch.sh').copySync('$bundle/hearth-launch.sh');
      writeStub('logger', 'exit 0');
      writeStub('systemctl', 'echo "systemctl \$*" >> ${calls.path}');
      writeStub('visudo', 'exit 0');
    });

    test('installs the launcher, drop-in and sudoers rule', () {
      final result = migrate();
      expect(result.exitCode, 0, reason: '${result.stderr}');

      final launcher = File('$root/usr/local/bin/hearth-launch');
      expect(launcher.readAsStringSync(),
          File('scripts/hearth-launch.sh').readAsStringSync());
      expect(launcher.statSync().modeString(), 'rwxr-xr-x');

      expect(
        File('$root/etc/systemd/system/hearth.service.d/10-launcher.conf')
            .readAsStringSync(),
        '[Service]\nExecStart=\nExecStart=/usr/local/bin/hearth-launch\n',
      );
      // The unit itself is left alone — removing the drop-in undoes the move.
      expect(
          File('$root/etc/systemd/system/hearth.service').readAsStringSync(),
          legacyUnit);

      final sudoers = File('$root/etc/sudoers.d/hearth-restart');
      expect(sudoers.readAsStringSync(),
          'hearth ALL=(root) NOPASSWD: /usr/bin/systemctl restart hearth.service\n');
      expect(sudoers.statSync().modeString(), 'r--r-----');
      expect(calls.readAsStringSync(), 'systemctl daemon-reload\n');
    });

    test('a second run changes nothing', () {
      expect(migrate().exitCode, 0);
      final before = snapshot();
      calls.writeAsStringSync('');

      expect(migrate().exitCode, 0);
      expect(snapshot(), before);
      expect(calls.readAsStringSync(), isEmpty);
    });

    test('adds no drop-in when the unit already execs the launcher', () {
      File('$root/etc/systemd/system/hearth.service').writeAsStringSync(
          '[Service]\nExecStart=/usr/local/bin/hearth-launch\n');
      expect(migrate().exitCode, 0);
      expect(Directory('$root/etc/systemd/system/hearth.service.d').existsSync(),
          isFalse);
      expect(calls.existsSync(), isFalse);
    });

    test('leaves the unit alone when the bundle has no launcher', () {
      File('$bundle/hearth-launch.sh').deleteSync();
      expect(migrate().exitCode, isNot(0));
      expect(Directory('$root/etc/systemd/system/hearth.service.d').existsSync(),
          isFalse);
      expect(File('$root/etc/sudoers.d/hearth-restart').existsSync(), isFalse);
    });

    test('does not install a sudoers rule visudo rejects', () {
      writeStub('visudo', 'exit 1');
      expect(migrate().exitCode, isNot(0));
      expect(Directory('$root/etc/sudoers.d').listSync(), isEmpty);
    });
  });
}
