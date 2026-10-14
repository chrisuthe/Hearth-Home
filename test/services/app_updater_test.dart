import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/app_updater.dart';
import 'package:hearth/services/update_service.dart';

const _apkUrl = 'https://example.com/hearth-android-1.22.0.apk';
const _sumUrl = 'https://example.com/hearth-android-1.22.0.sha256';
final _apk = utf8.encode('pretend this is an APK');
final _apkSum = sha256.convert(_apk).toString();

void main() {
  late Directory cache;
  late _FakeInstaller installer;
  late _FakeAdapter http;
  UpdateInfo? latest;

  AppUpdater updater({String installed = '1.21.0'}) => AppUpdater(
        checkForUpdate: () async => latest,
        installedVersion: () async => installed,
        installer: installer,
        cacheDir: () async => cache,
        dio: Dio()..httpClientAdapter = http,
      );

  setUp(() {
    cache = Directory.systemTemp.createTempSync('hearth_update_');
    installer = _FakeInstaller();
    http = _FakeAdapter({
      _apkUrl: _apk,
      _sumUrl: utf8.encode('$_apkSum  hearth-android-1.22.0.apk\n'),
    });
    latest = const UpdateInfo(
      version: '1.22.0',
      bundleUrl: _apkUrl,
      checksumUrl: _sumUrl,
      tagName: 'v1.22.0',
    );
  });

  tearDown(() => cache.deleteSync(recursive: true));

  test('a matching checksum hands the APK to the installer', () async {
    final s = await updater().apply();
    expect(s.phase, AppUpdatePhase.waitingForConfirmation);
    expect(installer.installed, hasLength(1));
    expect(File(installer.installed.single).readAsBytesSync(), _apk);
  });

  test('a checksum mismatch stops before the prompt', () async {
    http.files[_sumUrl] = utf8.encode('${'0' * 64}  x.apk\n');
    final s = await updater().apply();
    expect(s.phase, AppUpdatePhase.failed);
    expect(s.message, contains('Checksum mismatch'));
    expect(installer.installed, isEmpty);
    expect(Directory('${cache.path}/updates').listSync(), isEmpty);
  });

  test('a release without a checksum stops before downloading', () async {
    latest = const UpdateInfo(
        version: '1.22.0', bundleUrl: _apkUrl, tagName: 'v1.22.0');
    final s = await updater().apply();
    expect(s.phase, AppUpdatePhase.failed);
    expect(s.message, contains('no .sha256'));
    expect(http.requests, isEmpty);
    expect(installer.installed, isEmpty);
  });

  test('without install permission it opens the setting', () async {
    installer.allowed = false;
    final s = await updater().apply();
    expect(s.phase, AppUpdatePhase.needsPermission);
    expect(installer.settingsOpened, 1);
    expect(http.requests, isEmpty);
  });

  test('no newer release reads as up to date', () async {
    expect((await updater(installed: '1.22.0').apply()).phase,
        AppUpdatePhase.upToDate);
    latest = null;
    expect((await updater().apply()).phase, AppUpdatePhase.upToDate);
    expect(installer.installed, isEmpty);
  });

  test('a dev APK installs without a version gate', () async {
    latest = UpdateInfo.devApk(_apkUrl);
    expect(latest!.checksumUrl, _sumUrl);
    final s = await updater(installed: '9.0.0').apply();
    expect(s.phase, AppUpdatePhase.waitingForConfirmation);
  });

  test('a verified download is reused rather than fetched again', () async {
    final u = updater();
    await u.apply();
    installer.resultController.add(const InstallResult(InstallResult.aborted, null));
    await pumpEventQueue();
    expect(u.current.phase, AppUpdatePhase.failed);
    expect(u.current.message, contains('cancelled'));

    await u.apply();
    expect(http.requests.where((r) => r == _apkUrl), hasLength(1));
    expect(installer.installed, hasLength(2));
  });

  test('auto-update offers a version once per process', () async {
    final u = updater();
    await u.apply(auto: true);
    await u.apply(auto: true);
    expect(installer.installed, hasLength(1));
  });

  test('auto-update does not open the settings page', () async {
    installer.allowed = false;
    final s = await updater().apply(auto: true);
    expect(s.phase, AppUpdatePhase.needsPermission);
    expect(installer.settingsOpened, 0);
  });

  test('a signature rejection names the key', () async {
    final u = updater();
    await u.apply();
    installer.resultController.add(const InstallResult(
        5, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match'));
    await pumpEventQueue();
    expect(u.current.phase, AppUpdatePhase.failed);
    expect(u.current.message, contains('different key'));
  });

  test('parseSha256 reads sha256sum output', () {
    expect(parseSha256('$_apkSum  hearth-android-1.22.0.apk\n'), _apkSum);
    expect(parseSha256(_apkSum.toUpperCase()), _apkSum);
    expect(parseSha256('not a hash'), isNull);
    expect(parseSha256(''), isNull);
  });
}

class _FakeInstaller implements AppInstaller {
  bool allowed = true;
  int settingsOpened = 0;
  final installed = <String>[];
  final resultController = StreamController<InstallResult>.broadcast();

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<void> install(String apkPath) async => installed.add(apkPath);

  @override
  Stream<InstallResult> get results => resultController.stream;
}

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, List<int>> files;
  final requests = <String>[];
  _FakeAdapter(this.files);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final url = options.uri.toString();
    requests.add(url);
    final bytes = files[url];
    if (bytes == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(bytes, 200, headers: {
      Headers.contentLengthHeader: ['${bytes.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}
