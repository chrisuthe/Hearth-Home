import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/hub_config.dart';
import '../../modules/alarm_clock/alarm_models.dart';
import '../../modules/alarm_clock/alarm_service.dart';
import '../installed_version.dart';
import '../sendspin/android_sendspin_service.dart' show sendspinNative;
import '../update_service.dart';
import 'sendspin_secret_files.dart';

/// A backup the kiosk will not restore. [message] is shown in the portal.
class BackupRejected implements Exception {
  final String message;
  const BackupRejected(this.message);

  @override
  String toString() => 'BackupRejected: $message';
}

/// What a restore did with the backup's Sendspin secrets.
enum SendspinRestore {
  /// Written back: Music Assistant sees the same player.
  restored,

  /// The backup came from another platform, whose files this one can't read.
  skipped,

  /// The backup carried none.
  none,
}

/// Builds and restores a whole-kiosk backup: `hub_config.json` (unredacted,
/// identity fields included), the alarms, and the Sendspin secrets.
///
/// A restore is meant for the same kiosk after a rebuild, so nothing is
/// stripped. Every check runs before anything is written; the caller
/// restarts the kiosk afterwards so the settings read only at startup apply.
/// Design: `docs/specs/2026-10-16-backup-restore-design.md`.
class BackupService {
  static const formatVersion = 1;
  static const _invalid = 'This file is not a valid Hearth backup.';

  final HubConfigNotifier config;
  final AlarmService alarms;
  final SendspinSecretFiles sendspin;

  /// `Platform.operatingSystem` of this kiosk.
  final String platform;

  final Future<String> Function() _installedVersion;
  final Future<String> Function() _directory;
  final DateTime Function() _now;

  BackupService({
    required this.config,
    required this.alarms,
    required this.sendspin,
    required this.platform,
    required Future<String> Function() installedVersion,
    Future<String> Function()? directory,
    DateTime Function()? now,
  })  : _installedVersion = installedVersion,
        _directory = directory ?? _supportDirectory,
        _now = now ?? DateTime.now;

  static Future<String> _supportDirectory() async =>
      (await getApplicationSupportDirectory()).path;

  Future<Map<String, dynamic>> create() async => {
        'hearthBackup': formatVersion,
        'createdAt': _now().toUtc().toIso8601String(),
        'hearthVersion': await _installedVersion(),
        'platform': platform,
        'config': config.current.toJson(),
        'alarms': [for (final a in alarms.alarms) a.toJson()],
        'sendspin': {'platform': platform, 'files': await sendspin.read()},
      };

  /// `hearth-backup-<device>-<yyyy-mm-dd>.json`, the device being the MQTT
  /// device name made filename-safe.
  String fileName() {
    final device = config.current.mqttDeviceName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final date = _now().toIso8601String().substring(0, 10);
    return 'hearth-backup-${device.isEmpty ? 'hearth' : device}-$date.json';
  }

  /// Validates [backup] and, only if all of it is good, writes it back.
  /// Throws [BackupRejected] without writing anything otherwise.
  Future<SendspinRestore> restore(Map<String, dynamic> backup) async {
    final format = backup['hearthBackup'];
    if (format is! int) throw const BackupRejected(_invalid);
    if (format > formatVersion) {
      throw const BackupRejected('This backup needs a newer version of Hearth.');
    }

    // A newer build's settings would be dropped by fromJson and then lost
    // for good on the next save, so it is refused rather than half-restored.
    final from = backup['hearthVersion'] is String
        ? backup['hearthVersion'] as String
        : '';
    final fromNumbers = _versionNumbers(from);
    final runningNumbers = _versionNumbers(await _installedVersion());
    if (fromNumbers != null &&
        runningNumbers != null &&
        semverIsNewer(fromNumbers, runningNumbers)) {
      throw BackupRejected('This backup is from Hearth $from; update this '
          'kiosk to $from or later first.');
    }

    final HubConfig restored;
    final List<Alarm> restoredAlarms;
    try {
      restored = HubConfig.fromJson(backup['config'] as Map<String, dynamic>);
      restoredAlarms = [
        for (final a in (backup['alarms'] as List<dynamic>? ?? const []))
          Alarm.fromJson(a as Map<String, dynamic>),
      ];
      // fromJson casts lists lazily; encoding forces every element now.
      jsonEncode(restored.toJson());
      jsonEncode([for (final a in restoredAlarms) a.toJson()]);
    } on TypeError {
      throw const BackupRejected(_invalid);
    } on FormatException {
      throw const BackupRejected(_invalid);
    }
    final secrets = _sendspinFiles(backup['sendspin']);

    final dir = await _directory();
    for (final name in ['hub_config.json', 'alarms.json']) {
      final file = File('$dir/$name');
      if (await file.exists()) await file.copy('${file.path}.pre-restore');
    }

    // The Sendspin keys go first: the config going live can start Sendspin,
    // which would mint a key of its own if the restored one were not on
    // disk yet. It is also the write most likely to fail, and failing first
    // leaves the config and alarms as they were.
    final SendspinRestore result;
    if (secrets == null || secrets.files.isEmpty) {
      result = SendspinRestore.none;
    } else if (secrets.platform != platform) {
      result = SendspinRestore.skipped;
    } else {
      await sendspin.write(secrets.files);
      result = SendspinRestore.restored;
    }
    await alarms.replaceAll(restoredAlarms);
    await config.update((_) => restored);
    return result;
  }

  /// [version] without a pre-release or build suffix, or null when it does
  /// not start with a number — a dev bundle reports `dev`, which cannot be
  /// compared, so the check is skipped as for an unreadable version.
  static String? _versionNumbers(String version) {
    final numbers = version.split(RegExp('[-+]')).first;
    return int.tryParse(numbers.split('.').first) == null ? null : numbers;
  }

  static ({String platform, Map<String, String> files})? _sendspinFiles(
      Object? section) {
    if (section == null) return null;
    try {
      final map = section as Map<String, dynamic>;
      final files = (map['files'] as Map<String, dynamic>? ?? const {})
          .map((name, data) => MapEntry(name, data as String));
      // Decoded here so a corrupt file is refused before anything is written.
      files.values.forEach(base64Decode);
      return (platform: map['platform'] as String? ?? '', files: files);
    } on TypeError {
      throw const BackupRejected(_invalid);
    } on FormatException {
      throw const BackupRejected(_invalid);
    }
  }
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      config: ref.read(hubConfigProvider.notifier),
      alarms: ref.read(alarmServiceProvider),
      sendspin: sendspinNative
          ? AndroidSendspinSecretFiles()
          : FileSendspinSecretFiles(),
      platform: Platform.operatingSystem,
      installedVersion: readInstalledVersion,
    ));
