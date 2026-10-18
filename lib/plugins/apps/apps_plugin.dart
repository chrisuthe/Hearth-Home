import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/android_app_config.dart';
import '../../config/hub_config.dart';
import '../../services/android_apps.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Apps plugin: which installed Android apps get a tile, and whether they open
/// beside Hearth (split) or over it (full screen). Android only.
///
/// Routes enforce the platform gate themselves: plugin routes are not
/// auto-gated by [isVisible].
class AppsPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.apps';

  @override
  String get name => 'Apps';

  @override
  IconData get icon => Icons.apps;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 95;

  @override
  bool get isCommunity => false;

  @override
  bool isVisible(HubConfig config) => androidAppsSupported;

  @override
  PluginConfigStatus statusFor(HubConfig config) => config.androidApps.isEmpty
      ? PluginConfigStatus.needsSetup
      : PluginConfigStatus.configured;

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const _AppsPanel();

  @override
  String buildSettingsHtml(WebContext ctx) => _appsHtml;

  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('apps', (req) async {
      if (await _gated(req)) return;
      final bridge = req.readProvider(androidAppsBridgeProvider);
      final installed = await bridge.listApps();
      await req.respondJson({
        'installed': [
          for (final a in installed)
            {'packageName': a.packageName, 'label': a.label},
        ],
        'selected': [for (final a in req.config.androidApps) a.toJson()],
        'layout': req.config.androidAppLayout.toJson(),
        'overlayGranted': await bridge.overlayGranted(),
      });
    });

    router.post('apps', (req) async {
      if (await _gated(req)) return;
      final raw = (req.body['selected'] as List?) ?? const [];
      final selected = [
        for (final item in raw)
          AndroidAppConfig.fromJson((item as Map).cast<String, dynamic>()),
      ];
      final layout = req.body['layout'] is String
          ? AndroidAppLayout.fromJson(req.body['layout'] as String)
          : req.config.androidAppLayout;
      await req.updateConfig(
        (c) => _withSelection(c, selected).copyWith(androidAppLayout: layout),
      );
      await req.respondJson({'status': 'saved', 'count': selected.length});
    });
  }

  Future<bool> _gated(PluginRequest req) async {
    if (androidAppsSupported) return false;
    req.raw.response.statusCode = 404;
    req.raw.response.headers.contentType = ContentType.json;
    req.raw.response.write(jsonEncode({'error': 'not found'}));
    await req.raw.response.close();
    return true;
  }
}

/// [config] with [selected] as its app list. An app that has no placement yet
/// gets the swipe row; removing one leaves placements alone, so a tile the
/// user moved elsewhere keeps its place if the app is ticked again.
HubConfig _withSelection(HubConfig config, List<AndroidAppConfig> selected) {
  final placements = {...config.modulePlacements};
  for (final app in selected) {
    placements.putIfAbsent(app.id, () => const ['swipe']);
  }
  return config.copyWith(androidApps: selected, modulePlacements: placements);
}

class _AppsPanel extends ConsumerStatefulWidget {
  const _AppsPanel();

  @override
  ConsumerState<_AppsPanel> createState() => _AppsPanelState();
}

class _AppsPanelState extends ConsumerState<_AppsPanel>
    with WidgetsBindingObserver {
  late Future<bool> _overlay = _checkOverlay();

  Future<bool> _checkOverlay() =>
      ref.read(androidAppsBridgeProvider).overlayGranted();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The grant happens in Android's settings, so look again on the way back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _overlay = _checkOverlay());
    }
  }

  void _toggle(AndroidAppConfig app, bool on) {
    ref.read(hubConfigProvider.notifier).update((c) {
      final next = [
        for (final a in c.androidApps)
          if (a.packageName != app.packageName) a,
        if (on) app,
      ];
      return _withSelection(c, next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.hearthColors;
    final config = ref.watch(hubConfigProvider);
    final installed = ref.watch(installedAndroidAppsProvider);
    final selected = {for (final a in config.androidApps) a.packageName};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Open apps in', style: TextStyle(color: colors.textSecondary)),
        const SizedBox(height: 8),
        SegmentedButton<AndroidAppLayout>(
          segments: const [
            ButtonSegment(value: AndroidAppLayout.split, label: Text('Split')),
            ButtonSegment(
              value: AndroidAppLayout.fullscreen,
              label: Text('Full screen'),
            ),
          ],
          selected: {config.androidAppLayout},
          onSelectionChanged: (s) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(androidAppLayout: s.first)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Text(
            'Split keeps Hearth on screen beside the app. Full screen '
            'shrinks the app into a corner when Hearth needs you.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
        FutureBuilder<bool>(
          future: _overlay,
          builder: (context, snap) {
            if (snap.data != false) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: colors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Allow Hearth to display over other apps so it can come '
                      'forward during alarms and show its button over the app',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(androidAppsBridgeProvider)
                        .openOverlaySettings(),
                    child: const Text('Grant'),
                  ),
                ],
              ),
            );
          },
        ),
        Text(
          'APPS',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        installed.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Text(
            'Could not list the apps on this tablet.',
            style: TextStyle(color: colors.textMuted),
          ),
          data: (apps) => Column(
            children: [
              for (final app in apps)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(app.label),
                  value: selected.contains(app.packageName),
                  onChanged: (on) => _toggle(
                    AndroidAppConfig(
                      packageName: app.packageName,
                      name: app.label,
                    ),
                    on ?? false,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Self-contained web panel. It loads the installed apps, the selection, the
/// layout and the permission state from the `apps` GET route and saves both
/// through the POST route. The containers carry `data-config-path` for the web
/// parity guard; they are non-input `<div>`s, so the scalar auto-save binder
/// ignores them.
const _appsHtml = r'''
<style>
  #apps-panel .ap-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #161618; border-radius: 6px;
    margin-bottom: 4px; cursor: pointer;
  }
  #apps-panel .ap-row input { accent-color: #646cff; }
  #apps-panel .ap-hint { font-size: 12px; color: #888; padding: 4px 0 12px; }
  #apps-panel .ap-head {
    font-size: 11px; font-weight: 600; letter-spacing: 1.2px; color: #888;
    margin: 16px 0 8px;
  }
  #apps-panel .ap-warn {
    display: flex; align-items: center; gap: 10px; color: #fbbf24;
    font-size: 13px; margin-bottom: 12px;
  }
  #apps-panel select {
    padding: 9px 11px; background: #0e0e10; border: 1px solid #333;
    border-radius: 6px; color: #e0e0e0; font-size: 14px;
  }
  #apps-panel button {
    padding: 6px 12px; background: #333; color: #e0e0e0;
    border: 1px solid #444; border-radius: 6px; cursor: pointer;
  }
</style>
<div id="apps-panel">
  <div class="field" data-config-path="androidAppLayout">
    <label>Open apps in</label>
    <select id="ap-layout">
      <option value="split">Split</option>
      <option value="fullscreen">Full screen</option>
    </select>
    <div class="ap-hint">Split keeps Hearth on screen beside the app. Full screen shrinks the app into a corner when Hearth needs you.</div>
  </div>
  <div id="ap-perm"></div>
  <div class="field" data-config-path="androidApps">
    <div class="ap-head">APPS</div>
    <div id="ap-list">Loading apps…</div>
  </div>
</div>
<script>
(function () {
  var list = document.getElementById('ap-list');
  var perm = document.getElementById('ap-perm');
  var layoutSel = document.getElementById('ap-layout');
  if (!list) return;

  var installed = [];
  var selected = [];
  var saveTimer = null;

  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      hearth.action('apps', { selected: selected, layout: layoutSel.value })
        .catch(function (e) { console.error('apps save failed', e); });
    }, 400);
  }

  function indexOfPkg(pkg) {
    for (var i = 0; i < selected.length; i++)
      if (selected[i].packageName === pkg) return i;
    return -1;
  }

  function render() {
    list.textContent = '';
    installed.forEach(function (a) {
      var row = document.createElement('label');
      row.className = 'ap-row';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = indexOfPkg(a.packageName) !== -1;
      cb.addEventListener('change', function () {
        var idx = indexOfPkg(a.packageName);
        if (cb.checked && idx === -1) {
          selected.push({ packageName: a.packageName, name: a.label });
        } else if (!cb.checked && idx !== -1) {
          selected.splice(idx, 1);
        }
        save();
      });
      var txt = document.createElement('span');
      txt.textContent = a.label;
      row.appendChild(cb);
      row.appendChild(txt);
      list.appendChild(row);
    });
  }

  function renderPerm(granted) {
    perm.textContent = '';
    if (granted) return;
    var box = document.createElement('div');
    box.className = 'ap-warn';
    var msg = document.createElement('span');
    msg.textContent = 'Allow Hearth to display over other apps so it can come forward during alarms and show its button over the app. Grant it on the tablet under Settings, Apps, Hearth.';
    box.appendChild(msg);
    perm.appendChild(box);
  }

  layoutSel.addEventListener('change', save);

  function load() {
    hearth.action('apps').then(function (data) {
      installed = data.installed || [];
      selected = data.selected || [];
      layoutSel.value = data.layout || 'split';
      renderPerm(!!data.overlayGranted);
      render();
    }).catch(function (e) {
      list.textContent = 'Failed to load apps.';
      console.error(e);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }
})();
</script>
''';
