import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../config/hub_config.dart';
import '../utils/logger.dart';
import 'installed_version.dart';
import 'update_service.dart';

/// Where an Android self-update stands.
enum AppUpdatePhase {
  idle,
  checking,
  upToDate,
  needsPermission,
  downloading,
  verifying,
  waitingForConfirmation,
  failed,
}

class AppUpdateState {
  final AppUpdatePhase phase;

  /// The release being installed, once one is known.
  final String? version;

  /// Download progress, 0..1, while [AppUpdatePhase.downloading].
  final double? progress;

  /// One line for the user: what is happening, or why it stopped.
  final String message;

  const AppUpdateState(this.phase, this.message, {this.version, this.progress});

  static const idle = AppUpdateState(AppUpdatePhase.idle, '');

  bool get busy =>
      phase == AppUpdatePhase.checking ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.verifying;

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'message': message,
        if (version != null) 'version': version,
        if (progress != null) 'progress': progress,
      };
}

/// A `PackageInstaller` session result, as `MainActivity` reports it.
class InstallResult {
  /// `PackageInstaller.STATUS_*`.
  final int status;
  final String? message;
  const InstallResult(this.status, this.message);

  static const pendingUserAction = -1;
  static const success = 0;
  static const aborted = 3;
}

/// The native half of the updater (`AppUpdateChannel.kt`).
abstract class AppInstaller {
  /// Whether Hearth may install packages ("Install unknown apps").
  Future<bool> canInstall();

  /// Opens the "Install unknown apps" page for Hearth.
  Future<void> openInstallSettings();

  /// Commits [apkPath] to a `PackageInstaller` session. Completes once the
  /// session is committed; the outcome arrives on [results].
  Future<void> install(String apkPath);

  Stream<InstallResult> get results;
}

class MethodChannelAppInstaller implements AppInstaller {
  static const _channel = MethodChannel('com.hearth/app_update');
  final _results = StreamController<InstallResult>.broadcast();

  MethodChannelAppInstaller() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installStatus') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _results.add(
            InstallResult(args['status'] as int, args['message'] as String?));
      }
    });
  }

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod('openInstallSettings');

  @override
  Future<void> install(String apkPath) =>
      _channel.invokeMethod('install', {'path': apkPath});

  @override
  Stream<InstallResult> get results => _results.stream;
}

/// Downloads the release APK, checks it against the release's `.sha256`,
/// and hands it to Android, which asks the user to confirm the install.
///
/// Android only installs an APK signed with the installed app's key and
/// carrying a higher versionCode, so there is no downgrade or rollback path.
class AppUpdater extends StateNotifier<AppUpdateState> {
  final Future<UpdateInfo?> Function() _checkForUpdate;
  final Future<String> Function() _installedVersion;
  final Map<String, String> Function() _downloadHeaders;
  final Future<Directory> Function() _cacheDir;
  final AppInstaller _installer;
  final Dio _dio;
  StreamSubscription<InstallResult>? _resultSub;
  Timer? _autoTimer;

  /// Versions auto-update has already fetched or offered in this process,
  /// so a declined prompt does not come back every day.
  final Set<String> _autoAttempted = {};

  AppUpdater({
    required Future<UpdateInfo?> Function() checkForUpdate,
    required AppInstaller installer,
    Future<String> Function()? installedVersion,
    Map<String, String> Function()? downloadHeaders,
    Future<Directory> Function()? cacheDir,
    Dio? dio,
  })  : _checkForUpdate = checkForUpdate,
        _installer = installer,
        _installedVersion =
            installedVersion ?? (() => readInstalledVersion(android: true)),
        _downloadHeaders = downloadHeaders ?? (() => const {}),
        _cacheDir = cacheDir ?? getTemporaryDirectory,
        _dio = dio ??
            Dio(BaseOptions(headers: {'User-Agent': 'Hearth-Home-Updater'})),
        super(AppUpdateState.idle) {
    _resultSub = _installer.results.listen(_onInstallResult);
  }

  AppUpdateState get current => state;

  /// Checks for a newer release and, when there is one, takes it as far as
  /// the system install prompt. Returns the state it stopped in.
  ///
  /// [auto] runs unattended: it skips a version it already offered and does
  /// not open the settings page.
  Future<AppUpdateState> apply({bool auto = false}) async {
    if (state.busy) return state;
    final before = state;
    _set(const AppUpdateState(AppUpdatePhase.checking, 'Checking for updates'));

    final UpdateInfo? latest;
    final String current;
    try {
      latest = await _checkForUpdate();
      current = await _installedVersion();
    } catch (e) {
      return _fail('Update check failed: $e');
    }
    if (latest == null || (!latest.dev && !latest.isNewerThan(current))) {
      return _set(AppUpdateState(AppUpdatePhase.upToDate,
          current.isEmpty ? 'Up to date' : 'Up to date (v$current)'));
    }
    final version = latest.version;
    if (auto && _autoAttempted.contains(version)) return _set(before);

    if (!await _installer.canInstall()) {
      if (!auto) await _installer.openInstallSettings();
      return _set(AppUpdateState(
          AppUpdatePhase.needsPermission,
          'Allow Hearth to install unknown apps in Android settings, '
          'then update again',
          version: version));
    }

    final checksumUrl = latest.checksumUrl;
    if (checksumUrl == null) {
      return _fail('v$version has no .sha256 checksum; not installing',
          version: version);
    }
    if (auto) _autoAttempted.add(version);

    final File apk;
    try {
      final dir = Directory('${(await _cacheDir()).path}/updates');
      await dir.create(recursive: true);
      apk = File('${dir.path}/${Uri.parse(latest.bundleUrl).pathSegments.last}');
      await for (final old in dir.list()) {
        if (old.path != apk.path) await old.delete(recursive: true);
      }

      final expected = await _fetchChecksum(checksumUrl);
      if (expected == null) {
        return _fail('The checksum file for v$version is unreadable; '
            'not installing', version: version);
      }

      // A file already fetched and intact is reused rather than downloaded
      // again — the prompt may have been dismissed, not the update refused.
      if (!await apk.exists() || await _sha256(apk) != expected) {
        _set(AppUpdateState(AppUpdatePhase.downloading, 'Downloading v$version',
            version: version, progress: 0));
        await _dio.download(
          latest.bundleUrl,
          apk.path,
          options: Options(headers: _downloadHeaders()),
          onReceiveProgress: (got, total) {
            if (total <= 0) return;
            _set(AppUpdateState(AppUpdatePhase.downloading,
                'Downloading v$version (${(got * 100 / total).floor()}%)',
                version: version, progress: got / total));
          },
        );
        _set(AppUpdateState(AppUpdatePhase.verifying, 'Verifying v$version',
            version: version));
        if (await _sha256(apk) != expected) {
          await apk.delete();
          return _fail('Checksum mismatch for v$version; not installing',
              version: version);
        }
      }
    } catch (e) {
      return _fail('Download of v$version failed: $e', version: version);
    }

    try {
      await _installer.install(apk.path);
    } catch (e) {
      return _fail('Could not start the install: $e', version: version);
    }
    // The prompt may already have come and gone while install() ran.
    if (state.phase == AppUpdatePhase.verifying ||
        state.phase == AppUpdatePhase.checking) {
      _set(AppUpdateState(AppUpdatePhase.waitingForConfirmation,
          'Confirm the update to v$version on the tablet',
          version: version));
    }
    return state;
  }

  /// Runs [apply] two minutes after start and daily after that, while
  /// [enabled] holds — the cadence of the Pi's `hearth-updater.timer`.
  void scheduleAutoUpdate(bool Function() enabled) {
    _autoTimer?.cancel();
    Future<void> tick() async {
      if (!enabled()) return;
      final s = await apply(auto: true);
      Log.i('Update', 'Auto-update: ${s.phase.name} ${s.message}');
    }

    _autoTimer = Timer(const Duration(minutes: 2), () {
      tick();
      _autoTimer = Timer.periodic(const Duration(days: 1), (_) => tick());
    });
  }

  void _onInstallResult(InstallResult r) {
    final version = state.version;
    final v = version == null ? 'the update' : 'v$version';
    switch (r.status) {
      case InstallResult.pendingUserAction:
        _set(AppUpdateState(AppUpdatePhase.waitingForConfirmation,
            'Confirm the update to $v on the tablet',
            version: version));
      case InstallResult.success:
        _set(AppUpdateState(AppUpdatePhase.idle, 'Installed $v',
            version: version));
      case InstallResult.aborted:
        _fail('Install of $v was cancelled', version: version);
      default:
        _fail('Android refused $v: ${describeInstallFailure(r.message)}',
            version: version);
    }
  }

  Future<String?> _fetchChecksum(String url) async {
    final res = await _dio.get<String>(url,
        options: Options(
            headers: _downloadHeaders(), responseType: ResponseType.plain));
    return parseSha256(res.data ?? '');
  }

  static Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  AppUpdateState _fail(String message, {String? version}) {
    Log.e('Update', message);
    return _set(AppUpdateState(AppUpdatePhase.failed, message, version: version));
  }

  AppUpdateState _set(AppUpdateState s) {
    if (mounted) state = s;
    return s;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resultSub?.cancel();
    super.dispose();
  }
}

/// The hash from a `sha256sum` line (`<hex>  <file>`), or null.
String? parseSha256(String text) {
  final hex = text.trim().split(RegExp(r'\s+')).first.toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
}

/// Adds the likely cause to the `INSTALL_FAILED_*` text Android reports.
String describeInstallFailure(String? message) {
  final m = message ?? 'no reason given';
  if (m.contains('UPDATE_INCOMPATIBLE') || m.contains('signatures')) {
    return '$m — the APK is signed with a different key than the installed '
        'app. Debug-signed builds cannot update each other; use '
        'release-signed APKs.';
  }
  if (m.contains('VERSION_DOWNGRADE')) {
    return '$m — the APK is older than the installed app.';
  }
  return m;
}

final appUpdaterProvider =
    StateNotifierProvider<AppUpdater, AppUpdateState>((ref) {
  // As on the Pi, a dev URL replaces the release lookup and carries no auth.
  String? devApk() {
    final c = ref.read(hubConfigProvider);
    return c.devBundleEnabled && c.devBundleUrl.endsWith('.apk')
        ? c.devBundleUrl
        : null;
  }

  final updater = AppUpdater(
    checkForUpdate: () async {
      final dev = devApk();
      if (dev != null) return UpdateInfo.devApk(dev);
      return ref.read(updateServiceProvider).checkForUpdate();
    },
    downloadHeaders: () => devApk() != null
        ? const {}
        : ref.read(updateServiceProvider).downloadHeaders,
    installer: MethodChannelAppInstaller(),
  );
  updater.scheduleAutoUpdate(() => ref.read(hubConfigProvider).autoUpdate);
  return updater;
});
