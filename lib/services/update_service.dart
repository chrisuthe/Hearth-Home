import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';

/// Describes a Hearth release available on GitHub.
class UpdateInfo {
  final String version;
  final String bundleUrl;
  final String tagName;

  const UpdateInfo({
    required this.version,
    required this.bundleUrl,
    required this.tagName,
  });

  /// Parses a GitHub Releases API response.
  ///
  /// Returns null if the release is a prerelease, a draft, or has no
  /// `hearth-bundle-*.tar.gz` asset.
  static UpdateInfo? fromGitHubRelease(Map<String, dynamic> json) {
    if (json['prerelease'] == true || json['draft'] == true) return null;

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    final assets = json['assets'] as List<dynamic>? ?? [];
    final bundleAsset = assets.cast<Map<String, dynamic>>().where((a) {
      final name = a['name'] as String? ?? '';
      return name.startsWith('hearth-bundle-') && name.endsWith('.tar.gz');
    }).firstOrNull;

    if (bundleAsset == null) return null;

    return UpdateInfo(
      version: version,
      bundleUrl: bundleAsset['browser_download_url'] as String,
      tagName: tagName,
    );
  }

  /// Returns true if this version is newer than [other] (semver comparison).
  ///
  /// Returns true when [other] is empty.
  bool isNewerThan(String other) {
    if (other.isEmpty) return true;

    final thisParts = _parseSemver(version);
    final otherParts = _parseSemver(other);

    for (var i = 0; i < 3; i++) {
      if (thisParts[i] > otherParts[i]) return true;
      if (thisParts[i] < otherParts[i]) return false;
    }
    return false; // equal
  }

  static List<int> _parseSemver(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    });
  }
}

/// Checks GitHub Releases for the latest Hearth update.
class UpdateService {
  static const _releaseUrl =
      'https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest';

  final Dio _dio;

  UpdateService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    headers: {'User-Agent': 'Hearth-Home-Updater'},
  ));

  /// Fetches the latest release and returns an [UpdateInfo] if available,
  /// or null on error or if the release doesn't meet criteria.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(_releaseUrl);
      final data = response.data;
      if (data == null) return null;
      return UpdateInfo.fromGitHubRelease(data);
    } catch (e) {
      debugPrint('UpdateService: failed to check for update: $e');
      return null;
    }
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final latestUpdateProvider = FutureProvider<UpdateInfo?>((ref) async {
  final service = ref.read(updateServiceProvider);
  return service.checkForUpdate();
});

final updateAvailableProvider = Provider<bool>((ref) {
  final current = ref.watch(hubConfigProvider).currentVersion;
  final latest = ref.watch(latestUpdateProvider).valueOrNull;
  if (latest == null) return false;
  return latest.isNewerThan(current);
});
