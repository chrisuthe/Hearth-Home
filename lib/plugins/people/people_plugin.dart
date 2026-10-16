import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../config/person.dart';
import '../../services/home_assistant_service.dart';
import '../../services/people.dart';
import '../calendar/calendar_sources.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';
import 'people_settings_section.dart';

/// People plugin: the household registry that calendars and chore lists
/// belong to, each person optionally linked to a Home Assistant `person.*`
/// for an avatar and presence.
///
/// The registry is edited on the portal through the routes below, since the
/// `ListSection` HTML render is read-only. These routes change config only.
class PeoplePlugin extends HearthPlugin {
  @override
  String get id => 'hearth.people';

  @override
  String get name => 'People';

  @override
  IconData get icon => Icons.people_outline;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 44;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) => config.people.isNotEmpty
      ? PluginConfigStatus.configured
      : PluginConfigStatus.needsSetup;

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const PeopleSettingsSection();

  @override
  String buildSettingsHtml(WebContext ctx) {
    final haPicker = const HaEntityPickerField.form(
      formId: 'people-entity',
      label: 'Home Assistant person (blank: not linked)',
      hint: 'person.sam',
      domains: 'person',
    ).buildHtml(ctx);
    return _peopleHtml(haPicker);
  }

  /// Routes backing the portal's registry:
  ///   * GET    people      — each with resolved avatar and presence
  ///   * POST   people      — add one; name defaults from the linked entity
  ///   * PUT    people/:id  — name, colour, linked entity
  ///   * DELETE people/:id  — and clears it from lists and calendars
  ///   * POST   import      — a person per unlinked `person.*` entity
  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('people', (req) async {
      final ha = req.readProvider(homeAssistantServiceProvider);
      await req.respondJson({
        'palette': [for (final c in calendarPalette) calendarColorHex(c)],
        'people': [
          for (final p in req.config.people) personJson(p, req.config, ha),
        ],
      });
    });

    router.post('people', (req) async {
      final fields = _parseFields(req.body);
      if (fields.error != null) return req.respondError(400, fields.error!);
      final ha = req.readProvider(homeAssistantServiceProvider);
      final entityId = fields.entityId ?? '';
      final conflict = _linkConflict(req.config.people, entityId, null);
      if (conflict != null) return req.respondError(409, conflict);
      final name = fields.name?.isNotEmpty == true
          ? fields.name!
          : (entityId.isEmpty ? '' : (ha.entities[entityId]?.name ?? ''));
      if (name.isEmpty) return req.respondError(400, 'name is required');
      final person = Person(
        id: newPersonId(),
        name: name,
        color: fields.color ??
            nextFreePaletteColor([for (final p in req.config.people) p.color]),
        haPersonEntityId: entityId,
      );
      await req.updateConfig((c) => c.withPeople([...c.people, person]));
      await req.respondJson({'person': personJson(person, req.config, ha)});
    });

    router.put('people/:id', (req) async {
      final id = req.pathParams['id']!;
      final existing = personById(req.config.people, id);
      if (existing == null) return req.respondError(404, 'no person $id');
      final fields = _parseFields(req.body);
      if (fields.error != null) return req.respondError(400, fields.error!);
      if (fields.name != null && fields.name!.isEmpty) {
        return req.respondError(400, 'name must not be empty');
      }
      final entityId = fields.entityId;
      if (entityId != null) {
        final conflict = _linkConflict(req.config.people, entityId, id);
        if (conflict != null) return req.respondError(409, conflict);
      }
      final updated = existing.copyWith(
        name: fields.name,
        color: fields.color,
        haPersonEntityId: entityId,
      );
      await req.updateConfig((c) => c.withPeople([
            for (final p in c.people) p.id == id ? updated : p,
          ]));
      await req.respondJson({
        'person': personJson(updated, req.config,
            req.readProvider(homeAssistantServiceProvider)),
      });
    });

    router.delete('people/:id', (req) async {
      final id = req.pathParams['id']!;
      if (personById(req.config.people, id) == null) {
        return req.respondError(404, 'no person $id');
      }
      await req.updateConfig(
          (c) => c.withPeople(c.people.where((p) => p.id != id).toList()));
      await req.respondJson({'deleted': id});
    });

    router.post('import', (req) async {
      final ha = req.readProvider(homeAssistantServiceProvider);
      if (!ha.isConnected) {
        return req.respondError(503, "Can't reach Home Assistant");
      }
      final added =
          importablePeople(req.config.people, ha, nextFreePaletteColor);
      if (added.isNotEmpty) {
        await req.updateConfig((c) => c.withPeople([...c.people, ...added]));
      }
      await req.respondJson({
        'added': [for (final p in added) personJson(p, req.config, ha)],
      });
    });
  }

  /// Why [entityId] can't be linked to the person [selfId] (null for a new
  /// one): another person already links it. Null when it can.
  static String? _linkConflict(
          List<Person> people, String entityId, String? selfId) =>
      entityId.isNotEmpty &&
              people.any(
                  (p) => p.id != selfId && p.haPersonEntityId == entityId)
          ? '$entityId is already linked to someone'
          : null;

  /// The optional name, colour and linked entity of a POST or PUT body,
  /// trimmed; null where absent.
  static ({String? name, int? color, String? entityId, String? error})
      _parseFields(Map<String, dynamic> body) {
    ({String? name, int? color, String? entityId, String? error}) fail(
            String error) =>
        (name: null, color: null, entityId: null, error: error);

    for (final key in ['name', 'haPersonEntityId']) {
      if (body[key] != null && body[key] is! String) {
        return fail('$key must be a string');
      }
    }
    final rawColor = body['color'];
    final color = rawColor == null ? null : parseCalendarColor(rawColor);
    if (rawColor != null && color == null) return fail('color must be #rrggbb');
    final entityId = (body['haPersonEntityId'] as String?)?.trim();
    if (entityId != null && entityId.isNotEmpty) {
      final invalid = validatePersonEntityId(entityId);
      if (invalid != null) return fail(invalid);
    }
    return (
      name: (body['name'] as String?)?.trim(),
      color: color,
      entityId: entityId,
      error: null,
    );
  }
}

/// A person as the portal sees them.
Map<String, dynamic> personJson(
  Person p,
  HubConfig config,
  HomeAssistantService ha,
) {
  final view = resolvePerson(p, config.haUrl, ha);
  return {
    'id': p.id,
    'name': p.name,
    'color': calendarColorHex(p.color),
    'initial': view.initial,
    'haPersonEntityId': p.haPersonEntityId,
    'avatarUrl': view.avatarUrl,
    'presence': view.presence,
    'status': personStatusLabel(p, view, config, ha),
  };
}

/// "Home Assistant · person.sam · Home"-style line for a person's link, as
/// both surfaces show it.
String personStatusLabel(
  Person p,
  PersonView view,
  HubConfig config,
  HomeAssistantService ha,
) {
  if (!p.isLinked) return 'Not linked to Home Assistant';
  final parts = [p.haPersonEntityId];
  if (config.haUrl.isEmpty || config.haToken.isEmpty) {
    parts.add('Home Assistant is not configured');
  } else if (!ha.isConnected) {
    parts.add("Can't reach Home Assistant");
  } else if (ha.entities[p.haPersonEntityId] == null) {
    parts.add('Not found in Home Assistant');
  } else if (view.presence != null) {
    parts.add(view.presence!);
  }
  return parts.join(' · ');
}

/// The portal's registry and its add/edit form. Loaded and changed through
/// this plugin's routes; `data-config-path="people"` on the container is the
/// parity-ledger marker (see web_parity_guard_test) and sits on a `<div>` the
/// auto-save binder ignores.
String _peopleHtml(String haPicker) => '''
<style>
  #people-panel .ppl-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #161618; border-radius: 6px;
    margin-bottom: 4px;
  }
  #people-panel .ppl-avatar {
    position: relative; width: 32px; height: 32px; flex: none;
  }
  #people-panel .ppl-avatar img, #people-panel .ppl-avatar span {
    width: 32px; height: 32px; border-radius: 50%; display: flex;
    align-items: center; justify-content: center; object-fit: cover;
    color: #fff; font-weight: 600;
  }
  #people-panel .ppl-dot {
    position: absolute; right: -1px; bottom: -1px; width: 11px; height: 11px;
    border-radius: 50%; border: 2px solid #161618;
  }
  #people-panel .ppl-text { flex: 1; min-width: 0; }
  #people-panel .ppl-sub { font-size: 11px; color: #777; }
  .ppl-btn {
    background: none; border: none; color: #646cff;
    font-size: 13px; cursor: pointer; padding: 4px 6px;
  }
  .ppl-del { color: #ef5350; }
  .ppl-hint { font-size: 12px; color: #888; padding: 4px 0; }
  .ppl-form {
    background: #161618; border: 1px solid #333; border-radius: 6px;
    padding: 12px; margin-bottom: 8px;
  }
  .ppl-form input[type="text"] { width: 100%; margin-bottom: 8px; }
  .ppl-form .ppl-actions {
    display: flex; gap: 8px; justify-content: flex-end; margin-top: 8px;
  }
  .ppl-form .ppl-save {
    background: #646cff; color: #fff; border: none; border-radius: 6px;
    padding: 8px 16px; font-size: 13px; cursor: pointer;
  }
  .ppl-form .ppl-cancel {
    background: none; color: #888; border: none; padding: 8px 12px;
    font-size: 13px; cursor: pointer;
  }
  .ppl-swatches { display: flex; gap: 8px; flex-wrap: wrap; margin: 6px 0; }
  .ppl-swatches button {
    width: 28px; height: 28px; border-radius: 50%; cursor: pointer;
    border: 2px solid transparent;
  }
  .ppl-swatches button.ppl-on { border-color: #fff; }
  .ppl-result { font-size: 13px; color: #ffab40; margin: 4px 0; }
</style>
<div class="field" data-config-path="people">
  <label>People</label>
  <div id="people-panel">Loading people…</div>
  <div style="margin-top:6px">
    <button type="button" class="ppl-btn" id="ppl-add">+ Add person</button>
    <button type="button" class="ppl-btn" id="ppl-import">Import from Home Assistant</button>
  </div>
  <div class="ppl-result" id="ppl-import-result"></div>

  <div class="ppl-form" id="ppl-form" hidden>
    <div class="ppl-hint" id="ppl-form-title"></div>
    <input type="text" id="ppl-name" placeholder="Name">
    $haPicker
    <div class="ppl-swatches" id="ppl-colors"></div>
    <div class="ppl-result" id="ppl-result"></div>
    <div class="ppl-actions">
      <button type="button" class="ppl-cancel" id="ppl-cancel">Cancel</button>
      <button type="button" class="ppl-save" id="ppl-save">Save</button>
    </div>
  </div>
  <div class="ppl-hint">Calendars and chore lists are assigned to people on the Calendar and Lists panels.</div>
</div>
<script>$_peopleScript</script>
''';

const _peopleScript = r'''
(function () {
  var PREFIX = '/api/plugin/hearth.people';
  var panel = document.getElementById('people-panel');
  if (!panel) return;
  var palette = [];
  var people = [];
  var editing = null;
  var picked = null;
  var DOTS = { Home: '#66bb6a', Away: '#9e9e9e' };

  function $(id) { return document.getElementById(id); }
  function elem(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function entityInput() { return $('haep-people-entity-input'); }

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

  function swatches() {
    var box = $('ppl-colors');
    box.textContent = '';
    var colors = palette.slice();
    if (picked && colors.indexOf(picked) < 0) colors.push(picked);
    colors.forEach(function (c) {
      var b = elem('button', c === picked ? 'ppl-on' : '');
      b.type = 'button';
      b.style.background = c;
      b.title = c;
      b.addEventListener('click', function () { picked = c; swatches(); });
      box.appendChild(b);
    });
  }

  function nextColor() {
    var used = people.map(function (p) { return p.color; });
    for (var i = 0; i < palette.length; i++) {
      if (used.indexOf(palette[i]) < 0) return palette[i];
    }
    return palette[people.length % palette.length];
  }

  function avatar(p) {
    var box = elem('div', 'ppl-avatar');
    var initial = elem('span', null, p.initial);
    initial.style.background = p.color;
    if (p.avatarUrl) {
      var img = document.createElement('img');
      img.src = p.avatarUrl;
      img.alt = '';
      img.addEventListener('error', function () { box.replaceChild(initial, img); });
      box.appendChild(img);
    } else {
      box.appendChild(initial);
    }
    if (p.presence) {
      var dot = elem('span', 'ppl-dot');
      dot.style.background = DOTS[p.presence] || '#ffb74d';
      dot.title = p.presence;
      box.appendChild(dot);
    }
    return box;
  }

  function render() {
    panel.textContent = '';
    if (!people.length) {
      panel.appendChild(elem('div', 'ppl-hint', 'No people yet.'));
      return;
    }
    people.forEach(function (p) {
      var row = elem('div', 'ppl-row');
      var txt = elem('div', 'ppl-text');
      txt.appendChild(elem('div', null, p.name));
      txt.appendChild(elem('div', 'ppl-sub', p.status));
      var edit = elem('button', 'ppl-btn', 'Edit');
      edit.type = 'button';
      edit.addEventListener('click', function () { open(p); });
      var del = elem('button', 'ppl-btn ppl-del', 'Delete');
      del.type = 'button';
      del.addEventListener('click', function () {
        if (!confirm('Remove ' + p.name + '? Their calendars and lists stay, unassigned.')) return;
        call('DELETE', 'people/' + encodeURIComponent(p.id)).then(load)
          .catch(function (e) { alert(e.message); });
      });
      row.appendChild(avatar(p));
      row.appendChild(txt);
      row.appendChild(edit);
      row.appendChild(del);
      panel.appendChild(row);
    });
  }

  function load() {
    return call('GET', 'people').then(function (d) {
      palette = d.palette || [];
      people = d.people || [];
      render();
    }).catch(function () { panel.textContent = 'Failed to load people.'; });
  }

  function close() { $('ppl-form').hidden = true; editing = null; }

  function open(p) {
    editing = p || null;
    picked = p ? p.color : nextColor();
    $('ppl-form-title').textContent = p ? 'Edit ' + p.name : 'Add person';
    $('ppl-name').value = p ? p.name : '';
    var entity = entityInput();
    if (entity) entity.value = p ? p.haPersonEntityId : '';
    $('ppl-result').textContent = '';
    $('ppl-save').textContent = p ? 'Save' : 'Add';
    swatches();
    $('ppl-form').hidden = false;
  }

  function save() {
    var entity = entityInput();
    var body = {
      name: $('ppl-name').value.trim(),
      color: picked,
      haPersonEntityId: entity ? entity.value.trim() : '',
    };
    var req = editing
      ? call('PUT', 'people/' + encodeURIComponent(editing.id), body)
      : call('POST', 'people', body);
    req.then(function () { close(); load(); })
      .catch(function (e) { $('ppl-result').textContent = e.message; });
  }

  function runImport() {
    $('ppl-import-result').textContent = 'Importing…';
    call('POST', 'import').then(function (d) {
      var n = (d.added || []).length;
      $('ppl-import-result').textContent = n
        ? 'Added ' + n + (n === 1 ? ' person.' : ' people.')
        : 'Everyone in Home Assistant is already here.';
      load();
    }).catch(function (e) { $('ppl-import-result').textContent = e.message; });
  }

  function init() {
    $('ppl-add').addEventListener('click', function () { open(null); });
    $('ppl-import').addEventListener('click', runImport);
    $('ppl-save').addEventListener('click', save);
    $('ppl-cancel').addEventListener('click', close);
    load();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
''';
