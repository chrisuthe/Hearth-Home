import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../utils/logger.dart';

/// Describes a Hearth release available on GitHub.
class UpdateInfo {
  final String version;

  /// The asset this platform installs: the `hearth-bundle-*.tar.gz` on the
  /// Pi, the `hearth-android-*.apk` on Android.
  final String bundleUrl;

  /// The asset's sibling `.sha256`, or null when the release has none.
  final String? checksumUrl;
  final String tagName;

  /// A developer override (`devBundleUrl`), installed without a version gate.
  final bool dev;

  const UpdateInfo({
    required this.version,
    required this.bundleUrl,
    required this.tagName,
    this.checksumUrl,
    this.dev = false,
  });

  /// The Android counterpart of the Pi's dev bundle: an APK at [url], with
  /// its checksum expected beside it, as a release would carry it.
  factory UpdateInfo.devApk(String url) => UpdateInfo(
        version: 'dev',
        bundleUrl: url,
        checksumUrl: '${url.substring(0, url.length - '.apk'.length)}.sha256',
        tagName: '',
        dev: true,
      );

  /// Parses a GitHub or Gitea Releases API response.
  ///
  /// Returns null if the release is a prerelease, a draft, or has no asset
  /// for this platform: `hearth-android-*.apk` when [android], else
  /// `hearth-bundle-*.tar.gz`. Works with both GitHub and Gitea API formats
  /// (Gitea uses the same field names).
  static UpdateInfo? fromRelease(Map<String, dynamic> json,
      {bool android = false}) {
    if (json['prerelease'] == true || json['draft'] == true) return null;

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    final prefix = android ? 'hearth-android-' : 'hearth-bundle-';
    final suffix = android ? '.apk' : '.tar.gz';
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final bundleAsset = assets.where((a) {
      final name = a['name'] as String? ?? '';
      return name.startsWith(prefix) && name.endsWith(suffix);
    }).firstOrNull;

    if (bundleAsset == null) return null;

    // GitHub uses 'browser_download_url', Gitea also supports it.
    final downloadUrl = bundleAsset['browser_download_url'] as String?;
    if (downloadUrl == null) return null;

    final bundleName = bundleAsset['name'] as String;
    final checksumName =
        '${bundleName.substring(0, bundleName.length - suffix.length)}.sha256';
    final checksumAsset =
        assets.where((a) => a['name'] == checksumName).firstOrNull;

    return UpdateInfo(
      version: version,
      bundleUrl: downloadUrl,
      checksumUrl: checksumAsset?['browser_download_url'] as String?,
      tagName: tagName,
    );
  }

  /// Returns true if this version is newer than [other] (semver comparison).
  ///
  /// Returns true when [other] is empty.
  bool isNewerThan(String other) {
    if (other.isEmpty) return true;
    return semverIsNewer(version, other);
  }
}

/// True if [version] is newer than [other], comparing major.minor.patch.
/// A missing or non-numeric part counts as 0.
bool semverIsNewer(String version, String other) {
  final thisParts = _parseSemver(version);
  final otherParts = _parseSemver(other);

  for (var i = 0; i < 3; i++) {
    if (thisParts[i] > otherParts[i]) return true;
    if (thisParts[i] < otherParts[i]) return false;
  }
  return false; // equal
}

List<int> _parseSemver(String v) {
  final parts = v.split('.');
  return List.generate(3, (i) {
    if (i >= parts.length) return 0;
    return int.tryParse(parts[i]) ?? 0;
  });
}

/// Checks GitHub or Gitea Releases for the latest Hearth update.
class UpdateService {
  static const _githubUrl =
      'https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest';
  static const _giteaUrl =
      'https://registry.home.chrisuthe.com/api/v1/repos/chris/Hearth/releases?limit=1';

  final String _source;
  final String _giteaToken;
  final bool _android;
  final Dio _dio;

  UpdateService({
    Dio? dio,
    String source = 'github',
    String giteaToken = '',
    bool? android,
  })  : _dio = dio ?? Dio(BaseOptions(
          headers: {'User-Agent': 'Hearth-Home-Updater'},
        )),
        _source = source,
        _giteaToken = giteaToken,
        _android = android ?? (!kIsWeb && Platform.isAndroid);

  /// Fetches the latest release and returns an [UpdateInfo] if available,
  /// or null on error or if the release doesn't meet criteria.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = _source == 'gitea' ? _giteaUrl : _githubUrl;
      final options = _source == 'gitea' && _giteaToken.isNotEmpty
          ? Options(headers: {'Authorization': 'token $_giteaToken'})
          : null;
      final response = await _dio.get<dynamic>(url, options: options);

      // GitHub returns a single object; Gitea returns an array.
      final Map<String, dynamic>? data;
      if (response.data is List) {
        final list = response.data as List<dynamic>;
        data = list.isNotEmpty ? list.first as Map<String, dynamic> : null;
      } else {
        data = response.data as Map<String, dynamic>?;
      }
      if (data == null) return null;
      return UpdateInfo.fromRelease(data, android: _android);
    } catch (e) {
      Log.e('Update', 'Check failed ($source): $e');
      return null;
    }
  }

  String get source => _source;

  /// Headers a release asset download needs: the Gitea token, as
  /// `hearth-updater.sh` sends it, when Gitea is the source.
  Map<String, String> get downloadHeaders =>
      _source == 'gitea' && _giteaToken.isNotEmpty
          ? {'Authorization': 'token $_giteaToken'}
          : const {};
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  final config = ref.watch(hubConfigProvider);
  return UpdateService(
    source: config.updateSource,
    giteaToken: config.giteaApiToken,
  );
});

final latestUpdateProvider = FutureProvider<UpdateInfo?>((ref) async {
  final service = ref.read(updateServiceProvider);
  return service.checkForUpdate();
});
