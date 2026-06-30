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
    'enabledModules':
        'deferred: Screens & Order module enable/placement parity',
    'modulePlacements':
        'deferred: Screens & Order module enable/placement parity',
    'moduleOrder':
        'deferred: Screens & Order module reorder parity',
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
}
