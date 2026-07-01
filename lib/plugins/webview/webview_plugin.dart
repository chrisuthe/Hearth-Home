import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../config/webview_config.dart';
import '../../modules/webview/webview_settings_section.dart';
import '../../services/ha_lovelace_service.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Webviews plugin.
///
/// Wraps the existing [WebviewSettingsSection] (HA dashboard picker + custom
/// URL list) as the on-device panel. The web portal renders an interactive
/// equivalent: an HA dashboard toggle list plus custom-URL add/edit/delete,
/// backed by the `webviews` plugin routes below (the browser has no HA
/// connection, so dashboard discovery is proxied through the backend).
///
/// Each entry in `HubConfig.webviews` also yields a `WebviewModule` instance
/// via the legacy module registry, which is what actually contributes the
/// PageView screens. That stays in place for now — plugin `pageScreen`
/// routing isn't wired yet.
///
/// Deferred for later sessions:
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

  // Web settings: an interactive HA dashboard toggle list + custom-URL
  // editor, driven by the `webviews` plugin routes below. The static HTML
  // render can't reach the live HA dashboard list, so the picker loads its
  // data at runtime via `hearth.action` and persists the chosen webviews
  // through the POST route.
  @override
  String buildSettingsHtml(WebContext ctx) {
    // Web parity for the on-device "Dark mode for HA dashboards" toggle.
    final darkModeHtml = const BoolSettingField(
      label: 'Dark mode for HA dashboards',
      subtitle: 'Signal prefers-color-scheme: dark to Home Assistant',
      configPath: 'haDashboardDarkMode',
    ).buildHtml(ctx);
    return '$darkModeHtml$_webviewsHtml';
  }

  /// Routes backing the web Webviews panel:
  ///   * GET  webviews — discovered HA dashboards (via readProvider), the
  ///     current webview list, and the custom-editor icon choices, so the
  ///     panel can hydrate.
  ///   * POST webviews — persist the full webview list via updateConfig.
  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('webviews', (req) async {
      final haConfigured = req.config.haUrl.isNotEmpty;

      List<Map<String, dynamic>> dashboards = const [];
      if (haConfigured) {
        final lovelace = req.readProvider(haLovelaceServiceProvider);
        final list = await lovelace.listDashboards();
        dashboards = [
          for (final d in list)
            {
              'urlPath': d.urlPath,
              'title': d.title,
              'fullUrl': d.fullUrlOn(req.config.haUrl),
              'iconCodePoint': _materialIconFor(d.icon).codePoint,
            },
        ];
      }

      await req.respondJson({
        'haConfigured': haConfigured,
        'dashboards': dashboards,
        'webviews': [for (final w in req.config.webviews) w.toJson()],
        'icons': customEditorIcons,
      });
    });

    router.post('webviews', (req) async {
      final raw = (req.body['webviews'] as List?) ?? const [];
      final next = [
        for (final item in raw)
          WebviewConfig.fromJson((item as Map).cast<String, dynamic>()),
      ];
      await req.updateConfig((c) => c.copyWith(webviews: next));
      await req.respondJson({'status': 'saved', 'count': next.length});
    });
  }

  /// Icon choices offered in the web custom-URL editor, as `{name, codePoint}`.
  /// Mirrors the on-device editor's icon set (custom_url_editor.dart) so the
  /// two surfaces pick from the same icons. Built from the live [Icons]
  /// codepoints rather than hardcoded hex.
  @visibleForTesting
  static List<Map<String, dynamic>> get customEditorIcons => [
        {'name': 'Dashboard', 'codePoint': Icons.dashboard.codePoint},
        {'name': 'Web', 'codePoint': Icons.web.codePoint},
        {'name': 'Analytics', 'codePoint': Icons.analytics.codePoint},
        {'name': 'Chart', 'codePoint': Icons.show_chart.codePoint},
        {'name': 'Electrical', 'codePoint': Icons.electrical_services.codePoint},
        {'name': 'Shopping', 'codePoint': Icons.shopping_cart.codePoint},
        {'name': 'Print', 'codePoint': Icons.print.codePoint},
        {'name': 'Cloud', 'codePoint': Icons.cloud.codePoint},
        {'name': 'Security', 'codePoint': Icons.security.codePoint},
        {'name': 'Thermostat', 'codePoint': Icons.thermostat.codePoint},
      ];

  /// Best-effort MDI → Material icon mapping for HA dashboard icons. Mirrors
  /// the on-device picker (ha_dashboard_picker.dart).
  static IconData _materialIconFor(String? mdiIcon) {
    switch (mdiIcon) {
      case 'mdi:view-dashboard':
        return Icons.dashboard;
      case 'mdi:lightbulb':
        return Icons.lightbulb_outline;
      case 'mdi:thermometer':
        return Icons.thermostat;
      case 'mdi:home':
        return Icons.home;
      case 'mdi:flash':
        return Icons.bolt;
      case 'mdi:security':
        return Icons.security;
      case 'mdi:map':
        return Icons.map;
      default:
        return Icons.dashboard;
    }
  }
}

/// Self-contained HTML + JS for the web Webviews panel. No server-side
/// interpolation: the panel fetches dashboards, the current webview list, and
/// the editor icon choices from the `webviews` GET route, and persists the
/// full list via the POST route — both reached through `hearth.action` (which
/// scopes to this plugin's prefix).
///
/// The container's `data-config-path="webviews"` satisfies the web parity
/// drift-guard; it sits on a non-input `<div>` the scalar auto-save binder
/// ignores (this list is saved through the plugin route).
const _webviewsHtml = r'''
<style>
  #webview-panel .wv-section { margin-bottom: 20px; }
  #webview-panel .wv-head {
    display: flex; align-items: center; gap: 8px;
    font-weight: 600; color: #fff; margin-bottom: 8px;
  }
  #webview-panel .wv-head .wv-spacer { flex: 1; }
  #webview-panel .wv-btn {
    background: none; border: none; color: #646cff;
    font-size: 13px; cursor: pointer; padding: 4px 6px;
  }
  #webview-panel .wv-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #161618; border-radius: 6px;
    margin-bottom: 4px;
  }
  #webview-panel .wv-row .wv-text { flex: 1; min-width: 0; }
  #webview-panel .wv-row .wv-sub {
    font-size: 11px; color: #777;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  #webview-panel .wv-row input[type="checkbox"] { accent-color: #646cff; }
  #webview-panel .wv-icon-btn {
    background: none; border: none; cursor: pointer; font-size: 13px;
    color: #888; padding: 4px 8px;
  }
  #webview-panel .wv-icon-btn.wv-del { color: #ef5350; }
  #webview-panel .wv-hint { font-size: 12px; color: #888; padding: 4px 0; }
  #webview-panel .wv-editor {
    background: #161618; border: 1px solid #333; border-radius: 6px;
    padding: 12px; margin-bottom: 8px;
  }
  #webview-panel .wv-editor input, #webview-panel .wv-editor select {
    width: 100%; padding: 9px 11px; background: #0e0e10;
    border: 1px solid #333; border-radius: 6px; color: #e0e0e0;
    font-size: 14px; outline: none; margin-bottom: 8px;
  }
  #webview-panel .wv-editor input:focus, #webview-panel .wv-editor select:focus {
    border-color: #646cff;
  }
  #webview-panel .wv-editor .wv-actions { display: flex; gap: 8px; justify-content: flex-end; }
  #webview-panel .wv-save {
    background: #646cff; color: #fff; border: none; border-radius: 6px;
    padding: 8px 16px; font-size: 13px; cursor: pointer;
  }
  #webview-panel .wv-cancel {
    background: none; color: #888; border: none;
    padding: 8px 12px; font-size: 13px; cursor: pointer;
  }
</style>
<div class="field" data-config-path="webviews">
  <label>Webviews</label>
  <div id="webview-panel">Loading webviews…</div>
</div>
<script>
(function () {
  var root = document.getElementById('webview-panel');
  if (!root) return;

  var state = [];          // full webview list (objects)
  var dashboards = [];      // discovered HA dashboards
  var haConfigured = false;
  var icons = [];           // [{name, codePoint}]
  var editing = null;       // {id|null, name, url, iconCodePoint} or null
  var loaded = false;
  var saveTimer = null;

  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      hearth.action('webviews', { webviews: state }).catch(function (e) {
        console.error('webviews save failed', e);
      });
    }, 400);
  }

  function haId(urlPath) { return 'webview:ha:' + urlPath; }
  function customId() {
    var s = '';
    for (var i = 0; i < 8; i++) s += Math.floor(Math.random() * 16).toString(16);
    return 'webview:custom:' + s;
  }
  function indexOfId(id) {
    for (var i = 0; i < state.length; i++) if (state[i].id === id) return i;
    return -1;
  }

  function elem(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // --- HA dashboards section ---
  function toggleDashboard(d, on) {
    var id = haId(d.urlPath);
    var idx = indexOfId(id);
    if (on && idx === -1) {
      state.push({
        id: id, url: d.fullUrl, name: d.title,
        iconCodePoint: d.iconCodePoint, source: 'haDashboard',
        order: state.length,
      });
    } else if (!on && idx !== -1) {
      state.splice(idx, 1);
    }
    save();
    render();
  }

  function renderHaSection() {
    var sec = elem('div', 'wv-section');
    var head = elem('div', 'wv-head');
    head.appendChild(elem('span', null, 'Home Assistant dashboards'));
    var spacer = elem('span', 'wv-spacer'); head.appendChild(spacer);
    if (haConfigured) {
      var refresh = elem('button', 'wv-btn', 'Refresh');
      refresh.addEventListener('click', function () { load(true); });
      head.appendChild(refresh);
    }
    sec.appendChild(head);

    if (!haConfigured) {
      sec.appendChild(elem('div', 'wv-hint',
        'Configure Home Assistant connection first to auto-discover dashboards.'));
      return sec;
    }
    if (!dashboards.length) {
      sec.appendChild(elem('div', 'wv-hint',
        'No dashboards found. Check the Home Assistant connection in settings.'));
      return sec;
    }
    dashboards.forEach(function (d) {
      var row = elem('label', 'wv-row');
      row.style.cursor = 'pointer';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = indexOfId(haId(d.urlPath)) !== -1;
      cb.addEventListener('change', function () { toggleDashboard(d, cb.checked); });
      var txt = elem('div', 'wv-text');
      txt.appendChild(elem('div', null, d.title));
      txt.appendChild(elem('div', 'wv-sub', d.urlPath));
      row.appendChild(cb);
      row.appendChild(txt);
      sec.appendChild(row);
    });
    return sec;
  }

  // --- Custom URLs section ---
  function startEdit(item) {
    // New custom URLs default to the "Web" icon, matching the on-device editor.
    var web = icons.filter(function (i) { return i.name === 'Web'; })[0];
    var def = web ? web.codePoint : (icons.length ? icons[0].codePoint : 0);
    editing = item
      ? { id: item.id, name: item.name, url: item.url, iconCodePoint: item.iconCodePoint }
      : { id: null, name: '', url: '', iconCodePoint: def };
    render();
  }

  function commitEdit() {
    var name = editing.name.trim();
    var url = editing.url.trim();
    if (!name || !url) return;
    if (editing.id) {
      var idx = indexOfId(editing.id);
      if (idx !== -1) {
        state[idx].name = name;
        state[idx].url = url;
        state[idx].iconCodePoint = editing.iconCodePoint;
      }
    } else {
      state.push({
        id: customId(), url: url, name: name,
        iconCodePoint: editing.iconCodePoint, source: 'customUrl',
        order: state.length,
      });
    }
    editing = null;
    save();
    render();
  }

  function removeWebview(id) {
    var idx = indexOfId(id);
    if (idx !== -1) { state.splice(idx, 1); save(); render(); }
  }

  function renderEditor() {
    var ed = elem('div', 'wv-editor');
    var name = document.createElement('input');
    name.type = 'text';
    name.placeholder = 'Name';
    name.value = editing.name;
    name.addEventListener('input', function () { editing.name = name.value; });
    var url = document.createElement('input');
    url.type = 'text';
    url.placeholder = 'https://…';
    url.value = editing.url;
    url.addEventListener('input', function () { editing.url = url.value; });
    var sel = document.createElement('select');
    icons.forEach(function (ic) {
      var opt = document.createElement('option');
      opt.value = String(ic.codePoint);
      opt.textContent = ic.name;
      if (ic.codePoint === editing.iconCodePoint) opt.selected = true;
      sel.appendChild(opt);
    });
    sel.addEventListener('change', function () {
      editing.iconCodePoint = parseInt(sel.value, 10);
    });
    var actions = elem('div', 'wv-actions');
    var cancel = elem('button', 'wv-cancel', 'Cancel');
    cancel.addEventListener('click', function () { editing = null; render(); });
    var saveBtn = elem('button', 'wv-save', editing.id ? 'Save' : 'Add');
    saveBtn.addEventListener('click', commitEdit);
    actions.appendChild(cancel);
    actions.appendChild(saveBtn);
    ed.appendChild(name);
    ed.appendChild(url);
    ed.appendChild(sel);
    ed.appendChild(actions);
    return ed;
  }

  function renderCustomSection() {
    var sec = elem('div', 'wv-section');
    var head = elem('div', 'wv-head');
    head.appendChild(elem('span', null, 'Custom URLs'));
    head.appendChild(elem('span', 'wv-spacer'));
    if (!editing) {
      var add = elem('button', 'wv-btn', '+ Add');
      add.addEventListener('click', function () { startEdit(null); });
      head.appendChild(add);
    }
    sec.appendChild(head);

    if (editing) sec.appendChild(renderEditor());

    var customs = state.filter(function (w) { return w.source === 'customUrl'; });
    if (!customs.length && !editing) {
      sec.appendChild(elem('div', 'wv-hint', 'No custom URLs yet.'));
      return sec;
    }
    customs.forEach(function (w) {
      var row = elem('div', 'wv-row');
      var txt = elem('div', 'wv-text');
      txt.appendChild(elem('div', null, w.name));
      txt.appendChild(elem('div', 'wv-sub', w.url));
      var edit = elem('button', 'wv-icon-btn', 'Edit');
      edit.addEventListener('click', function () { startEdit(w); });
      var del = elem('button', 'wv-icon-btn wv-del', 'Delete');
      del.addEventListener('click', function () { removeWebview(w.id); });
      row.appendChild(txt);
      row.appendChild(edit);
      row.appendChild(del);
      sec.appendChild(row);
    });
    return sec;
  }

  function render() {
    if (!loaded) return;
    root.textContent = '';
    root.appendChild(renderHaSection());
    root.appendChild(renderCustomSection());
  }

  function load(isRefresh) {
    hearth.action('webviews').then(function (data) {
      haConfigured = !!data.haConfigured;
      dashboards = data.dashboards || [];
      icons = data.icons || [];
      // On the initial load, hydrate the editable list from config. On a
      // manual refresh, keep the in-memory list (it may hold unsaved edits)
      // and only refresh the discovered dashboards.
      if (!isRefresh) state = data.webviews || [];
      loaded = true;
      render();
    }).catch(function (e) {
      root.textContent = 'Failed to load webviews.';
      console.error(e);
    });
  }

  // hearth.js is loaded after this panel fragment, so defer until the page is
  // fully parsed (DOMContentLoaded) before reaching for window.hearth.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { load(false); });
  } else {
    load(false);
  }
})();
</script>
''';
