import '../web_context.dart';

/// Path of the shared Home Assistant entity-list route (see
/// [HomeAssistantPlugin.registerHttpRoutes]). It is owned by the HA plugin but
/// reached from any panel — the night-mode picker lives on the Display panel,
/// whose own plugin prefix can't see this route, so the field fetches the
/// absolute path with the page-global bearer token rather than the
/// prefix-scoped `hearth.action` helper.
const _haEntitiesRoute = '/api/plugin/hearth.ha/entities';

/// Web-only searchable single-select picker for a Home Assistant entity id,
/// bound to a string [configPath] on HubConfig.
///
/// Renders a real `<input data-config-path>` (the canonical value: free-text
/// fallback when HA is unreachable, auto-saved by the generic field binder,
/// and the `web_parity_guard_test` ledger marker) with a searchable list of
/// live HA entities layered on top. Clicking a row fills the input and fires
/// its `input` event so the existing auto-save path persists the pick.
///
/// On-device these fields keep their native pickers (a dynamic `SelectSettingField`
/// for the voice satellite, a bespoke dialog tile for night mode); this class
/// only closes the *web* parity gap, so it intentionally renders HTML only and
/// is not a [SettingField] subclass.
class HaEntityPickerField {
  /// HubConfig field this picker reads/writes (e.g. `voiceAssistantEntityId`).
  final String configPath;

  /// Label shown above the field.
  final String label;

  /// Placeholder / hint for the free-text input.
  final String? hint;

  /// Comma-separated HA domains to filter the option list to (e.g.
  /// `assist_satellite`). Null requests the full entity list — used by
  /// night mode, which accepts any entity, mirroring the on-device free-text.
  final String? domains;

  const HaEntityPickerField({
    required this.configPath,
    required this.label,
    this.hint,
    this.domains,
  });

  String buildHtml(WebContext ctx) {
    final current = (ctx.config.toJson()[configPath] as String?) ?? '';
    final escapedValue = _escapeHtml(current);
    final escapedLabel = _escapeHtml(label);
    final placeholder = hint == null ? '' : 'placeholder="${_escapeHtml(hint!)}"';
    final slug = 'haep-$configPath';
    final d = domains;
    final url = (d == null || d.isEmpty)
        ? _haEntitiesRoute
        : '$_haEntitiesRoute?domains=${Uri.encodeQueryComponent(d)}';
    return '''
<div class="field">
  <label>$escapedLabel</label>
  <input type="text"
         class="hearth-field"
         id="$slug-input"
         data-config-path="$configPath"
         value="$escapedValue"
         autocomplete="off"
         $placeholder>
  <input type="text"
         id="$slug-search"
         placeholder="Search Home Assistant entities…"
         autocomplete="off"
         style="margin-top:6px">
  <div id="$slug-list" style="margin-top:6px;max-height:220px;overflow-y:auto"></div>
  <div id="$slug-status" style="font-size:11px;color:#666;margin-top:6px"></div>
  <script>${_pickerScript(slug, url)}</script>
</div>
''';
  }
}

/// The client-side picker behaviour. Kept free of `\$` and `\\` so it can be a
/// plain interpolated string (only [slug] and [url] are substituted).
String _pickerScript(String slug, String url) => '''
(function () {
  function init() {
    var valueInput = document.getElementById('$slug-input');
    var search = document.getElementById('$slug-search');
    var list = document.getElementById('$slug-list');
    var status = document.getElementById('$slug-status');
    if (!valueInput || !list) return;
    var all = [];

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
        empty.textContent = all.length ? 'No matches.' : '';
        list.appendChild(empty);
        return;
      }
      shown.slice(0, 200).forEach(function (e) {
        var row = document.createElement('div');
        row.style.cssText = 'padding:8px 10px;background:#161618;border-radius:6px;margin-bottom:4px;cursor:pointer';
        if (e.id === valueInput.value) row.style.background = '#1d2233';
        var nm = document.createElement('div');
        nm.textContent = e.name;
        var id = document.createElement('div');
        id.textContent = e.id;
        id.style.cssText = 'font-size:11px;color:#777';
        row.appendChild(nm);
        row.appendChild(id);
        row.addEventListener('click', function () {
          valueInput.value = e.id;
          valueInput.dispatchEvent(new Event('input', { bubbles: true }));
          status.textContent = 'Selected: ' + e.name;
          render();
        });
        list.appendChild(row);
      });
    }

    search.addEventListener('input', render);
    status.textContent = 'Loading entities…';
    fetch('$url', {
      headers: { 'Authorization': 'Bearer ' + (window.__HEARTH_BEARER__ || '') },
    }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.json();
    }).then(function (d) {
      all = d.entities || [];
      status.textContent = all.length
        ? all.length + ' entities — click to select'
        : 'No matching entities in Home Assistant.';
      render();
    }).catch(function () {
      status.textContent = 'Home Assistant unreachable — type the entity ID above.';
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
''';

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
