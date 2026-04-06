import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'display_mode_service.dart';

/// Minimal HTTP server for external device control and configuration.
///
/// Runs on port 8090 by default. Endpoints:
///   GET  /                 — config web page for entering service credentials
///   GET  /api/config       — read current config as JSON
///   POST /api/config       — update config fields
///   POST /api/display-mode — set night/day mode from external devices
///   GET  /api/display-mode — query current mode
class LocalApiServer {
  final DisplayModeService _displayModeService;
  final HubConfigNotifier _configNotifier;
  HttpServer? _server;

  LocalApiServer({
    required DisplayModeService displayModeService,
    required HubConfigNotifier configNotifier,
  })  : _displayModeService = displayModeService,
        _configNotifier = configNotifier;

  Future<int> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/') {
      await _serveConfigPage(request);
    } else if (path == '/api/config') {
      if (request.method == 'GET') {
        await _handleGetConfig(request);
      } else if (request.method == 'POST') {
        await _handlePostConfig(request);
      } else {
        request.response.statusCode = 405;
        await request.response.close();
      }
    } else if (path == '/api/display-mode') {
      if (request.method == 'POST') {
        await _handleSetDisplayMode(request);
      } else if (request.method == 'GET') {
        await _handleGetDisplayMode(request);
      } else {
        request.response.statusCode = 405;
        await request.response.close();
      }
    } else {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'not found'}));
      await request.response.close();
    }
  }

  // --- Config endpoints ---

  Future<void> _handleGetConfig(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_configNotifier.current.toJson()));
    await request.response.close();
  }

  Future<void> _handlePostConfig(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    await _configNotifier.update((c) => HubConfig(
          immichUrl: json['immichUrl'] as String? ?? c.immichUrl,
          immichApiKey: json['immichApiKey'] as String? ?? c.immichApiKey,
          haUrl: json['haUrl'] as String? ?? c.haUrl,
          haToken: json['haToken'] as String? ?? c.haToken,
          musicAssistantUrl:
              json['musicAssistantUrl'] as String? ?? c.musicAssistantUrl,
          musicAssistantToken:
              json['musicAssistantToken'] as String? ?? c.musicAssistantToken,
          frigateUrl: json['frigateUrl'] as String? ?? c.frigateUrl,
          idleTimeoutSeconds:
              json['idleTimeoutSeconds'] as int? ?? c.idleTimeoutSeconds,
          nightModeSource:
              json['nightModeSource'] as String? ?? c.nightModeSource,
          nightModeHaEntity:
              json['nightModeHaEntity'] as String? ?? c.nightModeHaEntity,
          nightModeClockStart:
              json['nightModeClockStart'] as String? ?? c.nightModeClockStart,
          nightModeClockEnd:
              json['nightModeClockEnd'] as String? ?? c.nightModeClockEnd,
          defaultMusicZone:
              json['defaultMusicZone'] as String? ?? c.defaultMusicZone,
          use24HourClock:
              json['use24HourClock'] as bool? ?? c.use24HourClock,
          pinnedEntityIds:
              (json['pinnedEntityIds'] as List<dynamic>?)?.cast<String>() ??
                  c.pinnedEntityIds,
        ));

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'saved'}));
    await request.response.close();
  }

  // --- Display mode endpoints ---

  Future<void> _handleSetDisplayMode(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modeStr = json['mode'] as String?;

    final mode = modeStr == 'night' ? DisplayMode.night : DisplayMode.day;
    _displayModeService.setModeFromApi(mode);

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': modeStr}));
    await request.response.close();
  }

  Future<void> _handleGetDisplayMode(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': 'day'}));
    await request.response.close();
  }

  // --- Config web page ---

  Future<void> _serveConfigPage(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write(_configPageHtml);
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close();
  }
}

final localApiServerProvider = Provider<LocalApiServer>((ref) {
  final displayService = ref.watch(displayModeServiceProvider);
  final configNotifier = ref.watch(hubConfigProvider.notifier);
  return LocalApiServer(
    displayModeService: displayService,
    configNotifier: configNotifier,
  );
});

// ---------------------------------------------------------------------------
// Inline HTML for the config page. Kept as a raw string to avoid any build
// tooling — this page is hit once to enter credentials, not a production UI.
// ---------------------------------------------------------------------------

const _configPageHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth Setup</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #111; color: #e0e0e0;
    display: flex; justify-content: center;
    padding: 24px 16px;
  }
  .container { width: 100%; max-width: 520px; }
  h1 { font-size: 22px; font-weight: 300; margin-bottom: 24px; color: #fff; }
  h2 {
    font-size: 11px; font-weight: 600; letter-spacing: 1.2px;
    color: #888; text-transform: uppercase; margin: 24px 0 8px;
  }
  label { display: block; font-size: 13px; color: #aaa; margin-bottom: 4px; }
  input[type="text"], input[type="password"], input[type="number"] {
    width: 100%; padding: 10px 12px; margin-bottom: 12px;
    background: #1e1e1e; border: 1px solid #333; border-radius: 6px;
    color: #e0e0e0; font-size: 14px; outline: none;
  }
  input:focus { border-color: #646cff; }
  .secret-wrap { position: relative; }
  .secret-wrap input { padding-right: 40px; }
  .toggle-vis {
    position: absolute; right: 8px; top: 8px;
    background: none; border: none; color: #666; cursor: pointer; font-size: 18px;
  }
  button.save {
    width: 100%; padding: 12px; margin-top: 8px;
    background: #646cff; color: #fff; border: none; border-radius: 6px;
    font-size: 15px; cursor: pointer;
  }
  button.save:hover { background: #535bf2; }
  .toast {
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
    background: #2a2a2a; color: #4ade80; padding: 10px 24px;
    border-radius: 8px; font-size: 14px; opacity: 0; transition: opacity 0.3s;
  }
  .toast.show { opacity: 1; }
  .toast.error { color: #f87171; }
</style>
</head>
<body>
<div class="container">
  <h1>Hearth Setup</h1>
  <form id="configForm">

    <h2>Immich</h2>
    <label for="immichUrl">Server URL</label>
    <input type="text" id="immichUrl" placeholder="http://192.168.1.x:2283">
    <label for="immichApiKey">API Key</label>
    <div class="secret-wrap">
      <input type="password" id="immichApiKey" placeholder="Paste your Immich API key">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>

    <h2>Home Assistant</h2>
    <label for="haUrl">Server URL</label>
    <input type="text" id="haUrl" placeholder="http://192.168.1.x:8123">
    <label for="haToken">Long-Lived Access Token</label>
    <div class="secret-wrap">
      <input type="password" id="haToken" placeholder="Paste your HA token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>

    <h2>Music Assistant</h2>
    <label for="musicAssistantUrl">Server URL</label>
    <input type="text" id="musicAssistantUrl" placeholder="http://192.168.1.x:8095">
    <label for="musicAssistantToken">Token</label>
    <div class="secret-wrap">
      <input type="password" id="musicAssistantToken" placeholder="Paste your MA long-lived token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
    <label for="defaultMusicZone">Default Zone</label>
    <input type="text" id="defaultMusicZone" placeholder="media_player.living_room">

    <h2>Frigate</h2>
    <label for="frigateUrl">Server URL</label>
    <input type="text" id="frigateUrl" placeholder="http://192.168.1.x:5000">

    <h2>Display</h2>
    <label for="idleTimeoutSeconds">Idle Timeout (seconds)</label>
    <input type="number" id="idleTimeoutSeconds" min="30" max="600" step="10" placeholder="120">

    <h2>Pinned Devices</h2>
    <label for="pinnedEntityIds">Entity IDs (one per line)</label>
    <textarea id="pinnedEntityIds" rows="6" placeholder="light.kitchen&#10;climate.living_room&#10;switch.garage_door" style="width:100%;padding:10px 12px;margin-bottom:12px;background:#1e1e1e;border:1px solid #333;border-radius:6px;color:#e0e0e0;font-size:14px;outline:none;resize:vertical;font-family:monospace;"></textarea>

    <button type="submit" class="save">Save</button>
  </form>
  <div class="toast" id="toast"></div>
</div>
<script>
const fields = [
  'immichUrl','immichApiKey','haUrl','haToken',
  'musicAssistantUrl','musicAssistantToken','defaultMusicZone','frigateUrl','idleTimeoutSeconds'
];

async function load() {
  try {
    const r = await fetch('/api/config');
    const cfg = await r.json();
    for (const f of fields) {
      const el = document.getElementById(f);
      if (el && cfg[f] != null && cfg[f] !== '') el.value = cfg[f];
    }
    if (cfg.pinnedEntityIds && Array.isArray(cfg.pinnedEntityIds)) {
      document.getElementById('pinnedEntityIds').value = cfg.pinnedEntityIds.join('\n');
    }
  } catch(e) { showToast('Failed to load config', true); }
}

document.getElementById('configForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const body = {};
  for (const f of fields) {
    const el = document.getElementById(f);
    if (f === 'idleTimeoutSeconds') {
      body[f] = parseInt(el.value) || 120;
    } else {
      body[f] = el.value;
    }
  }
  const pinnedText = document.getElementById('pinnedEntityIds').value;
  body.pinnedEntityIds = pinnedText.split('\n').map(s => s.trim()).filter(s => s.length > 0);
  try {
    const r = await fetch('/api/config', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(body)
    });
    if (r.ok) { showToast('Saved! Restart Hearth to apply.'); }
    else { showToast('Save failed', true); }
  } catch(e) { showToast('Save failed', true); }
});

function toggleVis(btn) {
  const inp = btn.previousElementSibling;
  inp.type = inp.type === 'password' ? 'text' : 'password';
}

function showToast(msg, isError) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show' + (isError ? ' error' : '');
  setTimeout(() => t.className = 'toast', 2500);
}

load();
</script>
</body>
</html>
''';
