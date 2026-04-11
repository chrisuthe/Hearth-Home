import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../utils/logger.dart';

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

  /// Parses a GitHub or Gitea Releases API response.
  ///
  /// Returns null if the release is a prerelease, a draft, or has no
  /// `hearth-bundle-*.tar.gz` asset. Works with both GitHub and Gitea
  /// API formats (Gitea uses the same field names).
  static UpdateInfo? fromRelease(Map<String, dynamic> json) {
    if (json['prerelease'] == true || json['draft'] == true) return null;

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    final assets = json['assets'] as List<dynamic>? ?? [];
    final bundleAsset = assets.cast<Map<String, dynamic>>().where((a) {
      final name = a['name'] as String? ?? '';
      return name.startsWith('hearth-bundle-') && name.endsWith('.tar.gz');
    }).firstOrNull;

    if (bundleAsset == null) return null;

    // GitHub uses 'browser_download_url', Gitea also supports it.
    final downloadUrl = bundleAsset['browser_download_url'] as String?;
    if (downloadUrl == null) return null;

    return UpdateInfo(
      version: version,
      bundleUrl: downloadUrl,
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

/// Checks GitHub or Gitea Releases for the latest Hearth update.
class UpdateService {
  static const _githubUrl =
      'https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest';
  static const _giteaUrl =
      'https://registry.home.chrisuthe.com/api/v1/repos/chris/Hearth/releases?limit=1';

  final String _source;
  final String _giteaToken;
  final Dio _dio;

  UpdateService({Dio? dio, String source = 'github', String giteaToken = ''})
      : _dio = dio ?? Dio(BaseOptions(
          headers: {'User-Agent': 'Hearth-Home-Updater'},
        )),
        _source = source,
        _giteaToken = giteaToken;

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
      return UpdateInfo.fromRelease(data);
    } catch (e) {
      Log.e('Update', 'Check failed ($source): $e');
      return null;
    }
  }

  String get source => _source;
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

final updateAvailableProvider = Provider<bool>((ref) {
  final current = ref.watch(hubConfigProvider).currentVersion;
  final latest = ref.watch(latestUpdateProvider).valueOrNull;
  if (latest == null) return false;
  return latest.isNewerThan(current);
});
