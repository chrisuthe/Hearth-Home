import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'display_mode_service.dart';
import 'wifi_service.dart';
import 'update_service.dart';

/// Minimal HTTP server for external device control and configuration.
///
/// Runs on port 8090 by default. All /api/* endpoints require a Bearer
/// token matching the auto-generated apiKey in HubConfig. The config
/// page at / is unauthenticated so a fresh kiosk can be set up from
/// any browser on the LAN.
///
/// Endpoints:
///   GET  /                 — config web page (unauthenticated)
///   GET  /api/config       — read config (secrets redacted)
///   POST /api/config       — update config fields
///   POST /api/display-mode — set night/day mode
///   GET  /api/display-mode — query current mode
///   GET  /api/wifi/scan    — scan for WiFi networks
///   POST /api/wifi/connect — connect to a WiFi network
///   GET  /api/update/status — current version and auto-update setting
class LocalApiServer {
  final DisplayModeService _displayModeService;
  final HubConfigNotifier _configNotifier;
  final WifiService _wifiService;
  // ignore: unused_field
  final UpdateService _updateService;
  HttpServer? _server;

  static const int _maxBodySize = 64 * 1024; // 64 KB

  LocalApiServer({
    required DisplayModeService displayModeService,
    required HubConfigNotifier configNotifier,
    WifiService? wifiService,
    UpdateService? updateService,
  })  : _displayModeService = displayModeService,
        _configNotifier = configNotifier,
        _wifiService = wifiService ?? WifiService(),
        _updateService = updateService ?? UpdateService();

  Future<int> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path == '/') {
        await _serveConfigPage(request);
      } else if (path.startsWith('/api/')) {
        if (!_checkAuth(request)) return;
        if (path == '/api/config') {
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
        } else if (path == '/api/wifi/scan' && request.method == 'GET') {
          await _handleWifiScan(request);
        } else if (path == '/api/wifi/connect' && request.method == 'POST') {
          await _handleWifiConnect(request);
        } else if (path == '/api/update/status' && request.method == 'GET') {
          await _handleUpdateStatus(request);
        } else {
          request.response.statusCode = 404;
          request.response.write(jsonEncode({'error': 'not found'}));
          await request.response.close();
        }
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'error': 'not found'}));
        await request.response.close();
      }
    } catch (e) {
      debugPrint('API server error: $e');
      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'internal server error'}));
        await request.response.close();
      } catch (_) {
        // Response may already be closed or broken — nothing more we can do.
      }
    }
  }

  /// Validates the Bearer token against the stored API key.
  /// Returns true if authorized, false if rejected (response already sent).
  bool _checkAuth(HttpRequest request) {
    final apiKey = _configNotifier.current.apiKey;
    final authHeader = request.headers.value('authorization');
    final token = authHeader != null && authHeader.startsWith('Bearer ')
        ? authHeader.substring(7)
        : null;

    if (token != apiKey) {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'unauthorized'}));
      request.response.close();
      return false;
    }
    return true;
  }

  /// Reads and decodes a JSON request body with size limit enforcement.
  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.length > _maxBodySize) {
      throw const FormatException('Request body too large');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Reads raw request body as a string with size limit enforcement.
  /// Returns null and sends a 400 response if the body is too large.
  Future<String?> _readBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.length > _maxBodySize) {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'request body too large'}));
      await request.response.close();
      return null;
    }
    return body;
  }

  // --- Config endpoints ---

  Future<void> _handleGetConfig(HttpRequest request) async {
    final json = _configNotifier.current.toJson();
    // Redact secrets — tokens are write-only from the API's perspective.
    const secretFields = ['apiKey', 'haToken', 'immichApiKey', 'musicAssistantToken'];
    for (final field in secretFields) {
      final value = json[field] as String? ?? '';
      json[field] = value.isEmpty ? '' : '••••••••';
    }
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
    await request.response.close();
  }

  Future<void> _handlePostConfig(HttpRequest request) async {
    final json = await _readJsonBody(request);

    await _configNotifier.update((c) => c.copyWith(
          immichUrl: json['immichUrl'] as String?,
          immichApiKey: json['immichApiKey'] as String?,
          haUrl: json['haUrl'] as String?,
          haToken: json['haToken'] as String?,
          musicAssistantUrl: json['musicAssistantUrl'] as String?,
          musicAssistantToken: json['musicAssistantToken'] as String?,
          frigateUrl: json['frigateUrl'] as String?,
          weatherEntityId: json['weatherEntityId'] as String?,
          idleTimeoutSeconds: json['idleTimeoutSeconds'] as int?,
          nightModeSource: json['nightModeSource'] as String?,
          nightModeHaEntity: json['nightModeHaEntity'] as String?,
          nightModeClockStart: json['nightModeClockStart'] as String?,
          nightModeClockEnd: json['nightModeClockEnd'] as String?,
          defaultMusicZone: json['defaultMusicZone'] as String?,
          use24HourClock: json['use24HourClock'] as bool?,
          pinnedEntityIds:
              (json['pinnedEntityIds'] as List<dynamic>?)?.cast<String>(),
          displayProfile: json['displayProfile'] as String?,
          autoUpdate: json['autoUpdate'] as bool?,
          sendspinEnabled: json['sendspinEnabled'] as bool?,
          sendspinPlayerName: json['sendspinPlayerName'] as String?,
          sendspinBufferSeconds: json['sendspinBufferSeconds'] as int?,
          sendspinServerUrl: json['sendspinServerUrl'] as String?,
        ));

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'saved'}));
    await request.response.close();
  }

  // --- Display mode endpoints ---

  Future<void> _handleSetDisplayMode(HttpRequest request) async {
    final json = await _readJsonBody(request);
    final modeStr = json['mode'] as String?;

    final mode = modeStr == 'night' ? DisplayMode.night : DisplayMode.day;
    _displayModeService.setModeFromApi(mode);

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': modeStr}));
    await request.response.close();
  }

  Future<void> _handleGetDisplayMode(HttpRequest request) async {
    final config = _configNotifier.current;
    final mode = _displayModeService.resolveMode(config: config);
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': mode.name}));
    await request.response.close();
  }

  // --- WiFi endpoints ---

  Future<void> _handleWifiScan(HttpRequest request) async {
    final networks = await _wifiService.scan();
    final connected = await _wifiService.activeConnection();
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'networks': networks.map((n) => {
          'ssid': n.ssid,
          'signal': n.signalStrength,
          'security': n.security,
          'isOpen': n.isOpen,
        }).toList(),
        'connected': connected,
      }));
    await request.response.close();
  }

  Future<void> _handleWifiConnect(HttpRequest request) async {
    final body = await _readBody(request);
    if (body == null) return;
    final data = jsonDecode(body) as Map<String, dynamic>;
    final ssid = data['ssid'] as String? ?? '';
    final password = data['password'] as String? ?? '';
    final success = password.isEmpty
        ? await _wifiService.connectOpen(ssid)
        : await _wifiService.connect(ssid, password);
    request.response
      ..statusCode = success ? 200 : 500
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'success': success}));
    await request.response.close();
  }

  Future<void> _handleUpdateStatus(HttpRequest request) async {
    final config = _configNotifier.current;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'currentVersion': config.currentVersion,
        'autoUpdate': config.autoUpdate,
      }));
    await request.response.close();
  }

  // --- Config web page ---

  Future<void> _serveConfigPage(HttpRequest request) async {
    final apiKey = _configNotifier.current.apiKey;
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.add('X-Content-Type-Options', 'nosniff');
    request.response.headers.add('X-Frame-Options', 'DENY');
    // Inject the API key into the page so JS can authenticate requests.
    request.response.write(_configPageHtml.replaceFirst(
        '{{API_KEY}}', apiKey.replaceAll(r'\', r'\\').replaceAll("'", r"\'")));
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close();
  }
}

final localApiServerProvider = Provider<LocalApiServer>((ref) {
  // Use ref.read — the server reads config/display state per-request,
  // so it doesn't need to be recreated when config changes.
  final displayService = ref.read(displayModeServiceProvider);
  final configNotifier = ref.read(hubConfigProvider.notifier);
  final wifiService = ref.read(wifiServiceProvider);
  final updateService = ref.read(updateServiceProvider);
  return LocalApiServer(
    displayModeService: displayService,
    configNotifier: configNotifier,
    wifiService: wifiService,
    updateService: updateService,
  );
});

// ---------------------------------------------------------------------------
// Inline HTML for the config page. Kept as a raw string to avoid any build
// tooling — this page is hit once to enter credentials, not a production UI.
// The {{API_KEY}} placeholder is replaced server-side on each request.
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
  .hint {
    font-size: 11px; color: #666; margin-bottom: 12px;
  }
  select {
    width: 100%; padding: 10px 12px; margin-bottom: 12px;
    background: #1e1e1e; border: 1px solid #333; border-radius: 6px;
    color: #e0e0e0; font-size: 14px; outline: none;
  }
  select:focus { border-color: #646cff; }
  .checkbox-label {
    display: flex; align-items: center; gap: 8px;
    font-size: 14px; color: #e0e0e0; margin-bottom: 12px; cursor: pointer;
  }
  .checkbox-label input[type="checkbox"] {
    width: 18px; height: 18px; accent-color: #646cff;
  }
</style>
</head>
<body>
<div class="container">
  <h1>Hearth Setup</h1>
  <form id="configForm">

    <h2>Connections</h2>
    <label for="immichUrl">Immich URL</label>
    <input type="text" id="immichUrl" placeholder="http://192.168.1.x:2283">
    <label for="immichApiKey">Immich API Key</label>
    <div class="secret-wrap">
      <input type="password" id="immichApiKey" placeholder="Paste your Immich API key">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
    <div class="hint" id="immichApiKey_hint"></div>

    <label for="haUrl">Home Assistant URL</label>
    <input type="text" id="haUrl" placeholder="http://192.168.1.x:8123">
    <label for="haToken">HA Long-Lived Access Token</label>
    <div class="secret-wrap">
      <input type="password" id="haToken" placeholder="Paste your HA token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
    <div class="hint" id="haToken_hint"></div>

    <label for="musicAssistantUrl">Music Assistant URL</label>
    <input type="text" id="musicAssistantUrl" placeholder="http://192.168.1.x:8095">
    <label for="musicAssistantToken">Music Assistant Token</label>
    <div class="secret-wrap">
      <input type="password" id="musicAssistantToken" placeholder="Paste your MA long-lived token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
    <div class="hint" id="musicAssistantToken_hint"></div>
    <label for="defaultMusicZone">Default Music Zone</label>
    <input type="text" id="defaultMusicZone" placeholder="media_player.living_room">

    <label for="frigateUrl">Frigate URL</label>
    <input type="text" id="frigateUrl" placeholder="http://192.168.1.x:5000">

    <h2>Weather</h2>
    <label for="weatherEntityId">Weather Entity ID</label>
    <input type="text" id="weatherEntityId" placeholder="weather.pirateweather">

    <h2>Display</h2>
    <label for="idleTimeoutSeconds">Idle Timeout (seconds)</label>
    <input type="number" id="idleTimeoutSeconds" min="30" max="600" step="10" placeholder="120">
    <label for="use24HourClock" class="checkbox-label">
      <input type="checkbox" id="use24HourClock"> Use 24-Hour Clock
    </label>
    <label for="displayProfile">Display Profile</label>
    <select id="displayProfile">
      <option value="auto">Auto-detect</option>
      <option value="amoled-11">11" AMOLED (1184x864)</option>
      <option value="rpi-7">RPi 7" Touchscreen (800x480)</option>
      <option value="hdmi">HDMI Monitor (native)</option>
    </select>

    <h2>Night Mode</h2>
    <label for="nightModeSource">Source</label>
    <select id="nightModeSource">
      <option value="none">Disabled</option>
      <option value="clock">Clock Schedule</option>
      <option value="ha_entity">HA Entity</option>
      <option value="api">External API</option>
    </select>
    <label for="nightModeHaEntity">Night Mode HA Entity</label>
    <input type="text" id="nightModeHaEntity" placeholder="binary_sensor.night_mode">
    <label for="nightModeClockStart">Clock Start (HH:MM)</label>
    <input type="text" id="nightModeClockStart" placeholder="22:00">
    <label for="nightModeClockEnd">Clock End (HH:MM)</label>
    <input type="text" id="nightModeClockEnd" placeholder="07:00">

    <h2>Pinned Devices</h2>
    <label for="pinnedEntityIds">Entity IDs (one per line)</label>
    <textarea id="pinnedEntityIds" rows="6" placeholder="light.kitchen&#10;climate.living_room&#10;switch.garage_door" style="width:100%;padding:10px 12px;margin-bottom:12px;background:#1e1e1e;border:1px solid #333;border-radius:6px;color:#e0e0e0;font-size:14px;outline:none;resize:vertical;font-family:monospace;"></textarea>

    <h2>Sendspin Audio</h2>
    <label for="sendspinEnabled" class="checkbox-label">
      <input type="checkbox" id="sendspinEnabled"> Enable Sendspin Player
    </label>
    <label for="sendspinPlayerName">Player Name</label>
    <input type="text" id="sendspinPlayerName" placeholder="Kitchen Display">
    <label for="sendspinServerUrl">Server URL (blank for auto-discover)</label>
    <input type="text" id="sendspinServerUrl" placeholder="ws://192.168.1.x:8095">
    <label for="sendspinBufferSeconds">Buffer Size</label>
    <select id="sendspinBufferSeconds">
      <option value="5">5 seconds</option>
      <option value="7">7 seconds</option>
      <option value="10">10 seconds</option>
    </select>

    <h2>Updates</h2>
    <label for="autoUpdate" class="checkbox-label">
      <input type="checkbox" id="autoUpdate"> Auto-Update
    </label>

    <button type="submit" class="save">Save</button>
  </form>
  <div class="toast" id="toast"></div>
</div>
<script>
const API_KEY = '{{API_KEY}}';
const headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + API_KEY};

const textFields = [
  'immichUrl','immichApiKey','haUrl','haToken',
  'musicAssistantUrl','musicAssistantToken','defaultMusicZone','frigateUrl',
  'weatherEntityId','nightModeHaEntity','nightModeClockStart','nightModeClockEnd',
  'sendspinPlayerName','sendspinServerUrl'
];
const intFields = ['idleTimeoutSeconds','sendspinBufferSeconds'];
const boolFields = ['use24HourClock','sendspinEnabled','autoUpdate'];
const selectFields = ['nightModeSource','displayProfile'];
const secretFields = ['immichApiKey', 'haToken', 'musicAssistantToken'];
const REDACTED = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

async function load() {
  try {
    const r = await fetch('/api/config', {headers});
    const cfg = await r.json();
    for (const f of textFields) {
      const el = document.getElementById(f);
      if (!el) continue;
      const val = cfg[f];
      if (secretFields.includes(f)) {
        const hint = document.getElementById(f + '_hint');
        if (val === REDACTED && hint) hint.textContent = 'A value is saved. Leave blank to keep it.';
      } else if (val != null && val !== '') {
        el.value = val;
      }
    }
    for (const f of intFields) {
      const el = document.getElementById(f);
      if (el && cfg[f] != null) el.value = cfg[f];
    }
    for (const f of boolFields) {
      const el = document.getElementById(f);
      if (el) el.checked = cfg[f] === true;
    }
    for (const f of selectFields) {
      const el = document.getElementById(f);
      if (el && cfg[f]) el.value = cfg[f];
    }
    if (cfg.pinnedEntityIds && Array.isArray(cfg.pinnedEntityIds)) {
      document.getElementById('pinnedEntityIds').value = cfg.pinnedEntityIds.join('\n');
    }
  } catch(e) { showToast('Failed to load config', true); }
}

document.getElementById('configForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const body = {};
  for (const f of textFields) {
    const el = document.getElementById(f);
    if (secretFields.includes(f)) {
      if (el.value.trim() !== '') body[f] = el.value;
    } else {
      body[f] = el.value;
    }
  }
  for (const f of intFields) {
    const el = document.getElementById(f);
    body[f] = parseInt(el.value) || 0;
  }
  for (const f of boolFields) {
    const el = document.getElementById(f);
    body[f] = el.checked;
  }
  for (const f of selectFields) {
    const el = document.getElementById(f);
    body[f] = el.value;
  }
  const pinnedText = document.getElementById('pinnedEntityIds').value;
  body.pinnedEntityIds = pinnedText.split('\n').map(s => s.trim()).filter(s => s.length > 0);
  try {
    const r = await fetch('/api/config', {method: 'POST', headers, body: JSON.stringify(body)});
    if (r.ok) { showToast('Saved!'); }
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
