import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('parseLatestRelease extracts version and asset URL', () {
      final json = {
        'tag_name': 'v1.2.0',
        'prerelease': false,
        'draft': false,
        'assets': [
          {
            'name': 'hearth-bundle-1.2.0.tar.gz',
            'browser_download_url':
                'https://github.com/chrisuthe/Hearth-Home/releases/download/v1.2.0/hearth-bundle-1.2.0.tar.gz',
          },
          {
            'name': 'hearth-1.2.0-pi5.img.xz',
            'browser_download_url':
                'https://github.com/chrisuthe/Hearth-Home/releases/download/v1.2.0/hearth-1.2.0-pi5.img.xz',
          },
        ],
      };
      final release = UpdateInfo.fromRelease(json);
      expect(release, isNotNull);
      expect(release!.version, '1.2.0');
      expect(release.bundleUrl, contains('hearth-bundle-1.2.0.tar.gz'));
    });

    test('parseLatestRelease returns null for prerelease', () {
      final json = {
        'tag_name': 'v2.0.0-beta',
        'prerelease': true,
        'draft': false,
        'assets': [],
      };
      expect(UpdateInfo.fromRelease(json), isNull);
    });

    test('parseLatestRelease returns null for draft', () {
      final json = {
        'tag_name': 'v2.0.0',
        'prerelease': false,
        'draft': true,
        'assets': [],
      };
      expect(UpdateInfo.fromRelease(json), isNull);
    });

    test('parseLatestRelease returns null when no bundle asset exists', () {
      final json = {
        'tag_name': 'v1.0.0',
        'prerelease': false,
        'draft': false,
        'assets': [
          {
            'name': 'hearth-1.0.0-pi5.img.xz',
            'browser_download_url': 'https://example.com/image.xz',
          },
        ],
      };
      expect(UpdateInfo.fromRelease(json), isNull);
    });

    test('isNewerThan compares semver correctly', () {
      final release = UpdateInfo(
        version: '1.2.0',
        bundleUrl: 'https://example.com/bundle.tar.gz',
        tagName: 'v1.2.0',
      );
      expect(release.isNewerThan('1.1.0'), true);
      expect(release.isNewerThan('1.2.0'), false);
      expect(release.isNewerThan('1.3.0'), false);
      expect(release.isNewerThan('0.9.0'), true);
      expect(release.isNewerThan(''), true);
    });

    group('asset selection per platform', () {
      const base = 'https://example.com/v1.22.0';
      Map<String, dynamic> release(List<String> names) => {
            'tag_name': 'v1.22.0',
            'prerelease': false,
            'draft': false,
            'assets': [
              for (final n in names)
                {'name': n, 'browser_download_url': '$base/$n'},
            ],
          };
      final both = release([
        'hearth-bundle-1.22.0.tar.gz',
        'hearth-bundle-1.22.0.sha256',
        'hearth-android-1.22.0.apk',
        'hearth-android-1.22.0.sha256',
      ]);

      test('Android takes the APK and its .sha256', () {
        final info = UpdateInfo.fromRelease(both, android: true)!;
        expect(info.bundleUrl, '$base/hearth-android-1.22.0.apk');
        expect(info.checksumUrl, '$base/hearth-android-1.22.0.sha256');
      });

      test('the Pi takes the bundle and its .sha256', () {
        final info = UpdateInfo.fromRelease(both)!;
        expect(info.bundleUrl, '$base/hearth-bundle-1.22.0.tar.gz');
        expect(info.checksumUrl, '$base/hearth-bundle-1.22.0.sha256');
      });

      test('a release without an APK is no update on Android', () {
        final pi = release(['hearth-bundle-1.22.0.tar.gz']);
        expect(UpdateInfo.fromRelease(pi, android: true), isNull);
      });

      test('a release without a bundle is no update on the Pi', () {
        final apk = release(['hearth-android-1.22.0.apk']);
        expect(UpdateInfo.fromRelease(apk), isNull);
      });

      test('an APK without a checksum has a null checksumUrl', () {
        final apk = release(['hearth-android-1.22.0.apk']);
        expect(UpdateInfo.fromRelease(apk, android: true)!.checksumUrl, isNull);
      });
    });
  });
}
