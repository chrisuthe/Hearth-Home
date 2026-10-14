import 'dart:convert';

/// Pure Dart (no Flutter imports) so `tool/gen_third_party_notices.dart` can
/// run under plain `dart run`.

/// Where the manifest and licence texts live, as a repo path and as an asset
/// key alike.
const noticesDir = 'assets/licenses';
const noticesManifest = '$noticesDir/notices.json';

/// Build targets a notice can apply to. `pi` is the flutter-pi bundle;
/// `linux` is the Linux desktop build.
const noticePlatforms = ['android', 'pi', 'linux', 'windows'];

/// One credited piece of third-party code or content that Flutter's package
/// licences do not already cover. Source of truth: [noticesManifest].
class ThirdPartyNotice {
  final String id;
  final String name;
  final String license;

  /// File under [noticesDir] with the licence text. Null when Flutter's
  /// package licences already carry it, so it is listed but not registered.
  final String? licenseFile;
  final List<String> attribution;
  final List<String> platforms;
  final String source;

  /// Fork repositories Hearth builds instead of [source].
  final List<String> forks;

  /// Repo paths this notice credits; the notices test checks that every
  /// bundled asset, submodule and native module falls under one.
  final List<String> covers;

  /// `verified` or `assumed`.
  final String status;
  final String checked;

  const ThirdPartyNotice({
    required this.id,
    required this.name,
    required this.license,
    required this.licenseFile,
    required this.attribution,
    required this.platforms,
    required this.source,
    required this.forks,
    required this.covers,
    required this.status,
    required this.checked,
  });

  factory ThirdPartyNotice.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        ((json[key] as List?) ?? const []).cast<String>();
    return ThirdPartyNotice(
      id: json['id'] as String,
      name: json['name'] as String,
      license: json['license'] as String,
      licenseFile: json['licenseFile'] as String?,
      attribution: strings('attribution'),
      platforms: strings('platforms'),
      source: json['source'] as String,
      forks: strings('forks'),
      covers: strings('covers'),
      status: json['status'] as String,
      checked: json['checked'] as String,
    );
  }

  bool appliesToAny(Set<String> targets) => platforms.any(targets.contains);
}

List<ThirdPartyNotice> parseNotices(String manifestJson) {
  final json = jsonDecode(manifestJson) as Map<String, dynamic>;
  return (json['notices'] as List)
      .cast<Map<String, dynamic>>()
      .map(ThirdPartyNotice.fromJson)
      .toList();
}

/// The body of one notice as it appears on the licence page: attribution,
/// then the licence text.
String noticeText(ThirdPartyNotice notice, String licenseText) {
  return [
    ...notice.attribution,
    'Source: ${notice.source}',
    licenseText.trim(),
  ].join('\n\n');
}

/// Renders THIRD_PARTY_NOTICES.md. Generated, so the manifest stays the one
/// place to edit; the notices test fails when the two drift.
String renderNoticesMarkdown(List<ThirdPartyNotice> notices) {
  final b = StringBuffer()
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln('<!-- Generated from $noticesManifest by '
        '`dart run tool/gen_third_party_notices.dart`. Do not edit by hand. -->')
    ..writeln()
    ..writeln('Hearth is MIT-licensed (see `LICENSE`). Its builds also ship the '
        'code and content below, under their own licences. Every Dart package '
        'is credited separately by Flutter\'s package licences, which the app '
        'shows under Settings → System → Open-source licences next to these.')
    ..writeln()
    ..writeln('Full licence texts are in `$noticesDir/`. **Verified** means we '
        'read the licence at its source; **assumed** means we did not, and '
        'says why. This is our reading of each licence, not legal advice.')
    ..writeln()
    ..writeln('| Component | Licence | Platforms | Status |')
    ..writeln('|---|---|---|---|');
  for (final n in notices) {
    b.writeln('| [${n.name}](#${n.id}) | ${n.license} | '
        '${n.platforms.join(', ')} | ${n.status} |');
  }
  for (final n in notices) {
    b
      ..writeln()
      ..writeln('<a id="${n.id}"></a>')
      ..writeln('## ${n.name}')
      ..writeln();
    for (final line in n.attribution) {
      b
        ..writeln(line)
        ..writeln();
    }
    b
      ..writeln('- Licence: ${n.license}'
          '${n.licenseFile == null ? '' : ' (`$noticesDir/${n.licenseFile}`)'}')
      ..writeln('- Source: <${n.source}>');
    for (final fork in n.forks) {
      b.writeln('- Fork: <${fork.replaceFirst(RegExp(r'\.git$'), '')}>');
    }
    b
      ..writeln('- Platforms: ${n.platforms.join(', ')}')
      ..writeln('- Status: **${n.status}**. ${n.checked}'
          '${n.checked.endsWith('.') ? '' : '.'}');
  }
  return b.toString();
}
