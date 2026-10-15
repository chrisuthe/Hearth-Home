import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../modules/lists/models.dart';
import '../../services/home_assistant_service.dart';
import '../calendar/calendar_sources.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';
import 'lists_settings_section.dart';
import 'todo_lists.dart';

/// Lists plugin: the Home Assistant to-do lists Hearth shows, who each
/// belongs to (which makes it a chore list), and the idle chore glance.
///
/// The list is edited on the portal through the routes below, since the
/// `ListSection` HTML render is read-only. These routes change config only.
class ListsPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.lists';

  @override
  String get name => 'Lists';

  @override
  IconData get icon => Icons.checklist;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 46;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) => config.todoLists.isNotEmpty
      ? PluginConfigStatus.configured
      : PluginConfigStatus.needsSetup;

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const ListsSettingsSection();

  @override
  String buildSettingsHtml(WebContext ctx) {
    final haPicker = const HaEntityPickerField.form(
      formId: 'lists-entity',
      label: 'To-do entity',
      hint: 'todo.groceries',
      domains: 'todo',
    ).buildHtml(ctx);
    return _listsHtml(haPicker) + todoChoreGlanceField.buildHtml(ctx);
  }

  /// Routes backing the portal's list:
  ///   * GET    lists              — the lists with live status and features
  ///   * POST   lists              — add one; name defaults from HA
  ///   * PUT    lists/:entityId    — name, colour, person
  ///   * DELETE lists/:entityId
  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('lists', (req) async {
      final ha = req.readProvider(homeAssistantServiceProvider);
      await req.respondJson({
        'palette': [for (final c in calendarPalette) calendarColorHex(c)],
        'lists': [
          for (final l in req.config.todoLists) _listJson(l, req.config, ha),
        ],
      });
    });

    router.post('lists', (req) async {
      final body = req.body;
      final entityId = body['entityId'];
      final invalid = entityId is String
          ? validateTodoEntityId(entityId)
          : 'entityId is required';
      if (invalid != null) return req.respondError(400, invalid);
      entityId as String;
      if (req.config.todoLists.any((l) => l.entityId == entityId)) {
        return req.respondError(409, '$entityId is already added');
      }
      final fields = _parseFields(body);
      if (fields.error != null) return req.respondError(400, fields.error!);

      final ha = req.readProvider(homeAssistantServiceProvider);
      final friendly =
          ha.entities[entityId]?.attributes['friendly_name'] as String?;
      final list = TodoListConfig(
        entityId: entityId,
        name: fields.name?.isNotEmpty == true
            ? fields.name!
            : (friendly ?? entityId),
        color:
            fields.color ??
            nextFreePaletteColor([
              for (final l in req.config.todoLists) l.color,
            ]),
        person: fields.person ?? '',
      );
      await req.updateConfig(
        (c) => c.copyWith(todoLists: [...c.todoLists, list]),
      );
      await req.respondJson({'list': _listJson(list, req.config, ha)});
    });

    router.put('lists/:entityId', (req) async {
      final entityId = req.pathParams['entityId']!;
      final existing = req.config.todoLists
          .where((l) => l.entityId == entityId)
          .firstOrNull;
      if (existing == null) return req.respondError(404, 'no list $entityId');
      final body = req.body;
      if (body.containsKey('entityId') && body['entityId'] != entityId) {
        return req.respondError(
          400,
          "entityId can't change; delete the list and add it again",
        );
      }
      final fields = _parseFields(body);
      if (fields.error != null) return req.respondError(400, fields.error!);
      if (fields.name != null && fields.name!.isEmpty) {
        return req.respondError(400, 'name must not be empty');
      }
      final updated = existing.copyWith(
        name: fields.name,
        color: fields.color,
        person: fields.person,
      );
      await req.updateConfig(
        (c) => c.copyWith(
          todoLists: [
            for (final l in c.todoLists) l.entityId == entityId ? updated : l,
          ],
        ),
      );
      await req.respondJson({
        'list': _listJson(
          updated,
          req.config,
          req.readProvider(homeAssistantServiceProvider),
        ),
      });
    });

    router.delete('lists/:entityId', (req) async {
      final entityId = req.pathParams['entityId']!;
      if (!req.config.todoLists.any((l) => l.entityId == entityId)) {
        return req.respondError(404, 'no list $entityId');
      }
      await req.updateConfig(
        (c) => c.copyWith(
          todoLists: c.todoLists.where((l) => l.entityId != entityId).toList(),
        ),
      );
      await req.respondJson({'deleted': entityId});
    });
  }

  /// The optional name, colour and person of a POST or PUT body, trimmed;
  /// null where absent.
  static ({String? name, int? color, String? person, String? error})
  _parseFields(Map<String, dynamic> body) {
    String? text(String key) {
      final v = body[key];
      return v is String ? v.trim() : null;
    }

    for (final key in ['name', 'person']) {
      if (body[key] != null && body[key] is! String) {
        return (
          name: null,
          color: null,
          person: null,
          error: '$key must be a string',
        );
      }
    }
    final rawColor = body['color'];
    final color = rawColor == null ? null : parseCalendarColor(rawColor);
    if (rawColor != null && color == null) {
      return (
        name: null,
        color: null,
        person: null,
        error: 'color must be #rrggbb',
      );
    }
    return (
      name: text('name'),
      color: color,
      person: text('person'),
      error: null,
    );
  }

  static Map<String, dynamic> _listJson(
    TodoListConfig l,
    HubConfig config,
    HomeAssistantService ha,
  ) {
    final status = todoListStatus(config, ha, l.entityId);
    return {
      'entityId': l.entityId,
      'name': l.name,
      'color': calendarColorHex(l.color),
      'person': l.person,
      'kindLabel': todoListKindLabel(l),
      'status': status.label,
      'bad': status.bad,
      'features': todoFeaturesLabel(TodoFeatures.of(ha.entities[l.entityId])),
    };
  }
}

/// The portal's list and its add and edit forms. The list is loaded and
/// changed through this plugin's routes; `data-config-path="todoLists"` on
/// the container is the parity-ledger marker (see web_parity_guard_test) and
/// sits on a `<div>` the auto-save binder ignores.
String _listsHtml(String haPicker) =>
    '''
<style>
  #lists-panel .lst-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #161618; border-radius: 6px;
    margin-bottom: 4px;
  }
  #lists-panel .lst-swatch {
    width: 14px; height: 14px; border-radius: 50%; flex: none;
  }
  #lists-panel .lst-text { flex: 1; min-width: 0; }
  #lists-panel .lst-sub { font-size: 11px; color: #777; }
  #lists-panel .lst-sub.lst-bad { color: #ffab40; }
  .lst-btn {
    background: none; border: none; color: #646cff;
    font-size: 13px; cursor: pointer; padding: 4px 6px;
  }
  .lst-del { color: #ef5350; }
  .lst-hint { font-size: 12px; color: #888; padding: 4px 0; }
  .lst-form {
    background: #161618; border: 1px solid #333; border-radius: 6px;
    padding: 12px; margin-bottom: 8px;
  }
  .lst-form input[type="text"] { width: 100%; margin-bottom: 8px; }
  .lst-form .lst-actions {
    display: flex; gap: 8px; justify-content: flex-end; margin-top: 8px;
  }
  .lst-form .lst-save {
    background: #646cff; color: #fff; border: none; border-radius: 6px;
    padding: 8px 16px; font-size: 13px; cursor: pointer;
  }
  .lst-form .lst-cancel {
    background: none; color: #888; border: none; padding: 8px 12px;
    font-size: 13px; cursor: pointer;
  }
  .lst-swatches { display: flex; gap: 8px; flex-wrap: wrap; margin: 6px 0; }
  .lst-swatches button {
    width: 28px; height: 28px; border-radius: 50%; cursor: pointer;
    border: 2px solid transparent;
  }
  .lst-swatches button.lst-on { border-color: #fff; }
  .lst-result { font-size: 13px; color: #ffab40; margin: 4px 0; }
</style>
<div class="field" data-config-path="todoLists">
  <label>Lists</label>
  <div id="lists-panel">Loading lists…</div>
  <div style="margin-top:6px">
    <button type="button" class="lst-btn" id="lst-add">+ Add list</button>
  </div>

  <div class="lst-form" id="lst-add-form" hidden>
    $haPicker
    <input type="text" id="lst-add-name" placeholder="Name (blank: the name in Home Assistant)">
    <input type="text" id="lst-add-person" placeholder="Person (blank for a plain list)">
    <div class="lst-swatches" id="lst-add-colors"></div>
    <div class="lst-result" id="lst-add-result"></div>
    <div class="lst-actions">
      <button type="button" class="lst-cancel" data-lst-close>Cancel</button>
      <button type="button" class="lst-save" id="lst-add-save">Add</button>
    </div>
  </div>

  <div class="lst-form" id="lst-edit-form" hidden>
    <div class="lst-hint" id="lst-edit-what"></div>
    <div class="lst-hint">To change the list itself, delete it and add it again.</div>
    <input type="text" id="lst-edit-name" placeholder="Name">
    <input type="text" id="lst-edit-person" placeholder="Person (blank for a plain list)">
    <div class="lst-swatches" id="lst-edit-colors"></div>
    <div class="lst-result" id="lst-edit-result"></div>
    <div class="lst-actions">
      <button type="button" class="lst-cancel" data-lst-close>Cancel</button>
      <button type="button" class="lst-save" id="lst-edit-save">Save</button>
    </div>
  </div>
  <div class="lst-hint">A list with a person is that person's chore list.</div>
</div>
<script>$_listsScript</script>
''';

const _listsScript = r'''
(function () {
  var PREFIX = '/api/plugin/hearth.lists';
  var panel = document.getElementById('lists-panel');
  if (!panel) return;
  var palette = [];
  var lists = [];
  var editing = null;
  var picked = { add: null, edit: null };

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

  function swatches(key) {
    var box = $('lst-' + key + '-colors');
    box.textContent = '';
    var colors = palette.slice();
    if (picked[key] && colors.indexOf(picked[key]) < 0) colors.push(picked[key]);
    colors.forEach(function (c) {
      var b = elem('button', c === picked[key] ? 'lst-on' : '');
      b.type = 'button';
      b.style.background = c;
      b.title = c;
      b.addEventListener('click', function () {
        picked[key] = c;
        swatches(key);
      });
      box.appendChild(b);
    });
  }

  function nextColor() {
    var used = lists.map(function (l) { return l.color; });
    for (var i = 0; i < palette.length; i++) {
      if (used.indexOf(palette[i]) < 0) return palette[i];
    }
    return palette[lists.length % palette.length];
  }

  function closeForms() {
    $('lst-add-form').hidden = true;
    $('lst-edit-form').hidden = true;
    editing = null;
  }

  function render() {
    panel.textContent = '';
    if (!lists.length) {
      panel.appendChild(elem('div', 'lst-hint', 'No lists yet.'));
      return;
    }
    lists.forEach(function (l) {
      var row = elem('div', 'lst-row');
      var sw = elem('span', 'lst-swatch');
      sw.style.background = l.color;
      var txt = elem('div', 'lst-text');
      txt.appendChild(elem('div', null, l.name));
      txt.appendChild(elem('div', 'lst-sub' + (l.bad ? ' lst-bad' : ''),
        l.kindLabel + ' · ' + l.status));
      if (l.features) txt.appendChild(elem('div', 'lst-sub', l.features));
      var edit = elem('button', 'lst-btn', 'Edit');
      edit.type = 'button';
      edit.addEventListener('click', function () { openEdit(l); });
      var del = elem('button', 'lst-btn lst-del', 'Delete');
      del.type = 'button';
      del.addEventListener('click', function () {
        if (!confirm('Remove ' + l.name + '?')) return;
        call('DELETE', 'lists/' + encodeURIComponent(l.entityId)).then(load)
          .catch(function (e) { alert(e.message); });
      });
      row.appendChild(sw);
      row.appendChild(txt);
      row.appendChild(edit);
      row.appendChild(del);
      panel.appendChild(row);
    });
  }

  function load() {
    return call('GET', 'lists').then(function (d) {
      palette = d.palette || [];
      lists = d.lists || [];
      render();
    }).catch(function () { panel.textContent = 'Failed to load lists.'; });
  }

  function openAdd() {
    closeForms();
    picked.add = nextColor();
    $('lst-add-name').value = '';
    $('lst-add-person').value = '';
    var entity = $('haep-lists-entity-input');
    if (entity) entity.value = '';
    $('lst-add-result').textContent = '';
    swatches('add');
    $('lst-add-form').hidden = false;
  }

  function saveAdd() {
    var entity = $('haep-lists-entity-input');
    call('POST', 'lists', {
      entityId: entity ? entity.value.trim() : '',
      name: $('lst-add-name').value.trim(),
      person: $('lst-add-person').value.trim(),
      color: picked.add,
    }).then(function () {
      closeForms();
      load();
    }).catch(function (e) { $('lst-add-result').textContent = e.message; });
  }

  function openEdit(l) {
    closeForms();
    editing = l;
    picked.edit = l.color;
    $('lst-edit-what').textContent = l.entityId;
    $('lst-edit-name').value = l.name;
    $('lst-edit-person').value = l.person;
    $('lst-edit-result').textContent = '';
    swatches('edit');
    $('lst-edit-form').hidden = false;
  }

  function saveEdit() {
    if (!editing) return;
    call('PUT', 'lists/' + encodeURIComponent(editing.entityId), {
      name: $('lst-edit-name').value.trim(),
      person: $('lst-edit-person').value.trim(),
      color: picked.edit,
    }).then(function () {
      closeForms();
      load();
    }).catch(function (e) { $('lst-edit-result').textContent = e.message; });
  }

  function init() {
    $('lst-add').addEventListener('click', openAdd);
    $('lst-add-save').addEventListener('click', saveAdd);
    $('lst-edit-save').addEventListener('click', saveEdit);
    document.querySelectorAll('[data-lst-close]').forEach(function (b) {
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
