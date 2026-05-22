import '../../config/hub_config.dart';
import '../hearth_plugin.dart';
import 'web_assets.dart';
import 'web_context.dart';

/// Renders the full settings page HTML from the plugin registry.
///
/// The selected plugin is passed in; the renderer assembles the sidebar
/// (all plugins + Legacy) and the active plugin's panel (via
/// [HearthPlugin.buildSettingsHtml]).
class WebRenderer {
  /// Plugins to render in the sidebar, in display order.
  final List<HearthPlugin> plugins;

  /// Bearer token to inject so client JS can call /api/* endpoints.
  final String bearerToken;

  /// HTML chunk for the legacy panel (existing flat-page content with
  /// plugin-owned fields stripped out as plugins migrate). Shown when
  /// `selectedId == 'legacy'`.
  final String legacyHtml;

  /// Current config snapshot, used to hydrate field values when rendering
  /// each plugin's HTML.
  final HubConfig config;

  WebRenderer({
    required this.plugins,
    required this.bearerToken,
    required this.legacyHtml,
    required this.config,
  });

  /// Render the full page. [selectedId] is the currently-selected sidebar
  /// row — a plugin ID or `'legacy'`.
  String render({required String selectedId}) {
    final features =
        plugins.where((p) => p.category == PluginCategory.feature).toList();
    final devices =
        plugins.where((p) => p.category == PluginCategory.device).toList();

    HearthPlugin? selected;
    if (selectedId != 'legacy') {
      for (final p in plugins) {
        if (p.id == selectedId) {
          selected = p;
          break;
        }
      }
      // If a non-legacy id didn't match any plugin (stale URL), fall back
      // to first plugin or legacy.
      selected ??= plugins.isNotEmpty ? plugins.first : null;
    }

    String panelHtml;
    if (selected == null) {
      panelHtml =
          '<div class="panel-header"><h1>Legacy Settings</h1></div>$legacyHtml';
    } else {
      final ctx = WebContext(
        config: config,
        apiBearerToken: bearerToken,
        pluginActionPrefix: '/api/plugin/${selected.id}',
      );
      panelHtml = '''
<div class="panel-header">
  <h1>${_escape(selected.name)}</h1>
</div>
${selected.buildSettingsHtml(ctx)}
''';
    }

    final pluginPrefix = selected != null ? '/api/plugin/${selected.id}' : '';

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth Settings</title>
<style>$hearthCss</style>
</head>
<body>
<aside class="sidebar">
${_renderSidebar(features, devices, selectedId)}
</aside>
<main class="panel">
$panelHtml
</main>
<script>
window.__HEARTH_BEARER__ = '${_escapeJs(bearerToken)}';
window.__HEARTH_PLUGIN_PREFIX__ = '${_escapeJs(pluginPrefix)}';
</script>
<script>$hearthJs</script>
</body>
</html>
''';
  }

  String _renderSidebar(List<HearthPlugin> features,
      List<HearthPlugin> devices, String selectedId) {
    final buf = StringBuffer();
    if (features.isNotEmpty) {
      buf.writeln('<div class="category">FEATURES</div>');
      for (final p in features) {
        buf.writeln(_renderRow(p, selectedId));
      }
    }
    if (devices.isNotEmpty) {
      buf.writeln('<div class="category">DEVICE</div>');
      for (final p in devices) {
        buf.writeln(_renderRow(p, selectedId));
      }
    }
    buf.writeln('<div class="category">LEGACY</div>');
    final legacyClass =
        selectedId == 'legacy' ? 'row legacy selected' : 'row legacy';
    buf.writeln(
        '<a class="$legacyClass" href="?panel=legacy">Legacy Settings</a>');
    return buf.toString();
  }

  String _renderRow(HearthPlugin p, String selectedId) {
    final selected = p.id == selectedId ? 'row selected' : 'row';
    final tag =
        p.isCommunity ? '<span class="community-tag">community</span>' : '';
    return '<a class="$selected" href="?panel=${p.id}">${_escape(p.name)}$tag</a>';
  }
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _escapeJs(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll('\n', '\\n');
