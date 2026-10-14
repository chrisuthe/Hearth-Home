import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/third_party_licenses.dart';
import 'package:hearth/services/third_party_notices.dart';

/// Keeps the notices current: anything bundled, vendored or forked must have
/// an entry in assets/licenses/notices.json. When one of these fails, add or
/// extend an entry there and run `dart run tool/gen_third_party_notices.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final notices = parseNotices(File(noticesManifest).readAsStringSync());
  final covered = [for (final n in notices) ...n.covers];

  bool isCovered(String path) =>
      covered.any((c) => path == c || path.startsWith('$c/'));

  List<String> filesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  List<String> dirsUnder(String dir) => Directory(dir)
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.replaceAll(r'\', '/'))
      .toList();

  group('manifest', () {
    test('ids are unique and fields are well formed', () {
      final ids = notices.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final n in notices) {
        expect(n.platforms, isNotEmpty, reason: n.id);
        expect(n.platforms.every(noticePlatforms.contains), isTrue,
            reason: '${n.id}: ${n.platforms}');
        expect(['verified', 'assumed'], contains(n.status), reason: n.id);
        expect(n.checked, isNotEmpty, reason: n.id);
      }
    });

    test('every licence file exists and none is orphaned', () {
      final referenced = {
        for (final n in notices)
          if (n.licenseFile != null) '$noticesDir/${n.licenseFile}',
      };
      for (final path in referenced) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      final present = filesUnder(noticesDir).toSet()..remove(noticesManifest);
      expect(present.difference(referenced), isEmpty);
    });

    test('THIRD_PARTY_NOTICES.md is generated from the manifest', () {
      expect(File('THIRD_PARTY_NOTICES.md').readAsStringSync(),
          renderNoticesMarkdown(notices),
          reason: 'Run: dart run tool/gen_third_party_notices.dart');
    });
  });

  group('coverage', () {
    test('every bundled asset is credited', () {
      final assets = filesUnder('assets')
          .where((p) => !p.startsWith('$noticesDir/'))
          .toList();
      expect(assets, isNotEmpty);
      expect(assets.where((p) => !isCovered(p)), isEmpty);
    });

    test('every git submodule is credited', () {
      final paths = RegExp(r'^\s*path\s*=\s*(\S+)', multiLine: true)
          .allMatches(File('.gitmodules').readAsStringSync())
          .map((m) => m.group(1)!)
          .toList();
      expect(paths, isNotEmpty);
      expect(paths.where((p) => !isCovered(p)), isEmpty);
    });

    test('every Ava module Hearth builds and every native module is credited',
        () {
      final modules = [...dirsUnder('android/ava'), ...dirsUnder('native')];
      expect(modules, isNotEmpty);
      expect(modules.where((p) => !isCovered(p)), isEmpty);
    });

    test('every fork in the upstream drift check is credited', () {
      final forks = RegExp(r'check_fork "[^"]+" \\\s*"([^"]+)"')
          .allMatches(File('scripts/check-upstream-drift.sh').readAsStringSync())
          .map((m) => m.group(1)!)
          .toList();
      expect(forks, isNotEmpty);
      final credited = {for (final n in notices) ...n.forks};
      expect(forks.where((f) => !credited.contains(f)), isEmpty);
    });

    test('every wake-word model the APK ships is credited', () {
      final models = RegExp(r'"(?:wake|stop)Words/(\w+)\.tflite"')
          .allMatches(File('android/ava/satellite/build.gradle.kts')
              .readAsStringSync())
          .map((m) => m.group(1)!)
          .toList();
      expect(models, isNotEmpty);
      final notice = notices.singleWhere((n) => n.id == 'microwakeword-models');
      expect(models.where((m) => !notice.name.contains(m)), isEmpty);
    });
  });

  group('licence registry', () {
    setUp(LicenseRegistry.reset);
    tearDown(LicenseRegistry.reset);

    Future<Map<String, String>> registered(Set<String> platforms) async {
      registerThirdPartyLicenses(platforms: platforms);
      return {
        await for (final e in LicenseRegistry.licenses)
          e.packages.single: e.paragraphs.map((p) => p.text).join('\n'),
      };
    }

    test('registers the notices for this platform with their texts', () async {
      final android = await registered({'android'});
      expect(android.keys, contains('Ava (Android voice satellite)'));
      expect(android['Ava (Android voice satellite)'],
          contains('Apache License'));
      expect(android.keys, isNot(contains('flutter-pi')));

      LicenseRegistry.reset();
      final pi = await registered({'pi'});
      expect(pi.keys, contains('flutter-pi'));
      expect(pi.keys, contains('Inter font'));
      expect(pi.keys, isNot(contains('Ava (Android voice satellite)')));
      // Listed in the manifest but left to Flutter's package licences.
      expect(pi.keys, isNot(contains('flutterpi_gstreamer_video_player')));
    });

    test('portal page lists every package and escapes the text', () async {
      final html = await renderLicensesHtml(Stream.fromIterable([
        const LicenseEntryWithLineBreaks(['b_pkg'], 'Copyright <b>'),
        const LicenseEntryWithLineBreaks(['a_pkg'], 'MIT'),
      ]));
      expect(html.indexOf('>a_pkg<'), lessThan(html.indexOf('>b_pkg<')));
      expect(html, contains('Copyright &lt;b&gt;'));
    });
  });
}
