import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed Hearth version, or '' when it cannot be read.
///
/// The Pi reads `/etc/hearth-version`, which the installer and
/// `hearth-updater.sh` maintain. Android has no such file: the APK carries
/// its version as `versionName`, which `scripts/build-android-apk.sh` sets
/// from the release tag.
Future<String> readInstalledVersion({
  bool? android,
  Future<String> Function()? packageVersion,
  String versionFile = '/etc/hearth-version',
}) async {
  if (kIsWeb) return '';
  if (android ?? Platform.isAndroid) {
    try {
      return await (packageVersion ?? _packageVersion)();
    } catch (_) {
      return '';
    }
  }
  try {
    return File(versionFile).readAsStringSync().trim();
  } catch (_) {
    return '';
  }
}

Future<String> _packageVersion() async =>
    (await PackageInfo.fromPlatform()).version;
