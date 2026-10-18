import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  test('round-trips through json', () {
    const config = HubConfig(
      androidApps: [
        AndroidAppConfig(
            packageName: 'com.google.android.youtube', name: 'YouTube'),
        AndroidAppConfig(packageName: 'com.spotify.music', name: 'Spotify'),
      ],
      androidAppLayout: AndroidAppLayout.fullscreen,
    );
    final back = HubConfig.fromJson(config.toJson());
    expect(back.androidApps, config.androidApps);
    expect(back.androidAppLayout, AndroidAppLayout.fullscreen);
  });

  test('defaults to split and no apps', () {
    final config = HubConfig.fromJson({});
    expect(config.androidApps, isEmpty);
    expect(config.androidAppLayout, AndroidAppLayout.split);
  });

  test('unknown layout falls back to split', () {
    final config = HubConfig.fromJson({'androidAppLayout': 'bogus'});
    expect(config.androidAppLayout, AndroidAppLayout.split);
  });

  test('id is app:<package>', () {
    const app = AndroidAppConfig(
        packageName: 'com.google.android.youtube', name: 'YouTube');
    expect(app.id, 'app:com.google.android.youtube');
  });

  test('entries without packageName are dropped on load', () {
    final config = HubConfig.fromJson({
      'androidApps': [
        {'name': 'No package'},
        {'packageName': '', 'name': 'Empty'},
        {'packageName': 'com.spotify.music', 'name': 'Spotify'},
      ],
    });
    expect(config.androidApps, [
      const AndroidAppConfig(packageName: 'com.spotify.music', name: 'Spotify'),
    ]);
  });
}
