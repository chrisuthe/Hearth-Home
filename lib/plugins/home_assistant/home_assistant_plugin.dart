import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import '../../widgets/entity_picker_dialog.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Home Assistant integration plugin.
///
/// Owns the `haUrl`, `haToken`, `voiceAssistantEntityId`, and
/// `pinnedEntityIds` HubConfig fields. The Controls module
/// (`lib/modules/controls/`) keeps its existing PageView screen and the
/// long-lived [HomeAssistantService]; this plugin only handles the
/// connection settings, the voice satellite picker, and the pinned-entity
/// list management.
///
/// Surface differences:
///   * On-device: voice satellite is a [SelectSettingField] whose options
///     are populated dynamically from the live HA entity list (any
///     `assist_satellite.*`). Pinned devices opens [EntityPickerDialog].
///   * Web portal: voice satellite renders a searchable [HaEntityPickerField]
///     populated from this plugin's `entities` HTTP route (filtered to
///     `assist_satellite`), with a free-text fallback when HA is unreachable.
///     Pinned devices renders a searchable multi-select that loads the live
///     HA entity list through the same `entities` route (the browser has no
///     HA connection) and persists picks through the `pinned` route.
///
/// Out of scope (stays in the legacy panel for now):
///   * Mic mute toggle (`micMuted`) — lives in the Voice plugin (drives the
///     satellite's HA Mute switch under the hood).
///   * Show voice feedback (`showVoiceFeedback`) — kiosk UI, not HA.
///   * The Controls module's PageView screen.
class HomeAssistantPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.ha';

  @override
  String get name => 'Home Assistant';

  @override
  IconData get icon => Icons.home;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 10;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.haUrl.isEmpty || config.haToken.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    if (config.pinnedEntityIds.isEmpty) {
      // Connection works but the Controls screen would be empty.
      return PluginConfigStatus.partial;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _HomeAssistantPanel();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final urlHtml = const TextSettingField(
      configPath: 'haUrl',
      label: 'Home Assistant URL',
      hint: 'http://192.168.1.x:8123',
    ).buildHtml(ctx);

    final tokenHtml = const PasswordSettingField(
      configPath: 'haToken',
      label: 'Long-Lived Access Token',
      hint: 'Paste your HA token',
    ).buildHtml(ctx);

    // Searchable picker over the live `assist_satellite.*` entities, served by
    // the shared `entities` route. The free-text input underneath still lets
    // the user paste an id (or leave it blank for MAC auto-detect) when HA is
    // unreachable, matching the on-device dropdown's capability.
    final satelliteHtml = const HaEntityPickerField(
      configPath: 'voiceAssistantEntityId',
      label: 'Voice Assistant Satellite Entity',
      hint: 'assist_satellite.hearth_kiosk (blank = auto-detect by MAC)',
      domains: 'assist_satellite',
    ).buildHtml(ctx);

    return urlHtml +
        tokenHtml +
        satelliteHtml +
        _pinnedDevicesHtml(_pinnableDomains.join(','));
  }

  @override
  void registerHttpRoutes(PluginRouter router) {
    // GET entities — the live HA entity list (id + friendly name) shared by the
    // three web pickers: pinned devices, the voice satellite, and night mode.
    // An optional `?domains=a,b,c` query filters to those domains (pinned →
    // pinnable set, voice → `assist_satellite`); no param returns every entity
    // (night mode accepts any). `pinned` carries the currently-pinned ids so
    // the pinned picker can pre-check them. Only the backend can reach the live
    // HA service, so the browser fetches it from here rather than holding an HA
    // connection.
    router.get('entities', (req) async {
      final ha = req.readProvider(homeAssistantServiceProvider);
      final raw = req.raw.uri.queryParameters['domains'];
      final domains = (raw == null || raw.trim().isEmpty)
          ? null
          : raw.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toSet();
      await req.respondJson({
        'entities': pickerEntities(ha.entities.values, domains: domains),
        'pinned': req.config.pinnedEntityIds,
      });
    });

    // POST pinned — persist the selected entity ids into pinnedEntityIds via
    // the same notifier an on-device save would use.
    router.post('pinned', (req) async {
      final ids =
          (req.body['ids'] as List?)?.cast<String>() ?? const <String>[];
      await req.updateConfig((c) => c.copyWith(pinnedEntityIds: ids));
      await req.respondJson({'status': 'saved', 'count': ids.length});
    });
  }

  /// Entity domains offered in the pinned-device picker. Mirrors the on-device
  /// [EntityPickerDialog] so the two surfaces show the same set. Passed to the
  /// shared `entities` route as the pinned picker's `domains` filter.
  static const _pinnableDomains = {
    'light',
    'switch',
    'climate',
    'fan',
    'cover',
    'lock',
    'input_boolean',
  };

  /// Shapes the live HA entities into the `{id, name}` list the web pickers
  /// render: sorted by friendly name (matching [EntityPickerDialog]'s on-device
  /// ordering). When [domains] is given, only those entity domains are kept;
  /// when null, every entity is returned (night mode accepts any).
  @visibleForTesting
  static List<Map<String, String>> pickerEntities(
    Iterable<HaEntity> entities, {
    Set<String>? domains,
  }) {
    final list = entities
        .where((e) => domains == null || domains.contains(e.domain))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final e in list) {'id': e.entityId, 'name': e.name},
    ];
  }
}

/// Web pinned-device picker: a searchable checkbox list bound to
/// `pinnedEntityIds`. The container carries `data-config-path="pinnedEntityIds"`
/// as the web-parity ledger marker (see `web_parity_guard_test`); persistence
/// runs through the plugin's `pinned` route, not the generic config auto-save,
/// so the marker lives on the (non-input) `<div>` the auto-binder ignores.
/// [domains] is the comma-separated pinnable-domain filter passed to the shared
/// `entities` route (read from `data-domains` by the script below).
String _pinnedDevicesHtml(String domains) => '''
<div class="field" data-config-path="pinnedEntityIds" data-domains="$domains">
  <label>Pinned Devices</label>
  <input type="text" id="ha-pinned-search" placeholder="Search entities…" autocomplete="off">
  <div id="ha-pinned-list" style="margin-top:8px"></div>
  <div id="ha-pinned-status" style="font-size:11px;color:#666;margin-top:6px"></div>
</div>
<script>$_pinnedDevicesScript</script>
''';

const _pinnedDevicesScript = r'''
(function () {
  function init() {
    var list = document.getElementById('ha-pinned-list');
    var search = document.getElementById('ha-pinned-search');
    var status = document.getElementById('ha-pinned-status');
    if (!list) return;
    var all = [];
    var selected = new Set();
    var saveTimer = null;

    function save() {
      if (saveTimer) clearTimeout(saveTimer);
      saveTimer = setTimeout(function () {
        hearth.action('pinned', { ids: Array.from(selected) })
          .then(function () { status.textContent = selected.size + ' selected'; })
          .catch(function () { status.textContent = 'Save failed'; });
      }, 400);
    }

    function render() {
      var q = (search.value || '').toLowerCase();
      list.textContent = '';
      var shown = all.filter(function (e) {
        return e.name.toLowerCase().indexOf(q) >= 0 ||
               e.id.toLowerCase().indexOf(q) >= 0;
      });
      if (!shown.length) {
        var empty = document.createElement('div');
        empty.style.cssText = 'color:#666;font-style:italic;padding:8px 0';
        empty.textContent = all.length
          ? 'No matches.'
          : 'No entities available. Is Home Assistant connected?';
        list.appendChild(empty);
        return;
      }
      shown.forEach(function (e) {
        var row = document.createElement('label');
        row.style.cssText = 'display:flex;align-items:center;gap:10px;padding:8px 10px;background:#161618;border-radius:6px;margin-bottom:4px;cursor:pointer';
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.checked = selected.has(e.id);
        cb.addEventListener('change', function () {
          if (cb.checked) selected.add(e.id); else selected.delete(e.id);
          save();
        });
        var txt = document.createElement('div');
        var nm = document.createElement('div');
        nm.textContent = e.name;
        var id = document.createElement('div');
        id.textContent = e.id;
        id.style.cssText = 'font-size:11px;color:#777';
        txt.appendChild(nm);
        txt.appendChild(id);
        row.appendChild(cb);
        row.appendChild(txt);
        list.appendChild(row);
      });
    }

    search.addEventListener('input', render);
    status.textContent = 'Loading…';
    var field = document.querySelector('[data-config-path="pinnedEntityIds"]');
    var domains = (field && field.dataset.domains) || '';
    hearth.action('entities?domains=' + domains).then(function (data) {
      all = data.entities || [];
      selected = new Set(data.pinned || []);
      status.textContent = selected.size + ' selected';
      render();
    }).catch(function () {
      status.textContent = 'Failed to load entities';
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
''';

class _HomeAssistantPanel extends ConsumerWidget {
  const _HomeAssistantPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final ha = ref.watch(homeAssistantServiceProvider);

    // Dynamic voice satellite options from the live HA entity list.
    final assistEntities = ha.entities.values
        .where((e) => e.entityId.startsWith('assist_satellite.'))
        .toList()
      ..sort((a, b) => a.entityId.compareTo(b.entityId));
    final voiceOptions = <String, String>{
      '': "Auto-detect (match this Pi's MAC)",
      for (final e in assistEntities)
        e.entityId:
            '${e.name.isNotEmpty ? e.name : e.entityId} (${e.entityId})',
    };
    // If the saved value isn't in the live list (HA still loading, or
    // entity went away), include it so the dropdown doesn't crash on a
    // missing key.
    final current = config.voiceAssistantEntityId;
    if (current.isNotEmpty && !voiceOptions.containsKey(current)) {
      voiceOptions[current] = current;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'haUrl',
          label: 'Home Assistant URL',
          hint: 'http://192.168.1.x:8123',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'haToken',
          label: 'Long-Lived Access Token',
          hint: 'Paste your HA token',
        ).buildWidget(ref),
        SelectSettingField(
          configPath: 'voiceAssistantEntityId',
          label: 'Voice Assistant Satellite',
          options: voiceOptions,
        ).buildWidget(ref),
        const SizedBox(height: 16),
        _PinnedEntitiesRow(pinnedCount: config.pinnedEntityIds.length),
      ],
    );
  }
}

/// Pinned-entity row: shows the current count and an "Edit" button that
/// opens the shared [EntityPickerDialog]. The dialog itself writes the
/// new list back to HubConfig.
class _PinnedEntitiesRow extends ConsumerWidget {
  final int pinnedCount;
  const _PinnedEntitiesRow({required this.pinnedCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = pinnedCount == 0
        ? 'No devices selected'
        : '$pinnedCount device${pinnedCount == 1 ? "" : "s"}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pinned Devices',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices, color: Colors.white54),
            title: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              onPressed: () => showDialog<List<String>>(
                context: context,
                builder: (_) => const EntityPickerDialog(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF646cff),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
