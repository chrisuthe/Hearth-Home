import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../screens/settings/photo_sources_section.dart';
import '../../services/immich_service.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Immich photo-server integration.
///
/// Owns the `immichUrl` + `immichApiKey` HubConfig fields, plus the
/// album / people / memories / smart-search source picker that drives the
/// ambient carousel (the `photoSources` HubConfig field). On-device the
/// picker is [PhotoSourcesSection]; on the web portal it is rendered by
/// [buildSettingsHtml] and backed by the `photo-sources` plugin routes.
class ImmichPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.immich';

  @override
  String get name => 'Immich';

  @override
  IconData get icon => Icons.photo_library;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 20;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.immichUrl.isEmpty || config.immichApiKey.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'immichUrl',
          label: 'Immich URL',
          hint: 'http://192.168.1.x:2283',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'immichApiKey',
          label: 'API Key',
          hint: 'Paste your Immich API key',
        ).buildWidget(ref),
        const SizedBox(height: 24),
        const PhotoSourcesSection(),
      ],
    );
  }

  // Web settings: URL + API key, then the photo-source picker. The picker is
  // driven by the `photo-sources` plugin routes below — it loads live album /
  // people lists (which the static HTML render can't reach) and persists the
  // chosen sources via updateConfig.
  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
          configPath: 'immichUrl',
          label: 'Immich URL',
          hint: 'http://192.168.1.x:2283',
        ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'immichApiKey',
          label: 'API Key',
          hint: 'Paste your Immich API key',
        ).buildHtml(ctx) +
        _photoSourcesHtml;
  }

  /// Routes backing the web photo-source picker:
  ///   * GET  photo-sources — live album/people lists (via readProvider) plus
  ///     the current selection, so the picker can hydrate.
  ///   * POST photo-sources — persist the chosen sources via updateConfig.
  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('photo-sources', (req) async {
      final immich = req.readProvider(immichServiceProvider);

      List<Map<String, dynamic>> albums = const [];
      String? albumsError;
      try {
        albums = (await immich.listAlbums())
            .map((a) =>
                {'id': a.id, 'name': a.name, 'assetCount': a.assetCount})
            .toList();
      } catch (_) {
        albumsError = "Couldn't load albums — check the Immich URL and key.";
      }

      List<Map<String, dynamic>> people = const [];
      String? peopleError;
      try {
        people = (await immich.listNamedPeople())
            .map((p) =>
                {'id': p.id, 'name': p.name, 'numberOfAssets': p.numberOfAssets})
            .toList();
      } catch (_) {
        peopleError = "Couldn't load people — check the Immich URL and key.";
      }

      await req.respondJson({
        'selected': req.config.photoSources.toJson(),
        'albums': albums,
        'albumsError': albumsError,
        'people': people,
        'peopleError': peopleError,
      });
    });

    router.post('photo-sources', (req) async {
      final next = PhotoSourcesConfig.fromJson(req.body);
      await req.updateConfig((c) => c.copyWith(photoSources: next));
      await req.respondJson({'status': 'saved'});
    });
  }
}

/// Self-contained HTML + JS for the web photo-source picker. No server-side
/// interpolation: the picker fetches its data and selection at runtime from
/// the `photo-sources` GET route and persists via the POST route, both reached
/// through `hearth.action` (which scopes to this plugin's prefix).
///
/// The hidden `data-config-path="photoSources"` marker satisfies the web
/// parity drift-guard; it carries `data-no-auto-save` so the scalar auto-save
/// binder ignores it (this object field is saved through the plugin route).
const _photoSourcesHtml = r'''
<style>
  #photo-sources-picker .ps-toggle {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 0; font-size: 14px; color: #e0e0e0; cursor: pointer;
  }
  #photo-sources-picker .ps-toggle input { accent-color: #646cff; }
  #photo-sources-picker .ps-indent { padding: 0 0 8px 28px; }
  #photo-sources-picker .ps-select, #photo-sources-picker .ps-text {
    width: 100%; padding: 10px 12px; background: #161618;
    border: 1px solid #333; border-radius: 6px; color: #e0e0e0;
    font-size: 14px; outline: none;
  }
  #photo-sources-picker .ps-select:focus,
  #photo-sources-picker .ps-text:focus { border-color: #646cff; }
  #photo-sources-picker .ps-chips { display: flex; flex-wrap: wrap; gap: 6px; }
  #photo-sources-picker .ps-chip {
    display: flex; align-items: center; gap: 6px;
    padding: 6px 10px; background: #161618; border: 1px solid #333;
    border-radius: 16px; font-size: 13px; cursor: pointer;
  }
  #photo-sources-picker .ps-chip input { accent-color: #646cff; }
  #photo-sources-picker .ps-hint { font-size: 12px; color: #888; padding: 2px 0 6px; }
  #photo-sources-picker .ps-hint.ps-warn { color: #fbbf24; }
</style>
<div class="field">
  <label>Photo sources</label>
  <div id="photo-sources-picker">Loading photo sources…</div>
  <input type="hidden" data-config-path="photoSources" data-no-auto-save>
</div>
<script>
(function () {
  var root = document.getElementById('photo-sources-picker');
  if (!root) return;
  var state = null;
  var albums = [];
  var albumsError = null;
  var people = [];
  var peopleError = null;
  var saveTimer = null;

  function commit() {
    hearth.action('photo-sources', state).catch(function (e) {
      console.error('photo-sources save failed', e);
    });
  }
  function scheduleCommit() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(commit, 500);
  }

  function toggle(labelText, checked, onChange) {
    var row = document.createElement('label');
    row.className = 'ps-toggle';
    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = checked;
    cb.addEventListener('change', function () { onChange(cb.checked); });
    var span = document.createElement('span');
    span.textContent = labelText;
    row.appendChild(cb);
    row.appendChild(span);
    return row;
  }

  function hint(text, warn) {
    var el = document.createElement('div');
    el.className = 'ps-hint' + (warn ? ' ps-warn' : '');
    el.textContent = text;
    return el;
  }

  function albumDropdown() {
    if (albumsError) return hint(albumsError, true);
    var wrap = document.createElement('div');
    wrap.className = 'ps-indent';
    var sel = document.createElement('select');
    sel.className = 'ps-select';
    var none = document.createElement('option');
    none.value = '';
    none.textContent = '— pick one —';
    sel.appendChild(none);
    var found = state.albumId === '';
    albums.forEach(function (a) {
      var opt = document.createElement('option');
      opt.value = a.id;
      opt.textContent = a.name + ' (' + a.assetCount + ')';
      if (a.id === state.albumId) { opt.selected = true; found = true; }
      sel.appendChild(opt);
    });
    if (!found) sel.value = '';
    sel.addEventListener('change', function () {
      state.albumId = sel.value;
      commit();
      render();
    });
    wrap.appendChild(sel);
    return wrap;
  }

  function peopleChips() {
    if (peopleError) return hint(peopleError, true);
    if (!people.length) {
      return hint('No named people found in Immich. Tag faces in Immich first.', false);
    }
    var wrap = document.createElement('div');
    wrap.className = 'ps-indent ps-chips';
    people.forEach(function (p) {
      var chip = document.createElement('label');
      chip.className = 'ps-chip';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = state.personIds.indexOf(p.id) !== -1;
      cb.addEventListener('change', function () {
        var idx = state.personIds.indexOf(p.id);
        if (cb.checked) { if (idx === -1) state.personIds.push(p.id); }
        else if (idx !== -1) { state.personIds.splice(idx, 1); }
        commit();
      });
      var span = document.createElement('span');
      span.textContent = p.name + ' (' + p.numberOfAssets + ')';
      chip.appendChild(cb);
      chip.appendChild(span);
      wrap.appendChild(chip);
    });
    return wrap;
  }

  function smartSearchInput() {
    var wrap = document.createElement('div');
    wrap.className = 'ps-indent';
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'ps-text';
    input.value = state.smartSearchQuery;
    input.placeholder = 'e.g. beach, sunset, autumn leaves';
    input.addEventListener('input', function () {
      state.smartSearchQuery = input.value;
      scheduleCommit();
    });
    wrap.appendChild(input);
    wrap.appendChild(hint(
      "Works best for visual concepts like 'beach' or 'sunset' — searches understand image content, not filenames.",
      false));
    return wrap;
  }

  function render() {
    root.textContent = '';
    root.appendChild(toggle('Memories ("On This Day")', state.memoriesEnabled,
      function (v) { state.memoriesEnabled = v; commit(); }));

    root.appendChild(toggle('Album', state.albumEnabled,
      function (v) { state.albumEnabled = v; commit(); render(); }));
    if (state.albumEnabled) {
      root.appendChild(albumDropdown());
      if (!albumsError && state.albumId === '') {
        root.appendChild(hint('Pick an album.', true));
      }
    }

    root.appendChild(toggle('People', state.peopleEnabled,
      function (v) { state.peopleEnabled = v; commit(); render(); }));
    if (state.peopleEnabled) {
      root.appendChild(peopleChips());
      if (!peopleError && people.length && !state.personIds.length) {
        root.appendChild(hint('Pick at least one person.', true));
      }
    }

    root.appendChild(toggle('Smart search', state.smartSearchEnabled,
      function (v) { state.smartSearchEnabled = v; commit(); render(); }));
    if (state.smartSearchEnabled) {
      root.appendChild(smartSearchInput());
      if (state.smartSearchQuery === '') {
        root.appendChild(hint('Enter a query.', true));
      }
    }
  }

  function load() {
    hearth.action('photo-sources').then(function (data) {
      state = data.selected || {};
      if (state.memoriesEnabled === undefined) state.memoriesEnabled = true;
      if (state.albumEnabled === undefined) state.albumEnabled = false;
      if (state.albumId === undefined) state.albumId = '';
      if (state.peopleEnabled === undefined) state.peopleEnabled = false;
      if (!Array.isArray(state.personIds)) state.personIds = [];
      if (state.smartSearchEnabled === undefined) state.smartSearchEnabled = false;
      if (state.smartSearchQuery === undefined) state.smartSearchQuery = '';
      albums = data.albums || [];
      albumsError = data.albumsError;
      people = data.people || [];
      peopleError = data.peopleError;
      render();
    }).catch(function (e) {
      root.textContent = 'Failed to load photo sources.';
      console.error(e);
    });
  }

  // hearth.js is loaded after this panel fragment, so defer until the page is
  // fully parsed (DOMContentLoaded) before reaching for window.hearth.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }
})();
</script>
''';
