import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../config/webview_config.dart';
import '../../modules/webview/webview_settings_section.dart';
import '../framework/list_section.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Webviews plugin.
///
/// Wraps the existing [WebviewSettingsSection] (HA dashboard picker + custom
/// URL list) as the on-device panel. The web render is read-only for v1 — it
/// shows ALL configured webviews (both HA dashboards and custom URLs) with a
/// hint that editing happens on-device.
///
/// Each entry in `HubConfig.webviews` also yields a `WebviewModule` instance
/// via the legacy module registry, which is what actually contributes the
/// PageView screens. That stays in place for now — plugin `pageScreen`
/// routing isn't wired yet.
///
/// Deferred for later sessions:
///   * Interactive HA dashboard discovery + toggle on the web
///   * Interactive custom URL add/edit/delete on the web (would need plugin
///     HTTP routes + a `CustomUrlList`-style JS UI)
///   * Owning the PageView screens via [pageScreen]
class WebviewPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.webview';

  @override
  String get name => 'Webviews';

  @override
  IconData get icon => Icons.web;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 90;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.webviews.isEmpty) return PluginConfigStatus.needsSetup;
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const WebviewSettingsSection();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final section = ListSection<WebviewConfig>(
      label: 'Configured Webviews',
      items: ctx.config.webviews,
      summaryFor: (w) {
        final source =
            w.source == WebviewSource.haDashboard ? 'HA dashboard' : 'Custom URL';
        return '${w.name} ($source) — ${w.url}';
      },
      // Web is read-only for v1; these callbacks are never invoked.
      onListChanged: (_) async {},
      editorBuilder: (_, existing) async => null,
    );
    return section.buildHtml();
  }
}
