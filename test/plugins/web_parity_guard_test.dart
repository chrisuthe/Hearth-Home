import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/plugin_registry.dart';

/// Structural drift guard between the on-device settings panels and the web
/// settings portal.
///
/// Settings are plugin-driven: each plugin renders its panel twice — a Flutter
/// widget on-device and an HTML fragment on the web portal — from two
/// hand-written methods. That duplication is where the two surfaces silently
/// drift: a field gets added to one method and forgotten on the other.
///
/// This guard treats the set of `HubConfig` keys as the ledger. Every key must
/// be either:
///   * editable on the web portal (rendered with a `data-config-path`), or
///   * listed in [webExempt] with a reason (intentional device-only / internal
///     field, or a parity gap deferred to a later phase).
///
/// A new `HubConfig` field that lands on-device but not on the web — and isn't
/// exempted — fails this test. So does a stale exemption: once a deferred field
/// is ported to the web, its [webExempt] entry must be removed.
///
/// Note: this only covers `HubConfig`-backed settings. Settings stored
/// elsewhere (e.g. alarms in AlarmService) are out of scope by design.
///
/// ## Second axis: UX degradation
///
/// Field-level parity proves a setting is *reachable* on web, not that the web
/// affordance *matches* the on-device one. Some fields pass the field-level
/// guard as plain text inputs while on-device they are rich pickers (a live HA
/// entity dropdown, a searchable timezone list). The author flags each such
/// soft gap with a `// Web degradation:` comment right above the degraded field
/// in the plugin source — that comment is the structural signal this guard
/// reads.
///
/// A second ledger, [webDegraded], documents each known degradation with a
/// reason (mirroring [webExempt]). The degradation guard then:
///   * fails if a field is marked `// Web degradation:` in source but missing
///     from [webDegraded] (forces a new soft gap to be acknowledged), and
///   * fails on a stale entry — a [webDegraded] field whose source marker is
///     gone because it was upgraded to a real web picker (forces the entry to
///     be removed as the gap closes).
void main() {
  /// Web-editable config paths the portal renders, across all plugins.
  Set<String> collectWebPaths() {
    const config = HubConfig();
    final paths = <String>{};
    final re = RegExp(r'data-config-path="([^"]*)"');
    for (final plugin in firstPartyPlugins) {
      final ctx = WebContext(
        config: config,
        apiBearerToken: 'test',
        pluginActionPrefix: '/api/plugin/${plugin.id}',
      );
      for (final m in re.allMatches(plugin.buildSettingsHtml(ctx))) {
        final p = m.group(1)!;
        if (p.isNotEmpty) paths.add(p);
      }
    }
    return paths;
  }

  /// Config paths flagged as UX-degraded on web, read from the `// Web
  /// degradation:` markers in the plugin source.
  ///
  /// Each marker sits directly above the degraded web field, e.g.
  ///
  /// ```dart
  /// // Web degradation: the browser has no live HA entity list, so we
  /// // render a plain text input ...
  /// final satelliteHtml = const TextSettingField(
  ///   configPath: 'voiceAssistantEntityId',
  /// ```
  ///
  /// so the path is the first `configPath: '...'` after the marker. This is the
  /// existing in-code convention; reading it keeps the ledger honest without
  /// touching production behavior.
  Set<String> collectDegradedPaths() {
    final pluginsDir = Directory('lib/plugins');
    final paths = <String>{};
    final re = RegExp(r"// Web degradation:[\s\S]*?configPath:\s*'([^']+)'");
    for (final entity in pluginsDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final m in re.allMatches(entity.readAsStringSync())) {
        paths.add(m.group(1)!);
      }
    }
    return paths;
  }

  /// Config keys that are intentionally NOT editable on the web portal, each
  /// with the reason. Two groups:
  ///
  ///   1. Permanent — internal/app-managed fields, or device-only settings the
  ///      browser can't drive.
  ///   2. Deferred — real parity gaps slated for a later phase of the web
  ///      portal parity work. Remove the entry when the field lands on web.
  const webExempt = <String, String>{
    // --- Permanent: internal / app-managed ---
    'apiKey': 'internal: API bearer token, redacted on read, never web-writable',
    'currentVersion': 'internal: managed by the updater',
    'sendspinClientId': 'internal: app-seeded Sendspin device identity',
    'sendspinStaticDelayMs':
        'internal: advanced sync tuning, not surfaced in any settings panel',
    'setupComplete': 'internal: first-run flow state',
    'touchIndicator':
        'edited via the /capture dev-tools page, not the main settings portal',

    // --- Permanent: device-only (browser cannot drive) ---
    'displayProfile':
        'device-only: selects a flutter-pi connector the browser cannot '
            'enumerate (web shows a hand-off note)',
    'displayWidth': 'device-only: part of the display-profile override',
    'displayHeight': 'device-only: part of the display-profile override',

    // --- Deferred: parity gaps to close in a later phase ---
    'updateSource':
        'deferred: System update-source toggle + force-update',
  };

  /// Fields that ARE web-editable but with a degraded affordance — a plain text
  /// input on web where the on-device panel has a richer picker. Each must
  /// carry a `// Web degradation:` marker in source (the signal
  /// [collectDegradedPaths] reads); remove the entry when the field is upgraded
  /// to a real web picker. Distinct from [webExempt], which is for fields not on
  /// the web portal at all.
  const webDegraded = <String, String>{
    'voiceAssistantEntityId':
        'web: plain text input to paste the entity id; on-device is a live '
            'assist_satellite dropdown. Upgrade tracked by '
            'web-parity-ha-entity-pickers.',
    'timezone':
        'web: free-text IANA zone; on-device is a searchable '
            'TimezonePickerDialog. Upgrade tracked by web-parity-timezone.',
  };

  test('every HubConfig field is web-editable or documented as exempt', () {
    final webPaths = collectWebPaths();
    final configKeys = const HubConfig().toJson().keys.toSet();

    final unclassified = configKeys
        .where((k) => !webPaths.contains(k) && !webExempt.containsKey(k))
        .toList()
      ..sort();

    expect(
      unclassified,
      isEmpty,
      reason: 'These HubConfig fields are not editable on the web portal and '
          'are not in webExempt. Either render them on web (add a '
          'data-config-path field to the owning plugin) or add a documented '
          'exemption: $unclassified',
    );
  });

  test('no stale or bogus web exemptions', () {
    final webPaths = collectWebPaths();
    final configKeys = const HubConfig().toJson().keys.toSet();

    // An exemption for a key that doesn't exist on HubConfig anymore.
    final bogus = webExempt.keys.where((k) => !configKeys.contains(k)).toList()
      ..sort();
    expect(bogus, isEmpty,
        reason: 'webExempt references config keys that no longer exist: $bogus');

    // An exemption for a field that is now editable on web — the entry must be
    // removed so the ledger reflects reality.
    final stale = webExempt.keys.where(webPaths.contains).toList()..sort();
    expect(stale, isEmpty,
        reason: 'These fields are now editable on web — remove them from '
            'webExempt: $stale');
  });

  test('every web data-config-path maps to a real HubConfig field', () {
    final webPaths = collectWebPaths();
    final configKeys = const HubConfig().toJson().keys.toSet();

    final orphans = webPaths.where((p) => !configKeys.contains(p)).toList()
      ..sort();
    expect(orphans, isEmpty,
        reason: 'These web fields post to a config path that is not a '
            'HubConfig key (typo? renamed field?) — saves would silently '
            'no-op: $orphans');
  });

  test('every web-degraded field is documented in webDegraded', () {
    final degraded = collectDegradedPaths();

    final undocumented =
        degraded.where((p) => !webDegraded.containsKey(p)).toList()..sort();

    expect(
      undocumented,
      isEmpty,
      reason: 'These fields carry a `// Web degradation:` marker in the plugin '
          'source but are not in webDegraded. Document each soft parity gap '
          '(degraded web input vs. a richer on-device picker) with a reason, '
          'or remove the marker if the web field is now a full picker: '
          '$undocumented',
    );
  });

  test('no stale or bogus web-degradation entries', () {
    final degraded = collectDegradedPaths();
    final configKeys = const HubConfig().toJson().keys.toSet();

    // An entry for a key that doesn't exist on HubConfig anymore.
    final bogus =
        webDegraded.keys.where((k) => !configKeys.contains(k)).toList()..sort();
    expect(bogus, isEmpty,
        reason: 'webDegraded references config keys that no longer exist: '
            '$bogus');

    // An entry whose `// Web degradation:` marker is gone — the field was
    // upgraded to a real web picker, so the ledger entry must be removed.
    final stale =
        webDegraded.keys.where((k) => !degraded.contains(k)).toList()..sort();
    expect(stale, isEmpty,
        reason: 'These fields no longer carry a `// Web degradation:` marker '
            '(upgraded to a web picker?) — remove them from webDegraded: '
            '$stale');
  });

  test('webDegraded and webExempt are disjoint', () {
    // A field is either absent from the web portal (webExempt) or present but
    // degraded (webDegraded) — never both.
    final overlap =
        webDegraded.keys.where(webExempt.containsKey).toList()..sort();
    expect(overlap, isEmpty,
        reason: 'These fields are listed as both exempt (not on web) and '
            'degraded (a basic web input) — pick one: $overlap');
  });
}
