import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/installed_version.dart';

void main() {
  late Directory dir;
  late String versionFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hearth_version_');
    versionFile = '${dir.path}/hearth-version';
    File(versionFile).writeAsStringSync('1.21.0\n');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('the Pi reads the version file', () async {
    final v = await readInstalledVersion(
      android: false,
      packageVersion: () async => '9.9.9',
      versionFile: versionFile,
    );
    expect(v, '1.21.0');
  });

  test('Android reads the package version, not the file', () async {
    final v = await readInstalledVersion(
      android: true,
      packageVersion: () async => '1.22.0',
      versionFile: versionFile,
    );
    expect(v, '1.22.0');
  });

  test('a missing version reads as empty', () async {
    expect(
        await readInstalledVersion(
            android: false, versionFile: '${dir.path}/absent'),
        '');
    expect(
        await readInstalledVersion(
            android: true, packageVersion: () async => throw StateError('x')),
        '');
  });
}
