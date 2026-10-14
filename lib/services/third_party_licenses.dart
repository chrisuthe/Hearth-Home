import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'third_party_notices.dart';

/// The notice platforms this build is. The Pi is the Linux build started
/// without media_kit (see main.dart).
Set<String> currentNoticePlatforms() {
  if (kIsWeb) return const {};
  if (Platform.isAndroid) return const {'android'};
  if (Platform.isWindows) return const {'windows'};
  if (Platform.isLinux) {
    return Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')
        ? const {'pi'}
        : const {'linux'};
  }
  return const {};
}

/// Adds the notices that apply to [platforms] to [LicenseRegistry], so they
/// list beside the Dart packages on Flutter's licence page and in
/// [LicenseRegistry.licenses]. Texts load lazily, when a page first asks.
void registerThirdPartyLicenses({
  AssetBundle? bundle,
  Set<String>? platforms,
}) {
  final assets = bundle ?? rootBundle;
  final targets = platforms ?? currentNoticePlatforms();
  LicenseRegistry.addLicense(() async* {
    final notices = parseNotices(await assets.loadString(noticesManifest));
    for (final notice in notices) {
      final file = notice.licenseFile;
      if (file == null || !notice.appliesToAny(targets)) continue;
      final text = await assets.loadString('$noticesDir/$file');
      yield LicenseEntryWithLineBreaks([notice.name], noticeText(notice, text));
    }
  });
}

/// Every licence in [LicenseRegistry] as one HTML page, grouped by package.
/// The `:8090` portal serves it; the device shows Flutter's licence page.
Future<String> renderLicensesHtml(Stream<LicenseEntry> licenses) async {
  final byPackage = <String, List<String>>{};
  await for (final entry in licenses) {
    final text = entry.paragraphs.map((p) => p.text).join('\n\n');
    for (final package in entry.packages) {
      byPackage.putIfAbsent(package, () => []).add(text);
    }
  }
  final packages = byPackage.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  const esc = HtmlEscape();
  final b = StringBuffer('''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth — Open-source licences</title>
<style>
body{background:#000;color:#e0e0e0;font-family:system-ui,sans-serif;max-width:860px;margin:0 auto;padding:16px}
a{color:#646CFF}
h2{font-size:16px;margin:28px 0 8px;border-top:1px solid #333;padding-top:16px}
pre{white-space:pre-wrap;font-size:12px;color:#bbb;background:#111;padding:12px;border-radius:6px}
ul{columns:2;font-size:13px}
</style></head><body>
<p><a href="/">← Settings</a></p>
<h1>Open-source licences</h1>
<p>Hearth is MIT-licensed and builds on the work below.</p>
<ul>
''');
  for (var i = 0; i < packages.length; i++) {
    b.writeln('<li><a href="#p$i">${esc.convert(packages[i])}</a></li>');
  }
  b.writeln('</ul>');
  for (var i = 0; i < packages.length; i++) {
    b.writeln('<h2 id="p$i">${esc.convert(packages[i])}</h2>');
    for (final text in byPackage[packages[i]]!) {
      b.writeln('<pre>${esc.convert(text)}</pre>');
    }
  }
  b.write('</body></html>');
  return b.toString();
}
