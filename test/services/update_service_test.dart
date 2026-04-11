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
  });
}
