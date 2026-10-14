import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../modules/calendar/ics_calendar_source.dart';
import '../../modules/calendar/models.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';
import 'calendar_settings_section.dart';
import 'calendar_sources.dart';

/// Calendar plugin: the Home Assistant calendars and ICS URLs the Calendar
/// module shows, plus its refresh interval, idle glance and default view.
///
/// The source list is edited on the portal through the routes below, since
/// the `ListSection` HTML render is read-only. Read-only toward HA and the
/// feeds: these routes change config only.
class CalendarPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.calendar';

  @override
  String get name => 'Calendar';

  @override
  IconData get icon => Icons.calendar_month;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 45;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) =>
      config.calendarSources.any((s) => s.enabled)
          ? PluginConfigStatus.configured
          : PluginConfigStatus.needsSetup;

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const CalendarSettingsSection();

  @override
  String buildSettingsHtml(WebContext ctx) {
    final haPicker = const HaEntityPickerField.form(
      formId: 'calendar-entity',
      label: 'Calendar entity',
      hint: 'calendar.family',
      domains: 'calendar',
    ).buildHtml(ctx);
    return _sourcesHtml(haPicker) +
        calendarPollField.buildHtml(ctx) +
        calendarGlanceField.buildHtml(ctx) +
        calendarViewField.buildHtml(ctx);
  }

  /// Routes backing the portal's source list:
  ///   * GET    sources       — the sources with live status (URLs left out)
  ///   * POST   sources       — add one; HA name/colour default from HA
  ///   * PUT    sources/:id   — name, colour, enabled
  ///   * DELETE sources/:id
  ///   * POST   test          — one fetch of an ICS URL
  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('sources', (req) async {
      await req.respondJson({
        'palette': [for (final c in calendarPalette) calendarColorHex(c)],
        'sources': [
          for (final s in req.config.calendarSources)
            _sourceJson(s, req.config,
                s.enabled ? calendarSourceStatus(req.readProvider, s.id) : null),
        ],
      });
    });

    router.post('sources', (req) async {
      final body = req.body;
      final sources = req.config.calendarSources;
      final rawColor = body['color'];
      final color = rawColor == null ? null : parseCalendarColor(rawColor);
      if (rawColor != null && color == null) {
        return req.respondError(400, 'color must be #rrggbb');
      }
      final enabled = body['enabled'];
      if (enabled != null && enabled is! bool) {
        return req.respondError(400, 'enabled must be true or false');
      }
      final name = (body['name'] as Object?) is String
          ? (body['name'] as String).trim()
          : '';

      final CalendarSource source;
      switch (body['kind']) {
        case 'ha':
          final entityId = body['entityId'];
          final invalid = entityId is String
              ? validateCalendarEntityId(entityId)
              : 'entityId is required';
          if (invalid != null) return req.respondError(400, invalid);
          entityId as String;
          final id = haSourceId(entityId);
          if (sources.any((s) => s.id == id)) {
            return req.respondError(409, '$entityId is already added');
          }
          ({String? name, int? color}) defaults = (name: null, color: null);
          if (name.isEmpty || color == null) {
            defaults = await req.readProvider(calendarHaDefaultsProvider)(
                entityId);
          }
          source = CalendarSource(
            id: id,
            kind: CalendarSourceKind.ha,
            entityId: entityId,
            name: name.isNotEmpty ? name : (defaults.name ?? entityId),
            color: color ?? defaults.color ?? nextPaletteColor(sources),
            enabled: enabled as bool? ?? true,
          );
        case 'ics':
          final url = body['url'];
          final invalid =
              url is String ? validateIcsUrl(url) : 'url is required';
          if (invalid != null) return req.respondError(400, invalid);
          url as String;
          source = CalendarSource(
            id: newIcsSourceId(),
            kind: CalendarSourceKind.ics,
            url: url.trim(),
            name: name.isNotEmpty ? name : icsFallbackName(url),
            color: color ?? nextPaletteColor(sources),
            enabled: enabled as bool? ?? true,
          );
        default:
          return req.respondError(400, 'kind must be ha or ics');
      }
      await req.updateConfig(
          (c) => c.copyWith(calendarSources: [...c.calendarSources, source]));
      await req.respondJson({'source': _sourceJson(source, req.config, null)});
    });

    router.put('sources/:id', (req) async {
      final id = req.pathParams['id']!;
      final existing =
          req.config.calendarSources.where((s) => s.id == id).firstOrNull;
      if (existing == null) return req.respondError(404, 'no source $id');
      final body = req.body;
      final fixed = {
        'kind': existing.kind.name,
        'entityId': existing.entityId,
        'url': existing.url,
      };
      for (final key in fixed.keys) {
        if (body.containsKey(key) && body[key] != fixed[key]) {
          return req.respondError(
              400, "$key can't change; delete the calendar and add it again");
        }
      }
      final name = body['name'];
      if (name != null && (name is! String || name.trim().isEmpty)) {
        return req.respondError(400, 'name must not be empty');
      }
      final rawColor = body['color'];
      final color = rawColor == null ? null : parseCalendarColor(rawColor);
      if (rawColor != null && color == null) {
        return req.respondError(400, 'color must be #rrggbb');
      }
      final enabled = body['enabled'];
      if (enabled != null && enabled is! bool) {
        return req.respondError(400, 'enabled must be true or false');
      }
      final updated = existing.copyWith(
        name: (name as String?)?.trim(),
        color: color,
        enabled: enabled as bool?,
      );
      await req.updateConfig((c) => c.copyWith(calendarSources: [
            for (final s in c.calendarSources) s.id == id ? updated : s,
          ]));
      await req.respondJson({'source': _sourceJson(updated, req.config, null)});
    });

    router.delete('sources/:id', (req) async {
      final id = req.pathParams['id']!;
      if (!req.config.calendarSources.any((s) => s.id == id)) {
        return req.respondError(404, 'no source $id');
      }
      await req.updateConfig((c) => c.copyWith(
          calendarSources:
              c.calendarSources.where((s) => s.id != id).toList()));
      await req.respondJson({'deleted': id});
    });

    router.post('test', (req) async {
      final url = req.body['url'];
      final invalid = url is String ? validateIcsUrl(url) : 'url is required';
      if (invalid != null) return req.respondError(400, invalid);
      try {
        final probe =
            await req.readProvider(calendarIcsProbeProvider)(url as String);
        final color = parseCalendarColor(probe.color);
        await req.respondJson({
          'ok': true,
          'name': probe.name,
          'color': color == null ? null : calendarColorHex(color),
          'eventCount': probe.eventCount,
        });
      } on IcsProbeException catch (e) {
        await req.respondJson({'ok': false, 'error': e.message});
      }
    });
  }

  /// A source as the portal sees it. The URL is left out: it can carry a
  /// secret, and the portal never needs it back.
  static Map<String, dynamic> _sourceJson(
          CalendarSource s, HubConfig config, SourceEvents? status) =>
      {
        'id': s.id,
        'kind': s.kind.name,
        'kindLabel': calendarKindLabel(s.kind),
        'entityId': s.entityId,
        'name': s.name,
        'color': calendarColorHex(s.color),
        'enabled': s.enabled,
        'state': s.enabled ? (status?.status.name ?? 'loading') : 'off',
        'status': calendarStatusLabel(status,
            enabled: s.enabled, use24Hour: config.use24HourClock),
      };
}

/// The portal's source list and its two add forms. The list is loaded and
/// changed through this plugin's routes; `data-config-path="calendarSources"`
/// on the container is the parity-ledger marker (see web_parity_guard_test)
/// and sits on a `<div>` the auto-save binder ignores.
String _sourcesHtml(String haPicker) => '''
<style>
  #calendar-panel .cal-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #161618; border-radius: 6px;
    margin-bottom: 4px;
  }
  #calendar-panel .cal-swatch {
    width: 14px; height: 14px; border-radius: 50%; flex: none;
  }
  #calendar-panel .cal-text { flex: 1; min-width: 0; }
  #calendar-panel .cal-sub { font-size: 11px; color: #777; }
  #calendar-panel .cal-sub.cal-bad { color: #ffab40; }
  #calendar-panel .cal-btn {
    background: none; border: none; color: #646cff;
    font-size: 13px; cursor: pointer; padding: 4px 6px;
  }
  #calendar-panel .cal-del { color: #ef5350; }
  #calendar-panel .cal-hint { font-size: 12px; color: #888; padding: 4px 0; }
  .cal-form {
    background: #161618; border: 1px solid #333; border-radius: 6px;
    padding: 12px; margin-bottom: 8px;
  }
  .cal-form input[type="text"], .cal-form input[type="password"] {
    width: 100%; margin-bottom: 8px;
  }
  .cal-form .cal-actions {
    display: flex; gap: 8px; justify-content: flex-end; margin-top: 8px;
  }
  .cal-form .cal-save {
    background: #646cff; color: #fff; border: none; border-radius: 6px;
    padding: 8px 16px; font-size: 13px; cursor: pointer;
  }
  .cal-form .cal-cancel {
    background: none; color: #888; border: none; padding: 8px 12px;
    font-size: 13px; cursor: pointer;
  }
  .cal-swatches { display: flex; gap: 8px; flex-wrap: wrap; margin: 6px 0; }
  .cal-swatches button {
    width: 28px; height: 28px; border-radius: 50%; cursor: pointer;
    border: 2px solid transparent;
  }
  .cal-swatches button.cal-on { border-color: #fff; }
  .cal-result { font-size: 13px; color: #bbb; margin: 4px 0; }
  .cal-result.cal-bad { color: #ffab40; }
</style>
<div class="field" data-config-path="calendarSources">
  <label>Calendars</label>
  <div id="calendar-panel">Loading calendars…</div>
  <div style="margin-top:6px">
    <button type="button" class="cal-btn" id="cal-add-ha"
            style="background:none;border:none;color:#646cff;cursor:pointer">+ Home Assistant calendar</button>
    <button type="button" class="cal-btn" id="cal-add-ics"
            style="background:none;border:none;color:#646cff;cursor:pointer">+ ICS URL</button>
  </div>

  <div class="cal-form" id="cal-ha-form" hidden>
    $haPicker
    <input type="text" id="cal-ha-name" placeholder="Name (blank: the name in Home Assistant)">
    <div class="cal-hint">Colour (none picked: the colour in Home Assistant, else the next free one)</div>
    <div class="cal-swatches" id="cal-ha-colors"></div>
    <div class="cal-result" id="cal-ha-result"></div>
    <div class="cal-actions">
      <button type="button" class="cal-cancel" data-cal-close>Cancel</button>
      <button type="button" class="cal-save" id="cal-ha-save">Add</button>
    </div>
  </div>

  <div class="cal-form" id="cal-ics-form" hidden>
    <input type="password" id="cal-ics-url" autocomplete="off"
           placeholder="https:// or webcal://… (kept private)">
    <div class="cal-result" id="cal-ics-result"></div>
    <input type="text" id="cal-ics-name" placeholder="Name">
    <div class="cal-swatches" id="cal-ics-colors"></div>
    <div class="cal-actions">
      <button type="button" class="cal-cancel" data-cal-close>Cancel</button>
      <button type="button" class="cal-save" id="cal-ics-save">Test</button>
    </div>
  </div>

  <div class="cal-form" id="cal-edit-form" hidden>
    <div class="cal-hint" id="cal-edit-what"></div>
    <div class="cal-hint">To change the calendar itself, delete it and add it again.</div>
    <input type="text" id="cal-edit-name" placeholder="Name">
    <div class="cal-swatches" id="cal-edit-colors"></div>
    <label style="display:flex;gap:8px;align-items:center;margin-top:6px">
      <input type="checkbox" id="cal-edit-enabled"> Enabled
    </label>
    <div class="cal-result" id="cal-edit-result"></div>
    <div class="cal-actions">
      <button type="button" class="cal-cancel" data-cal-close>Cancel</button>
      <button type="button" class="cal-save" id="cal-edit-save">Save</button>
    </div>
  </div>
</div>
<script>$_sourcesScript</script>
''';

const _sourcesScript = r'''
(function () {
  var PREFIX = '/api/plugin/hearth.calendar';
  var list = document.getElementById('calendar-panel');
  if (!list) return;
  var palette = [];
  var sources = [];
  var editing = null;
  var picked = { ha: null, ics: null, edit: null };
  var tested = null;

  function $(id) { return document.getElementById(id); }
  function elem(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function call(method, path, body) {
    return fetch(PREFIX + '/' + path, {
      method: method,
      headers: {
        'Authorization': 'Bearer ' + (window.__HEARTH_BEARER__ || ''),
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    }).then(function (r) {
      return r.json().then(function (d) {
        if (!r.ok) throw new Error(d.error || ('HTTP ' + r.status));
        return d;
      });
    });
  }

  function swatches(key, allowNone) {
    var box = $('cal-' + key + '-colors');
    box.textContent = '';
    var colors = palette.slice();
    if (picked[key] && colors.indexOf(picked[key]) < 0) colors.push(picked[key]);
    colors.forEach(function (c) {
      var b = elem('button', c === picked[key] ? 'cal-on' : '');
      b.type = 'button';
      b.style.background = c;
      b.title = c;
      b.addEventListener('click', function () {
        picked[key] = (allowNone && picked[key] === c) ? null : c;
        swatches(key, allowNone);
      });
      box.appendChild(b);
    });
    var custom = document.createElement('input');
    custom.type = 'color';
    custom.value = picked[key] || palette[0] || '#646cff';
    custom.addEventListener('change', function () {
      picked[key] = custom.value;
      swatches(key, allowNone);
    });
    box.appendChild(custom);
  }

  function nextColor() {
    var used = sources.map(function (s) { return s.color; });
    for (var i = 0; i < palette.length; i++) {
      if (used.indexOf(palette[i]) < 0) return palette[i];
    }
    return palette[sources.length % palette.length];
  }

  function closeForms() {
    ['cal-ha-form', 'cal-ics-form', 'cal-edit-form'].forEach(function (id) {
      $(id).hidden = true;
    });
    editing = null;
  }

  function result(id, text, bad) {
    var r = $(id);
    r.textContent = text || '';
    r.className = 'cal-result' + (bad ? ' cal-bad' : '');
  }

  function render() {
    list.textContent = '';
    if (!sources.length) {
      list.appendChild(elem('div', 'cal-hint', 'No calendars yet.'));
      return;
    }
    sources.forEach(function (s) {
      var row = elem('div', 'cal-row');
      var sw = elem('span', 'cal-swatch');
      sw.style.background = s.color;
      var txt = elem('div', 'cal-text');
      txt.appendChild(elem('div', null, s.name));
      var bad = s.state === 'error' || s.state === 'stale';
      txt.appendChild(elem('div', 'cal-sub' + (bad ? ' cal-bad' : ''),
        s.kindLabel + ' · ' + s.status));
      var edit = elem('button', 'cal-btn', 'Edit');
      edit.type = 'button';
      edit.addEventListener('click', function () { openEdit(s); });
      var del = elem('button', 'cal-btn cal-del', 'Delete');
      del.type = 'button';
      del.addEventListener('click', function () {
        if (!confirm('Remove ' + s.name + '?')) return;
        call('DELETE', 'sources/' + encodeURIComponent(s.id)).then(load)
          .catch(function (e) { alert(e.message); });
      });
      row.appendChild(sw);
      row.appendChild(txt);
      row.appendChild(edit);
      row.appendChild(del);
      list.appendChild(row);
    });
  }

  function load() {
    return call('GET', 'sources').then(function (d) {
      palette = d.palette || [];
      sources = d.sources || [];
      render();
    }).catch(function () { list.textContent = 'Failed to load calendars.'; });
  }

  function openHa() {
    closeForms();
    picked.ha = null;
    $('cal-ha-name').value = '';
    var entity = $('haep-calendar-entity-input');
    if (entity) entity.value = '';
    result('cal-ha-result', '');
    swatches('ha', true);
    $('cal-ha-form').hidden = false;
  }

  function saveHa() {
    var entity = $('haep-calendar-entity-input');
    var body = {
      kind: 'ha',
      entityId: entity ? entity.value.trim() : '',
      name: $('cal-ha-name').value.trim(),
    };
    if (picked.ha) body.color = picked.ha;
    call('POST', 'sources', body).then(function () {
      closeForms();
      load();
    }).catch(function (e) { result('cal-ha-result', e.message, true); });
  }

  function openIcs() {
    closeForms();
    tested = null;
    picked.ics = nextColor();
    $('cal-ics-url').value = '';
    $('cal-ics-name').value = '';
    result('cal-ics-result', '');
    $('cal-ics-save').textContent = 'Test';
    swatches('ics', false);
    $('cal-ics-form').hidden = false;
  }

  function saveIcs() {
    var url = $('cal-ics-url').value.trim();
    if (!url) return;
    if (tested !== url) {
      result('cal-ics-result', 'Fetching…');
      call('POST', 'test', { url: url }).then(function (d) {
        tested = url;
        $('cal-ics-save').textContent = 'Add';
        if (!d.ok) { result('cal-ics-result', d.error, true); return; }
        result('cal-ics-result', (d.name ? '“' + d.name + '”' : 'Calendar') +
          ' · ' + d.eventCount + (d.eventCount === 1 ? ' event' : ' events'));
        if (!$('cal-ics-name').value.trim() && d.name) $('cal-ics-name').value = d.name;
        if (d.color) { picked.ics = d.color; swatches('ics', false); }
      }).catch(function (e) { result('cal-ics-result', e.message, true); });
      return;
    }
    call('POST', 'sources', {
      kind: 'ics', url: url, name: $('cal-ics-name').value.trim(),
      color: picked.ics,
    }).then(function () {
      closeForms();
      load();
    }).catch(function (e) { result('cal-ics-result', e.message, true); });
  }

  function openEdit(s) {
    closeForms();
    editing = s;
    picked.edit = s.color;
    $('cal-edit-what').textContent = s.kind === 'ha'
      ? 'Home Assistant · ' + s.entityId : 'ICS feed';
    $('cal-edit-name').value = s.name;
    $('cal-edit-enabled').checked = s.enabled;
    result('cal-edit-result', '');
    swatches('edit', false);
    $('cal-edit-form').hidden = false;
  }

  function saveEdit() {
    if (!editing) return;
    call('PUT', 'sources/' + encodeURIComponent(editing.id), {
      name: $('cal-edit-name').value.trim(),
      color: picked.edit,
      enabled: $('cal-edit-enabled').checked,
    }).then(function () {
      closeForms();
      load();
    }).catch(function (e) { result('cal-edit-result', e.message, true); });
  }

  function init() {
    $('cal-add-ha').addEventListener('click', openHa);
    $('cal-add-ics').addEventListener('click', openIcs);
    $('cal-ha-save').addEventListener('click', saveHa);
    $('cal-ics-save').addEventListener('click', saveIcs);
    $('cal-edit-save').addEventListener('click', saveEdit);
    $('cal-ics-url').addEventListener('input', function () {
      $('cal-ics-save').textContent = 'Test';
    });
    document.querySelectorAll('[data-cal-close]').forEach(function (b) {
      b.addEventListener('click', closeForms);
    });
    load();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
''';
