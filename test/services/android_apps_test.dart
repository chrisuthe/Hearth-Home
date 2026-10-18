import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/services/android_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hearth/apps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Future<Object?>? Function(MethodCall call)? h) =>
      messenger.setMockMethodCallHandler(channel, h);

  tearDown(() => handle(null));

  test('listApps parses and returns apps', () async {
    handle((call) async {
      expect(call.method, 'listApps');
      return [
        {'packageName': 'com.plexapp.android', 'label': 'Plex'},
        {'packageName': 'com.netflix', 'label': 'Netflix'},
      ];
    });
    final apps = await AndroidAppsBridge().listApps();
    expect(apps.map((a) => a.packageName), [
      'com.plexapp.android',
      'com.netflix',
    ]);
    expect(apps.first.label, 'Plex');
  });

  test('launch sends package and layout name', () async {
    Object? args;
    handle((call) async {
      expect(call.method, 'launch');
      args = call.arguments;
      return true;
    });
    final ok = await AndroidAppsBridge().launch(
      'com.plexapp.android',
      AndroidAppLayout.split,
    );
    expect(ok, isTrue);
    expect(args, {'packageName': 'com.plexapp.android', 'layout': 'split'});
  });

  test('launch returns false for missing package', () async {
    handle((call) async => false);
    expect(
      await AndroidAppsBridge().launch('com.nope', AndroidAppLayout.fullscreen),
      isFalse,
    );
  });

  test('launch returns false when channel is missing', () async {
    handle(null);
    expect(
      await AndroidAppsBridge().launch('x', AndroidAppLayout.split),
      isFalse,
    );
  });

  test('overlayGranted false on PlatformException', () async {
    handle((call) async => throw PlatformException(code: 'boom'));
    expect(await AndroidAppsBridge().overlayGranted(), isFalse);
  });
}
