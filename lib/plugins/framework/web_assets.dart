// Inline frontend assets served by the web portal. Kept as Dart constants
// to match the existing pattern (raw HTML strings) — no separate static
// file serving needed.

/// CSS served alongside plugin panels in the web portal.
const hearthCss = r'''
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: #111; color: #e0e0e0;
  min-height: 100vh;
  display: flex;
}

/* Sidebar */
.sidebar {
  width: 240px;
  background: #080808;
  border-right: 1px solid #1f1f22;
  padding: 16px 0;
  overflow-y: auto;
  flex-shrink: 0;
}
.sidebar .category {
  font-size: 11px;
  color: #666;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  font-weight: 600;
  padding: 8px 16px 4px;
}
.sidebar .row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 16px;
  color: #e0e0e0;
  text-decoration: none;
  font-size: 13px;
  cursor: pointer;
}
.sidebar .row.selected {
  background: #1d2233;
  color: #9eb;
}
.sidebar .row:hover:not(.selected) {
  background: #161618;
}
.sidebar .row.legacy {
  color: rgba(224, 224, 224, 0.6);
  font-style: italic;
}
.sidebar .community-tag {
  font-size: 9px;
  color: #888;
  margin-left: auto;
}

/* Main panel */
.panel {
  flex: 1;
  padding: 24px;
  overflow-y: auto;
}
.panel-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}
.panel-header h1 {
  font-size: 22px;
  font-weight: 300;
  color: #fff;
}

/* Fields */
.field { margin-bottom: 16px; }
.field label {
  display: block;
  font-size: 13px;
  color: #aaa;
  margin-bottom: 4px;
}
.field input[type="text"],
.field input[type="password"],
.field input[type="number"],
.field textarea {
  width: 100%;
  padding: 10px 12px;
  background: #161618;
  border: 1px solid #333;
  border-radius: 6px;
  color: #e0e0e0;
  font-size: 14px;
  outline: none;
}
.field input:focus,
.field textarea:focus {
  border-color: #646cff;
}

/* Responsive */
@media (max-width: 900px) {
  .sidebar { position: fixed; left: -240px; height: 100vh; z-index: 100; transition: left 0.2s; }
  .sidebar.open { left: 0; }
  .panel { padding: 16px; }
}
''';

/// Inline JS helpers. Plugins emit `hearth.field(...)` calls that bind
/// auto-save behavior. Plugins emit `hearth.action(...)` to call their
/// backend routes.
const hearthJs = r'''
window.hearth = (function () {
  // Bearer token injected by the server at render time.
  const BEARER = window.__HEARTH_BEARER__;
  const PLUGIN_PREFIX = window.__HEARTH_PLUGIN_PREFIX__ || '';
  let debounceTimers = {};

  function field(configPath, opts) {
    opts = opts || {};
    const debounceMs = opts.debounce != null ? opts.debounce : 300;
    document.querySelectorAll('input[data-config-path="' + configPath + '"]').forEach(el => {
      el.addEventListener('input', () => {
        clearTimeout(debounceTimers[configPath]);
        debounceTimers[configPath] = setTimeout(() => {
          save(configPath, el.value);
        }, debounceMs);
      });
    });
  }

  async function save(configPath, value) {
    const body = {};
    body[configPath] = value;
    const res = await fetch('/api/config', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + BEARER,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) console.error('save failed', configPath, res.status);
  }

  async function action(path, body) {
    const res = await fetch(PLUGIN_PREFIX + '/' + path, {
      method: body ? 'POST' : 'GET',
      headers: {
        'Authorization': 'Bearer ' + BEARER,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error('Action failed: ' + res.status);
    return res.json();
  }

  // Auto-bind all fields with [data-config-path] on page load. Plugins
  // can opt out by adding [data-no-auto-save].
  function autoBindFields() {
    document.querySelectorAll('input[data-config-path]:not([data-no-auto-save])')
      .forEach(el => field(el.dataset.configPath));
  }

  document.addEventListener('DOMContentLoaded', autoBindFields);

  return { field, action, save };
})();
''';
