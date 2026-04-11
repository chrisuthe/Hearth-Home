import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
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

  /// 4-digit PIN displayed on the kiosk Settings screen.
  /// Users must enter this PIN in the web portal to gain access.
  final String _webPin;
  String get webPin => _webPin;

  /// Active session tokens granted after successful PIN entry.
  final Set<String> _activeSessions = {};

  LocalApiServer({
    required DisplayModeService displayModeService,
    required HubConfigNotifier configNotifier,
    WifiService? wifiService,
    UpdateService? updateService,
    String? webPin,
  })  : _displayModeService = displayModeService,
        _configNotifier = configNotifier,
        _wifiService = wifiService ?? WifiService(),
        _updateService = updateService ?? UpdateService(),
        _webPin = webPin ?? (Random.secure().nextInt(9000) + 1000).toString();

  Future<int> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// Generates a random 32-character session token.
  static String _generateSessionToken() {
    final rng = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Checks whether the request carries a valid session cookie.
  bool _checkSession(HttpRequest request) {
    final cookieHeader = request.headers.value('cookie');
    if (cookieHeader == null) return false;
    // Parse cookies: "name=value; name2=value2"
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('hearth_session=')) {
        final token = trimmed.substring('hearth_session='.length);
        return _activeSessions.contains(token);
      }
    }
    return false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      // Reject CORS preflight requests — the kiosk API is same-origin only.
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }

      final path = request.uri.path;

      // --- PIN auth endpoint (unauthenticated) ---
      if (path == '/auth/pin' && request.method == 'POST') {
        await _handlePinAuth(request);
        return;
      }

      if (path == '/') {
        if (_checkSession(request)) {
          await _serveConfigPage(request);
        } else {
          await _servePinPage(request);
        }
      } else if (path == '/logs') {
        if (_checkSession(request)) {
          await _serveLogsPage(request);
        } else {
          await _servePinPage(request);
        }
      } else if (path == '/api/session/key' && request.method == 'GET') {
        if (!_checkSession(request)) {
          request.response.statusCode = 401;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'error': 'unauthorized'}));
          await request.response.close();
          return;
        }
        await _handleSessionKey(request);
      } else if (path == '/api/logs' && request.method == 'GET') {
        if (!_checkAuth(request)) return;
        await _handleGetLogs(request);
      } else if (path == '/api/system/stats' && request.method == 'GET') {
        if (!_checkAuth(request)) return;
        await _handleSystemStats(request);
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
        } else if (path == '/api/update/check' && request.method == 'POST') {
          await _handleUpdateCheck(request);
        } else if (path == '/api/update/apply' && request.method == 'POST') {
          await _handleUpdateApply(request);
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
      Log.e('API', 'Request handler error: $e');
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
  /// Rejects early if Content-Length exceeds the limit, then streams with
  /// a byte counter to guard against chunked transfers that lie about length.
  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    if (request.contentLength > _maxBodySize) {
      request.response.statusCode = 413;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'request body too large'}));
      await request.response.close();
      throw const FormatException('Request body too large');
    }
    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
      if (chunks.length > _maxBodySize) {
        request.response.statusCode = 413;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'request body too large'}));
        await request.response.close();
        throw const FormatException('Request body too large');
      }
    }
    final body = utf8.decode(chunks);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Reads raw request body as a string with size limit enforcement.
  /// Returns null and sends a 413 response if the body is too large.
  Future<String?> _readBody(HttpRequest request) async {
    if (request.contentLength > _maxBodySize) {
      request.response.statusCode = 413;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'request body too large'}));
      await request.response.close();
      return null;
    }
    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
      if (chunks.length > _maxBodySize) {
        request.response.statusCode = 413;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'request body too large'}));
        await request.response.close();
        return null;
      }
    }
    return utf8.decode(chunks);
  }

  // --- PIN auth ---

  Future<void> _handlePinAuth(HttpRequest request) async {
    final json = await _readJsonBody(request);
    final pin = json['pin'] as String?;
    if (pin == _webPin) {
      final token = _generateSessionToken();
      _activeSessions.add(token);
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.add(
        'Set-Cookie',
        'hearth_session=$token; HttpOnly; SameSite=Strict; Max-Age=86400; Path=/',
      );
      request.response.write(jsonEncode({'status': 'ok'}));
      await request.response.close();
    } else {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'wrong pin'}));
      await request.response.close();
    }
  }

  /// Returns the API key to authenticated web sessions so JS can call /api/*.
  Future<void> _handleSessionKey(HttpRequest request) async {
    final apiKey = _configNotifier.current.apiKey;
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'apiKey': apiKey}));
    await request.response.close();
  }

  // --- Config endpoints ---

  Future<void> _handleGetConfig(HttpRequest request) async {
    final json = _configNotifier.current.toJson();
    // Redact secrets — tokens are write-only from the API's perspective.
    const secretFields = ['apiKey', 'haToken', 'immichApiKey', 'musicAssistantToken', 'mealieToken', 'giteaApiToken'];
    for (final field in secretFields) {
      final value = json[field] as String? ?? '';
      json[field] = value.isEmpty ? '' : '••••••••';
    }
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
    await request.response.close();
  }

  static const _redactedMarker = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

  Future<void> _handlePostConfig(HttpRequest request) async {
    final json = await _readJsonBody(request);

    // Filter out redacted markers so clients cannot overwrite real secrets
    // with the placeholder value returned by GET /api/config.
    const secretFields = ['haToken', 'immichApiKey', 'musicAssistantToken', 'mealieToken', 'giteaApiToken'];
    for (final field in secretFields) {
      if (json[field] == _redactedMarker) {
        json.remove(field);
      }
    }

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
          updateSource: json['updateSource'] as String?,
          giteaApiToken: json['giteaApiToken'] as String?,
          sendspinEnabled: json['sendspinEnabled'] as bool?,
          sendspinPlayerName: json['sendspinPlayerName'] as String?,
          sendspinBufferSeconds: json['sendspinBufferSeconds'] as int?,
          sendspinServerUrl: json['sendspinServerUrl'] as String?,
          mealieUrl: json['mealieUrl'] as String?,
          mealieToken: json['mealieToken'] as String?,
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

  /// Reads the installed version from /etc/hearth-version (written by the updater).
  String _readInstalledVersion() {
    try {
      return File('/etc/hearth-version').readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleUpdateStatus(HttpRequest request) async {
    final config = _configNotifier.current;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'currentVersion': _readInstalledVersion(),
        'autoUpdate': config.autoUpdate,
      }));
    await request.response.close();
  }

  Future<void> _handleUpdateCheck(HttpRequest request) async {
    final currentVersion = _readInstalledVersion();
    final latest = await _updateService.checkForUpdate();
    final available = latest != null && latest.isNewerThan(currentVersion);
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'currentVersion': currentVersion,
        'latestVersion': latest?.version,
        'updateAvailable': available,
        'bundleUrl': latest?.bundleUrl,
      }));
    await request.response.close();
  }

  Future<void> _handleUpdateApply(HttpRequest request) async {
    try {
      // Trigger the updater via systemd (runs as root with proper privileges)
      final result = await Process.run('sudo', [
        'systemctl', 'start', 'hearth-updater.service',
      ]).timeout(const Duration(seconds: 30));
      request.response
        ..statusCode = result.exitCode == 0 ? 200 : 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': result.exitCode == 0,
          'output': result.stdout.toString(),
          'error': result.stderr.toString(),
        }));
    } catch (e) {
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }
    await request.response.close();
  }

  // --- System stats ---

  Future<void> _handleSystemStats(HttpRequest request) async {
    try {
      // CPU: parse /proc/stat for usage, /sys/class/thermal for temp
      final cpuTemp = await _readFile('/sys/class/thermal/thermal_zone0/temp');
      final tempC = cpuTemp.isNotEmpty ? (int.tryParse(cpuTemp.trim()) ?? 0) / 1000.0 : null;

      final loadavg = await _readFile('/proc/loadavg');
      final loads = loadavg.split(' ');

      // Memory: parse /proc/meminfo
      final meminfo = await _readFile('/proc/meminfo');
      final memMap = <String, int>{};
      for (final line in meminfo.split('\n')) {
        final match = RegExp(r'(\w+):\s+(\d+)').firstMatch(line);
        if (match != null) memMap[match.group(1)!] = int.parse(match.group(2)!);
      }
      final totalMb = (memMap['MemTotal'] ?? 0) ~/ 1024;
      final availMb = (memMap['MemAvailable'] ?? 0) ~/ 1024;
      final usedMb = totalMb - availMb;

      // GPU: try vcgencmd (Pi-specific)
      String? gpuTemp;
      String? gpuMem;
      try {
        final gpuResult = await Process.run('vcgencmd', ['measure_temp']);
        if (gpuResult.exitCode == 0) {
          gpuTemp = RegExp(r'[\d.]+').firstMatch(gpuResult.stdout.toString())?.group(0);
        }
        final memResult = await Process.run('vcgencmd', ['get_mem', 'gpu']);
        if (memResult.exitCode == 0) {
          gpuMem = RegExp(r'\d+').firstMatch(memResult.stdout.toString())?.group(0);
        }
      } catch (_) {}

      // Uptime
      final uptime = await _readFile('/proc/uptime');
      final uptimeSecs = double.tryParse(uptime.split(' ').first) ?? 0;

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'cpu': {
            'tempC': tempC,
            'load1m': loads.isNotEmpty ? loads[0] : null,
            'load5m': loads.length > 1 ? loads[1] : null,
            'load15m': loads.length > 2 ? loads[2] : null,
          },
          'memory': {
            'totalMb': totalMb,
            'usedMb': usedMb,
            'availableMb': availMb,
          },
          'gpu': {
            'tempC': gpuTemp != null ? double.tryParse(gpuTemp) : null,
            'memoryMb': gpuMem != null ? int.tryParse(gpuMem) : null,
          },
          'uptimeSeconds': uptimeSecs.round(),
        }));
    } catch (e) {
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': e.toString()}));
    }
    await request.response.close();
  }

  Future<String> _readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return '';
    }
  }

  // --- Logs ---

  Future<void> _handleGetLogs(HttpRequest request) async {
    final lines = request.uri.queryParameters['lines'] ?? '100';
    try {
      final result = await Process.run('journalctl', [
        '-u', 'hearth.service',
        '--no-pager',
        '-n', lines,
        '--output', 'short-iso',
      ]);
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'logs': result.stdout.toString()}));
    } catch (e) {
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': e.toString()}));
    }
    await request.response.close();
  }

  Future<void> _serveLogsPage(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write(_logsPageHtml);
    await request.response.close();
  }

  // --- Config web page ---

  Future<void> _serveConfigPage(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.add('X-Content-Type-Options', 'nosniff');
    request.response.headers.add('X-Frame-Options', 'DENY');
    request.response.write(_configPageHtml);
    await request.response.close();
  }

  // --- PIN entry page ---

  Future<void> _servePinPage(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write(_pinPageHtml);
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
  final server = LocalApiServer(
    displayModeService: displayService,
    configNotifier: configNotifier,
    wifiService: wifiService,
    updateService: updateService,
  );
  ref.onDispose(() => server.stop());
  return server;
});

final webPinProvider = Provider<String>((ref) {
  return ref.read(localApiServerProvider).webPin;
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
  <div style="display:flex;justify-content:space-between;align-items:center;">
    <h1>Hearth Setup</h1>
    <a href="/logs" style="color:#646cff;font-size:13px;text-decoration:none;">View Logs</a>
  </div>
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

    <h2>Mealie</h2>
    <label for="mealieUrl">Mealie URL</label>
    <input type="text" id="mealieUrl" placeholder="http://192.168.1.x:9925">
    <label for="mealieToken">Mealie API Token</label>
    <div class="secret-wrap">
      <input type="password" id="mealieToken" placeholder="Paste your Mealie API token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
    <div class="hint" id="mealieToken_hint"></div>

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
    <div id="nightModeHaFields" style="display:none;">
      <label for="nightModeHaEntity">Night Mode HA Entity</label>
      <input type="text" id="nightModeHaEntity" placeholder="binary_sensor.night_mode">
    </div>
    <div id="nightModeClockFields" style="display:none;">
      <label for="nightModeClockStart">Clock Start (HH:MM)</label>
      <input type="text" id="nightModeClockStart" placeholder="22:00">
      <label for="nightModeClockEnd">Clock End (HH:MM)</label>
      <input type="text" id="nightModeClockEnd" placeholder="07:00">
    </div>

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
    <label>Update Source</label>
    <select id="updateSource">
      <option value="github">GitHub</option>
      <option value="gitea">Gitea (registry.home)</option>
    </select>
    <div id="giteaTokenRow">
      <label for="giteaApiToken">Gitea API Token</label>
      <input type="password" id="giteaApiToken" placeholder="Paste Gitea read-only token">
    </div>
    <div id="updateInfo" style="margin-bottom:12px;padding:12px;background:#1a1a1a;border-radius:6px;font-size:13px;color:#888;">
      <span id="updateText">Click "Check for Updates" to check.</span>
    </div>
    <div style="display:flex;gap:8px;margin-bottom:16px;">
      <button type="button" onclick="checkUpdate()" style="flex:1;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px;">Check for Updates</button>
      <button type="button" id="applyBtn" onclick="applyUpdate()" style="flex:1;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px;display:none;">Install Update</button>
    </div>

    <button type="submit" class="save">Save</button>
  </form>
  <div class="toast" id="toast"></div>
</div>
<script>
let API_KEY = '';
function getHeaders() {
  return {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + API_KEY};
}
async function initAuth() {
  const r = await fetch('/api/session/key');
  if (r.ok) {
    const d = await r.json();
    API_KEY = d.apiKey;
  }
}

const textFields = [
  'immichUrl','immichApiKey','haUrl','haToken',
  'musicAssistantUrl','musicAssistantToken','defaultMusicZone','frigateUrl',
  'mealieUrl','mealieToken','giteaApiToken',
  'weatherEntityId','nightModeHaEntity','nightModeClockStart','nightModeClockEnd',
  'sendspinPlayerName','sendspinServerUrl'
];
const intFields = ['idleTimeoutSeconds','sendspinBufferSeconds'];
const boolFields = ['use24HourClock','sendspinEnabled','autoUpdate'];
const selectFields = ['nightModeSource','displayProfile','updateSource'];
const secretFields = ['immichApiKey', 'haToken', 'musicAssistantToken', 'mealieToken', 'giteaApiToken'];
const REDACTED = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

async function load() {
  try {
    const r = await fetch('/api/config', {headers: getHeaders()});
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
    toggleGiteaToken();
  } catch(e) { showToast('Failed to load config', true); }
}
function toggleGiteaToken() {
  const src = document.getElementById('updateSource');
  const row = document.getElementById('giteaTokenRow');
  if (src && row) row.style.display = src.value === 'gitea' ? '' : 'none';
}
document.getElementById('updateSource').addEventListener('change', toggleGiteaToken);

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
    const r = await fetch('/api/config', {method: 'POST', headers: getHeaders(), body: JSON.stringify(body)});
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

async function checkUpdate() {
  const txt = document.getElementById('updateText');
  const btn = document.getElementById('applyBtn');
  txt.textContent = 'Checking...';
  txt.style.color = '#888';
  btn.style.display = 'none';
  try {
    const r = await fetch('/api/update/check', {method:'POST', headers: getHeaders()});
    const d = await r.json();
    if (d.updateAvailable) {
      txt.textContent = 'Update available: v' + d.latestVersion + ' (current: v' + (d.currentVersion || 'unknown') + ')';
      txt.style.color = '#fbbf24';
      btn.style.display = 'block';
    } else {
      txt.textContent = 'Up to date' + (d.currentVersion ? ' (v' + d.currentVersion + ')' : '') + (d.latestVersion ? ' — latest: v' + d.latestVersion : '');
      txt.style.color = '#4ade80';
    }
  } catch(e) { txt.textContent = 'Check failed'; txt.style.color = '#f87171'; }
}

async function applyUpdate() {
  const txt = document.getElementById('updateText');
  const btn = document.getElementById('applyBtn');
  txt.textContent = 'Installing update...';
  txt.style.color = '#888';
  btn.style.display = 'none';
  try {
    const r = await fetch('/api/update/apply', {method:'POST', headers: getHeaders()});
    const d = await r.json();
    if (d.success) {
      txt.textContent = 'Update installed! Hearth is restarting...';
      txt.style.color = '#4ade80';
    } else {
      txt.textContent = 'Update failed: ' + (d.error || 'unknown error');
      txt.style.color = '#f87171';
    }
  } catch(e) { txt.textContent = 'Update failed'; txt.style.color = '#f87171'; }
}

function updateNightModeFields() {
  const src = document.getElementById('nightModeSource').value;
  document.getElementById('nightModeHaFields').style.display = src === 'ha_entity' ? '' : 'none';
  document.getElementById('nightModeClockFields').style.display = src === 'clock' ? '' : 'none';
}
document.getElementById('nightModeSource').addEventListener('change', updateNightModeFields);

initAuth().then(() => load().then(() => updateNightModeFields()));
</script>
</body>
</html>
''';

const _logsPageHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth Logs</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #111; color: #e0e0e0;
    display: flex; flex-direction: column; height: 100vh;
    padding: 16px;
  }
  .header {
    display: flex; justify-content: space-between; align-items: center;
    margin-bottom: 12px;
  }
  h1 { font-size: 20px; font-weight: 300; color: #fff; }
  .controls { display: flex; gap: 8px; align-items: center; }
  .controls a {
    color: #646cff; text-decoration: none; font-size: 13px;
  }
  .controls button {
    padding: 6px 14px; background: #333; color: #e0e0e0;
    border: 1px solid #444; border-radius: 6px; cursor: pointer; font-size: 13px;
  }
  .controls select {
    padding: 6px 8px; background: #1e1e1e; border: 1px solid #333;
    border-radius: 6px; color: #e0e0e0; font-size: 13px;
  }
  #logOutput {
    flex: 1; overflow-y: auto; padding: 12px;
    background: #0a0a0a; border: 1px solid #222; border-radius: 6px;
    font-family: "Cascadia Code", "Fira Code", monospace;
    font-size: 12px; line-height: 1.5; white-space: pre-wrap;
    word-break: break-all; color: #aaa;
  }
  .checkbox-label {
    display: flex; align-items: center; gap: 6px;
    font-size: 13px; color: #aaa; cursor: pointer;
  }
  .checkbox-label input { accent-color: #646cff; }
</style>
</head>
<body>
<div class="header">
  <h1>Hearth Logs</h1>
  <div class="controls">
    <a href="/">Settings</a>
    <select id="lineCount">
      <option value="50">50 lines</option>
      <option value="100" selected>100 lines</option>
      <option value="200">200 lines</option>
      <option value="500">500 lines</option>
    </select>
    <label class="checkbox-label">
      <input type="checkbox" id="autoRefresh" checked> Auto-refresh
    </label>
    <button onclick="fetchLogs()">Refresh</button>
  </div>
</div>
<div id="statsBar" style="display:flex;gap:16px;padding:8px 12px;margin-bottom:8px;background:#0a0a0a;border:1px solid #222;border-radius:6px;font-family:monospace;font-size:12px;color:#888;"></div>
<pre id="logOutput">Loading...</pre>
<script>
let API_KEY = '';
function getHeaders() {
  return {'Authorization': 'Bearer ' + API_KEY};
}
async function initAuth() {
  const r = await fetch('/api/session/key');
  if (r.ok) {
    const d = await r.json();
    API_KEY = d.apiKey;
  }
}
let refreshTimer = null;

async function fetchLogs() {
  const lines = document.getElementById('lineCount').value;
  try {
    const r = await fetch('/api/logs?lines=' + lines, {headers: getHeaders()});
    const d = await r.json();
    const el = document.getElementById('logOutput');
    el.textContent = d.logs || d.error || 'No logs';
    el.scrollTop = el.scrollHeight;
  } catch(e) {
    document.getElementById('logOutput').textContent = 'Failed to fetch logs';
  }
}

function toggleAutoRefresh() {
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  if (document.getElementById('autoRefresh').checked) {
    refreshTimer = setInterval(fetchLogs, 3000);
  }
}

document.getElementById('autoRefresh').addEventListener('change', toggleAutoRefresh);
document.getElementById('lineCount').addEventListener('change', fetchLogs);

async function fetchStats() {
  try {
    const r = await fetch('/api/system/stats', {headers: getHeaders()});
    const d = await r.json();
    const bar = document.getElementById('statsBar');
    bar.textContent = '';
    const upH = Math.floor(d.uptimeSeconds / 3600);
    const upM = Math.floor((d.uptimeSeconds % 3600) / 60);
    const memPct = d.memory.totalMb > 0 ? Math.round(d.memory.usedMb / d.memory.totalMb * 100) : 0;
    const items = [
      'CPU: ' + (d.cpu.tempC != null ? d.cpu.tempC.toFixed(1) + '\u00B0C' : '?'),
      'Load: ' + (d.cpu.load1m || '?'),
      'Mem: ' + d.memory.usedMb + '/' + d.memory.totalMb + ' MB (' + memPct + '%)',
      d.gpu.tempC != null ? 'GPU: ' + d.gpu.tempC.toFixed(1) + '\u00B0C' : null,
      'Up: ' + upH + 'h ' + upM + 'm',
    ];
    items.filter(Boolean).forEach(function(text) {
      const span = document.createElement('span');
      span.textContent = text;
      bar.appendChild(span);
    });
  } catch(e) {}
}

initAuth().then(() => { fetchLogs(); fetchStats(); toggleAutoRefresh(); setInterval(fetchStats, 3000); });
</script>
</body>
</html>
''';

// ---------------------------------------------------------------------------
// PIN entry page — shown when a web session is not yet authenticated.
// ---------------------------------------------------------------------------

const _pinPageHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth — Unlock</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #111; color: #e0e0e0;
    display: flex; justify-content: center; align-items: center;
    min-height: 100vh; padding: 24px;
  }
  .card {
    text-align: center; width: 100%; max-width: 340px;
  }
  h1 { font-size: 28px; font-weight: 300; margin-bottom: 8px; color: #fff; }
  p { font-size: 14px; color: #888; margin-bottom: 24px; }
  input#pin {
    width: 160px; padding: 14px; text-align: center;
    font-size: 28px; letter-spacing: 12px;
    background: #1e1e1e; border: 1px solid #333; border-radius: 8px;
    color: #e0e0e0; outline: none;
  }
  input#pin:focus { border-color: #646cff; }
  button {
    display: block; width: 160px; margin: 16px auto 0;
    padding: 12px; background: #646cff; color: #fff;
    border: none; border-radius: 6px; font-size: 15px; cursor: pointer;
  }
  button:hover { background: #535bf2; }
  .error {
    margin-top: 12px; font-size: 13px; color: #f87171;
    min-height: 20px;
  }
</style>
</head>
<body>
<div class="card">
  <h1>Hearth</h1>
  <p>Enter the PIN shown on the kiosk display</p>
  <input type="text" id="pin" inputmode="numeric" maxlength="4" autofocus pattern="[0-9]*">
  <button onclick="unlock()">Unlock</button>
  <div class="error" id="error"></div>
</div>
<script>
document.getElementById('pin').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') unlock();
});

async function unlock() {
  const pin = document.getElementById('pin').value;
  const err = document.getElementById('error');
  err.textContent = '';
  if (pin.length !== 4) { err.textContent = 'Enter a 4-digit PIN'; return; }
  try {
    const r = await fetch('/auth/pin', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({pin: pin})
    });
    if (r.ok) {
      window.location.reload();
    } else {
      err.textContent = 'Wrong PIN';
      document.getElementById('pin').value = '';
      document.getElementById('pin').focus();
    }
  } catch(e) {
    err.textContent = 'Connection error';
  }
}
</script>
</body>
</html>
''';
