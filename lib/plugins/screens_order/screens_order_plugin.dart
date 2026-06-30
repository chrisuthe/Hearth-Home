import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../modules/module_registry.dart';
import '../../widgets/module_placement_tile.dart';
import '../../widgets/module_reorder_list.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Screens & Order plugin — first device-category plugin.
///
/// Owns module placement (where each module appears: swipe / menu1 / menu2)
/// and the swipe-PageView reorder list. Both surfaces are bespoke widgets:
/// no [SettingField] primitive fits cleanly.
///
/// Surface differences:
///   * On-device: full UI — placement chips per module plus drag-reorder
///     list. Community modules are separated under their own subheader.
///   * Web portal: read-only hand-off note. Multi-select chips and drag
///     reorder don't map to the HTML primitives the framework offers today.
///
/// Status: always [PluginConfigStatus.configured] — every module ships with
/// a sane default placement, so there's nothing the user must fill in.
class ScreensOrderPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.screens_order';

  @override
  String get name => 'Screens & Order';

  @override
  IconData get icon => Icons.swap_horiz;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 10;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _ScreensOrderPanel();
  }

  // Web settings: enable/disable each module, choose where it appears
  // (swipe / menu1 / menu2), and reorder the swipe screens. The module list is
  // derivable from config at render time (static registry + configured
  // webviews), so the data is embedded server-side and the controls are
  // rendered by the inline script — no plugin route needed. Each of the three
  // fields persists through `hearth.save` (the generic typed /api/config
  // writer). The hidden `data-config-path` markers satisfy the web parity
  // drift-guard; they carry `data-no-auto-save` so the scalar auto-save binder
  // ignores them (these List/Map fields are saved by the script below).
  @override
  String buildSettingsHtml(WebContext ctx) {
    final modules = modulesForConfig(ctx.config);
    final data = <String, dynamic>{
      'modules': modules
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'defaultOrder': m.defaultOrder,
                'community': m.isCommunity,
              })
          .toList(),
      'enabledModules': ctx.config.enabledModules,
      'modulePlacements': ctx.config.modulePlacements,
      'moduleOrder': ctx.config.moduleOrder,
    };
    // Escape `<` so a webview title can't break out of the <script> block;
    // `<` is a valid JSON/JS escape that decodes back to `<`.
    final dataJson = jsonEncode(data).replaceAll('<', '\\u003c');
    return _screensOrderHtml.replaceFirst('/*__DATA__*/', dataJson);
  }
}

/// Self-contained HTML + JS for the web Screens & Order panel. Server-side
/// interpolation injects only the module list + current values (the
/// `/*__DATA__*/` placeholder); everything else is static. Each field is
/// saved independently via `hearth.save`, so a placement tweak doesn't rewrite
/// the order and vice-versa.
const _screensOrderHtml = r'''
<style>
  #screens-order-panel .so-row {
    display: flex; align-items: center; gap: 12px;
    padding: 10px 0; border-bottom: 1px solid #1f1f22;
  }
  #screens-order-panel .so-enable {
    display: flex; align-items: center; gap: 10px;
    min-width: 160px; font-size: 14px; color: #e0e0e0; cursor: pointer;
  }
  #screens-order-panel .so-enable input { accent-color: #646cff; }
  #screens-order-panel .so-chips { display: flex; flex-wrap: wrap; gap: 6px; flex: 1; }
  #screens-order-panel .so-chip {
    display: flex; align-items: center; gap: 6px;
    padding: 6px 10px; background: #161618; border: 1px solid #333;
    border-radius: 16px; font-size: 13px; cursor: pointer;
  }
  #screens-order-panel .so-chip input { accent-color: #646cff; }
  #screens-order-panel .so-reorder { display: flex; gap: 4px; }
  #screens-order-panel .so-btn {
    width: 30px; height: 30px; background: #161618; border: 1px solid #333;
    border-radius: 6px; color: #e0e0e0; font-size: 14px; cursor: pointer;
  }
  #screens-order-panel .so-btn:disabled { opacity: 0.3; cursor: default; }
  #screens-order-panel .so-footer { padding-top: 12px; }
  #screens-order-panel .so-reset {
    background: none; border: none; color: #888; font-size: 13px;
    cursor: pointer; padding: 4px 0;
  }
</style>
<div class="field">
  <label>Screens &amp; Order</label>
  <div class="hint" style="color:#888;font-size:12px;padding:0 0 8px">
    Enable modules, choose where each appears, and set the swipe order. Changes save automatically.
  </div>
  <div id="screens-order-panel">Loading screens…</div>
  <input type="hidden" data-config-path="enabledModules" data-no-auto-save>
  <input type="hidden" data-config-path="modulePlacements" data-no-auto-save>
  <input type="hidden" data-config-path="moduleOrder" data-no-auto-save>
</div>
<script>
(function () {
  var DATA = /*__DATA__*/;
  var root = document.getElementById('screens-order-panel');
  if (!root) return;

  var modules = DATA.modules || [];
  var enabled = (DATA.enabledModules || []).slice();
  var placements = {};
  var src = DATA.modulePlacements || {};
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k)) {
      placements[k] = (src[k] || []).slice();
    }
  }
  var order = (DATA.moduleOrder || []).slice();

  var PLACEMENTS = [
    { id: 'swipe', label: 'Swipe' },
    { id: 'menu1', label: 'Menu 1' },
    { id: 'menu2', label: 'Menu 2' }
  ];

  function byId(id) {
    for (var i = 0; i < modules.length; i++) {
      if (modules[i].id === id) return modules[i];
    }
    return null;
  }

  // Display order: the custom order first (existing modules only), then any
  // remaining modules by defaultOrder. Mirrors swipeModulesProvider.
  function displayOrder() {
    var seen = {};
    var result = [];
    order.forEach(function (id) {
      if (byId(id) && !seen[id]) { seen[id] = true; result.push(id); }
    });
    var rest = modules.filter(function (m) { return !seen[m.id]; });
    rest.sort(function (a, b) { return a.defaultOrder - b.defaultOrder; });
    rest.forEach(function (m) { result.push(m.id); });
    return result;
  }

  function saveEnabled() { hearth.save('enabledModules', enabled); }
  function savePlacements() {
    var out = {};
    for (var id in placements) {
      if (placements[id] && placements[id].length) out[id] = placements[id];
    }
    hearth.save('modulePlacements', out);
  }
  function saveOrder() { hearth.save('moduleOrder', order); }

  function move(id, delta) {
    var ids = displayOrder();
    var i = ids.indexOf(id);
    var j = i + delta;
    if (i === -1 || j < 0 || j >= ids.length) return;
    var tmp = ids[i]; ids[i] = ids[j]; ids[j] = tmp;
    order = ids;
    saveOrder();
    render();
  }

  function render() {
    root.textContent = '';
    var ids = displayOrder();
    ids.forEach(function (id, idx) {
      var m = byId(id);
      if (!m) return;
      var row = document.createElement('div');
      row.className = 'so-row';

      var enLabel = document.createElement('label');
      enLabel.className = 'so-enable';
      var en = document.createElement('input');
      en.type = 'checkbox';
      en.checked = enabled.indexOf(id) !== -1;
      en.addEventListener('change', function () {
        var i = enabled.indexOf(id);
        if (en.checked) { if (i === -1) enabled.push(id); }
        else if (i !== -1) enabled.splice(i, 1);
        saveEnabled();
      });
      var name = document.createElement('span');
      name.textContent = m.name;
      enLabel.appendChild(en);
      enLabel.appendChild(name);
      row.appendChild(enLabel);

      var chips = document.createElement('div');
      chips.className = 'so-chips';
      PLACEMENTS.forEach(function (p) {
        var chip = document.createElement('label');
        chip.className = 'so-chip';
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        var list = placements[id] || [];
        cb.checked = list.indexOf(p.id) !== -1;
        cb.addEventListener('change', function () {
          var l = placements[id] || (placements[id] = []);
          var i = l.indexOf(p.id);
          if (cb.checked) { if (i === -1) l.push(p.id); }
          else if (i !== -1) l.splice(i, 1);
          savePlacements();
        });
        var span = document.createElement('span');
        span.textContent = p.label;
        chip.appendChild(cb);
        chip.appendChild(span);
        chips.appendChild(chip);
      });
      row.appendChild(chips);

      var reorder = document.createElement('div');
      reorder.className = 'so-reorder';
      var up = document.createElement('button');
      up.type = 'button';
      up.className = 'so-btn';
      up.textContent = '↑';
      up.disabled = idx === 0;
      up.addEventListener('click', function () { move(id, -1); });
      var down = document.createElement('button');
      down.type = 'button';
      down.className = 'so-btn';
      down.textContent = '↓';
      down.disabled = idx === ids.length - 1;
      down.addEventListener('click', function () { move(id, 1); });
      reorder.appendChild(up);
      reorder.appendChild(down);
      row.appendChild(reorder);

      root.appendChild(row);
    });

    if (order.length) {
      var footer = document.createElement('div');
      footer.className = 'so-footer';
      var reset = document.createElement('button');
      reset.type = 'button';
      reset.className = 'so-reset';
      reset.textContent = 'Reset order to default';
      reset.addEventListener('click', function () {
        order = [];
        saveOrder();
        render();
      });
      footer.appendChild(reset);
      root.appendChild(footer);
    }
  }

  // hearth.js loads after this fragment, so wait for the full parse before
  // reaching for window.hearth.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', render);
  } else {
    render();
  }
})();
</script>
''';

class _ScreensOrderPanel extends ConsumerWidget {
  const _ScreensOrderPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final allModules = ref.watch(allModulesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...allModules.where((m) => !m.isCommunity).map(
              (m) => ModulePlacementTile(module: m, config: config),
            ),
        if (allModules.any((m) => m.isCommunity)) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: HearthSpacing.x2,
                top: HearthSpacing.x3,
                bottom: HearthSpacing.x1),
            child: Text(
              'Community Contributed',
              style: TextStyle(
                fontSize: HearthFont.caption,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
            child: Text(
              'Modules contributed by the community. Disabled by default — enable at your own discretion.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: HearthFont.caption,
              ),
            ),
          ),
          const SizedBox(height: HearthSpacing.x1),
          ...allModules.where((m) => m.isCommunity).map(
                (m) => ModulePlacementTile(module: m, config: config),
              ),
        ],
        const SizedBox(height: HearthSpacing.x3),
        ModuleReorderList(
          config: config,
          modules: allModules,
          onReorder: (newOrder) {
            ref.read(hubConfigProvider.notifier).update(
                  (c) => c.copyWith(moduleOrder: newOrder),
                );
          },
          onReset: () {
            ref.read(hubConfigProvider.notifier).update(
                  (c) => c.copyWith(moduleOrder: const []),
                );
          },
        ),
      ],
    );
  }
}
