import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/capture_service.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Capture plugin — screenshots, screen recordings, and the touch-indicator
/// overlay used for marketing captures.
///
/// Conditionally visible: it only appears as a sidebar entry (on both the web
/// portal and the on-device settings sidebar) when [HubConfig.captureToolsEnabled]
/// is true. The enable toggle itself lives in the System plugin — a hidden
/// plugin can't host its own on-switch.
///
/// Surface differences:
///   * Web portal: the full interactive tools — take screenshot, start/stop
///     recording, a gallery with download + delete, and the touch-indicator
///     controls. Downloading screenshots/recordings needs a browser, so these
///     live on the web only.
///   * On-device: settings only — the touch-indicator controls plus a note
///     pointing to the web portal for screenshots/recordings/gallery.
///
/// Backend routes are registered under `/api/plugin/hearth.capture/*` and each
/// enforces the [HubConfig.captureToolsEnabled] gate itself (returning 404 when
/// off) — plugin routes are not auto-gated by [isVisible].
class CapturePlugin extends HearthPlugin {
  @override
  String get id => 'hearth.capture';

  @override
  String get name => 'Capture';

  @override
  IconData get icon => Icons.screen_share;

  @override
  PluginCategory get category => PluginCategory.device;

  // Just above System (70) — capture is a device dev-tool that pairs with the
  // System plugin's enable toggle.
  @override
  int get order => 65;

  @override
  bool get isCommunity => false;

  @override
  bool isVisible(HubConfig config) => config.captureToolsEnabled;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const _CapturePanel();

  @override
  String buildSettingsHtml(WebContext ctx) => _captureHtml;

  @override
  void registerHttpRoutes(PluginRouter router) {
    router.post('screenshot', _screenshot);
    router.post('recording/start', _recordingStart);
    router.post('recording/stop', _recordingStop);
    router.get('list', _list);
    router.get('file', _fileDownload);
    router.delete('file', _fileDelete);
    router.get('indicator-config', _indicatorGet);
    router.post('indicator-config', _indicatorPost);
  }

  // --- Route handlers ---
  //
  // Every handler first enforces the enable gate, then reaches the live
  // [CaptureService] singleton through [PluginRequest.readProvider] — the same
  // service the on-device overlay uses.

  /// Returns true (and writes a 404) when capture tools are disabled, matching
  /// the old `/api/capture/*` gate. Callers bail when this returns true.
  Future<bool> _gated(PluginRequest req) async {
    if (req.config.captureToolsEnabled) return false;
    req.raw.response.statusCode = 404;
    req.raw.response.headers.contentType = ContentType.json;
    req.raw.response.write(jsonEncode({'error': 'not found'}));
    await req.raw.response.close();
    return true;
  }

  Future<void> _screenshot(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    final file = await capture.takeScreenshot();
    await req.respondJson({
      'filename': file.filename,
      'path': file.path,
      'sizeBytes': file.sizeBytes,
      'createdAt': file.createdAt.toIso8601String(),
    });
  }

  Future<void> _recordingStart(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    try {
      final started = await capture.startRecording();
      await req.respondJson({
        'filename': started.filename,
        'startedAt': started.startedAt.toIso8601String(),
      });
    } on StateError catch (e) {
      req.raw.response.statusCode = 409;
      req.raw.response.headers.contentType = ContentType.json;
      req.raw.response.write(jsonEncode({
        'error': 'recording already active',
        'activeFilename': capture.activeRecordingFilename,
        'detail': e.message,
      }));
      await req.raw.response.close();
    }
  }

  Future<void> _recordingStop(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    try {
      final meta = await capture.stopRecording();
      // meta.createdAt is the recording's startedAt (see CaptureService.stopRecording).
      final duration = DateTime.now().difference(meta.createdAt).inSeconds;
      await req.respondJson({
        'filename': meta.filename,
        'sizeBytes': meta.sizeBytes,
        'durationSeconds': duration,
      });
    } on StateError catch (e) {
      await req.respondError(400, 'no active recording');
      // respondError already closed the response; surface detail in the log.
      debugPrint('Capture: stop with no active recording: ${e.message}');
    }
  }

  Future<void> _list(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    final items = await capture.listCaptures();
    await req.respondJson([
      for (final f in items)
        {
          'filename': f.filename,
          'type': f.filename.endsWith('.mp4') ? 'mp4' : 'png',
          'sizeBytes': f.sizeBytes,
          'createdAt': f.createdAt.toIso8601String(),
        },
    ]);
  }

  Future<void> _fileDownload(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    final name = req.raw.uri.queryParameters['name'] ?? '';
    if (!CaptureService.isValidCaptureFilename(name)) {
      await req.respondError(400, 'invalid filename');
      return;
    }
    final file = capture.captureFileHandle(name);
    if (!await file.exists()) {
      await req.respondError(404, 'not found');
      return;
    }
    req.raw.response.statusCode = 200;
    req.raw.response.headers.contentType = name.endsWith('.mp4')
        ? ContentType('video', 'mp4')
        : ContentType('image', 'png');
    req.raw.response.headers
        .add('Content-Disposition', 'attachment; filename="$name"');
    await file.openRead().pipe(req.raw.response);
  }

  Future<void> _fileDelete(PluginRequest req) async {
    if (await _gated(req)) return;
    final capture = req.readProvider(captureServiceProvider);
    final name = req.raw.uri.queryParameters['name'] ?? '';
    if (!CaptureService.isValidCaptureFilename(name)) {
      await req.respondError(400, 'invalid filename');
      return;
    }
    final removed = await capture.deleteCapture(name);
    if (!removed) {
      await req.respondError(404, 'not found');
      return;
    }
    await req.respondJson({'status': 'deleted'});
  }

  Future<void> _indicatorGet(PluginRequest req) async {
    if (await _gated(req)) return;
    await req.respondJson(req.config.touchIndicator.toJson());
  }

  Future<void> _indicatorPost(PluginRequest req) async {
    if (await _gated(req)) return;
    final current = req.config.touchIndicator;
    TouchIndicatorStyle? parsedStyle;
    if (req.body['style'] is String) {
      parsedStyle = TouchIndicatorStyle.values.firstWhere(
        (s) => s.name == req.body['style'],
        orElse: () => current.style,
      );
    }
    final merged = current.copyWith(
      enabled: req.body['enabled'] as bool?,
      colorArgb: req.body['colorArgb'] as int?,
      radius: (req.body['radius'] as num?)?.toDouble(),
      fadeMs: req.body['fadeMs'] as int?,
      style: parsedStyle,
    );
    await req.updateConfig((c) => c.copyWith(touchIndicator: merged));
    await req.respondJson({'status': 'saved', 'config': merged.toJson()});
  }
}

/// On-device Capture panel — settings only. The touch-indicator controls write
/// straight to [HubConfig.touchIndicator]; a note points users to the web
/// portal for the interactive screenshot/recording/gallery tools (which need a
/// browser to download files).
class _CapturePanel extends ConsumerStatefulWidget {
  const _CapturePanel();

  @override
  ConsumerState<_CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<_CapturePanel> {
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    final indicator = ref.read(hubConfigProvider).touchIndicator;
    _colorController = TextEditingController(text: _formatColor(indicator.colorArgb));
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  static String _formatColor(int argb) =>
      '0x${(argb & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0')}';

  void _update(TouchIndicatorConfig Function(TouchIndicatorConfig) updater) {
    ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(touchIndicator: updater(c.touchIndicator)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final indicator = ref.watch(hubConfigProvider).touchIndicator;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Screenshots, recordings, and the gallery are managed from the '
            'web portal — downloading capture files needs a browser.',
            style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
          ),
        ),
        const Text(
          'Touch indicator',
          style: TextStyle(
            color: Color(0xFF888888),
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: indicator.enabled,
          onChanged: (v) => _update((i) => i.copyWith(enabled: v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _colorController,
            decoration: const InputDecoration(
              labelText: 'Color (ARGB hex)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) {
              final parsed = int.tryParse(text.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''), radix: 16);
              if (parsed != null) {
                _update((i) => i.copyWith(colorArgb: parsed));
              }
            },
          ),
        ),
        Text('Radius: ${indicator.radius.round()} px',
            style: const TextStyle(color: Colors.white70)),
        Slider(
          min: 10,
          max: 80,
          value: indicator.radius.clamp(10, 80),
          onChanged: (v) => _update((i) => i.copyWith(radius: v)),
        ),
        Text('Fade: ${indicator.fadeMs} ms',
            style: const TextStyle(color: Colors.white70)),
        Slider(
          min: 200,
          max: 2000,
          divisions: 36,
          value: indicator.fadeMs.toDouble().clamp(200, 2000),
          onChanged: (v) => _update((i) => i.copyWith(fadeMs: v.round())),
        ),
        const SizedBox(height: 8),
        const Text('Style', style: TextStyle(color: Colors.white70)),
        DropdownButton<TouchIndicatorStyle>(
          value: indicator.style,
          dropdownColor: const Color(0xFF1e1e1e),
          items: [
            for (final s in TouchIndicatorStyle.values)
              DropdownMenuItem(value: s, child: Text(_styleLabel(s))),
          ],
          onChanged: (s) {
            if (s != null) _update((i) => i.copyWith(style: s));
          },
        ),
      ],
    );
  }

  static String _styleLabel(TouchIndicatorStyle s) {
    switch (s) {
      case TouchIndicatorStyle.ripple:
        return 'Ripple';
      case TouchIndicatorStyle.solid:
        return 'Solid';
      case TouchIndicatorStyle.trail:
        return 'Trail';
    }
  }
}

/// Self-contained web panel ported from the legacy `/capture` page. CSS is
/// scoped under `#capture-panel` so it doesn't clobber the settings shell, and
/// every fetch is repointed from `/api/capture/*` to this plugin's route
/// prefix. The bearer token and prefix are read at DOMContentLoaded — the page
/// sets `window.__HEARTH_BEARER__` / `window.__HEARTH_PLUGIN_PREFIX__` in a
/// script that runs *after* this fragment, so reading them eagerly would race.
const _captureHtml = r'''
<style>
  #capture-panel h2 { font-size: 11px; font-weight: 600; letter-spacing: 1.2px; color: #888;
       text-transform: uppercase; margin: 20px 0 8px; }
  #capture-panel button { padding: 10px 16px; background: #333; color: #e0e0e0;
           border: 1px solid #444; border-radius: 6px; cursor: pointer; font-size: 13px; }
  #capture-panel button.primary { background: #646cff; color: #fff; border: none; }
  #capture-panel button.primary:hover { background: #535bf2; }
  #capture-panel button.recording { background: #ef4444; color: #fff; border: none; }
  #capture-panel .controls { display: flex; gap: 8px; align-items: center; }
  #capture-panel .recording-status { color: #ef4444; font-family: monospace; font-size: 13px; }
  #capture-panel label { display: block; font-size: 13px; color: #aaa; margin: 8px 0 4px; }
  #capture-panel input, #capture-panel select {
    padding: 8px 10px; background: #1e1e1e; border: 1px solid #333;
    border-radius: 6px; color: #e0e0e0; font-size: 13px; outline: none;
  }
  #capture-panel input[type="range"] { width: 200px; }
  #capture-panel .row { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; }
  #capture-panel table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  #capture-panel th, #capture-panel td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #222;
           font-size: 13px; }
  #capture-panel th { color: #888; font-weight: 500; }
  #capture-panel td a { color: #646cff; text-decoration: none; margin-right: 12px; }
  #capture-panel td button.del { color: #f87171; background: none; border: none; cursor: pointer; font-size: 14px; }
  #capture-panel .toast { position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
           background: #2a2a2a; color: #4ade80; padding: 10px 20px; border-radius: 6px;
           opacity: 0; transition: opacity 0.3s; font-size: 13px; }
  #capture-panel .toast.show { opacity: 1; }
  #capture-panel .toast.error { color: #f87171; }
</style>
<div id="capture-panel">
<h2>Controls</h2>
<div class="controls">
  <button class="primary" id="cap-screenshot">Take Screenshot</button>
  <button id="recBtn">Start Recording</button>
  <span id="recStatus" class="recording-status"></span>
</div>

<h2>Touch Indicator</h2>
<div class="row"><label><input type="checkbox" id="ind_enabled"> Enabled</label></div>
<div class="row"><label>Color (ARGB hex)</label><input type="text" id="ind_color" size="10"></div>
<div class="row"><label>Radius <span id="ind_radius_v"></span> px</label>
  <input type="range" id="ind_radius" min="10" max="80" step="1"></div>
<div class="row"><label>Fade <span id="ind_fade_v"></span> ms</label>
  <input type="range" id="ind_fade" min="200" max="2000" step="50"></div>
<div class="row"><label>Style</label>
  <select id="ind_style">
    <option value="ripple">Ripple</option>
    <option value="solid">Solid</option>
    <option value="trail">Trail</option>
  </select></div>

<h2>Captures</h2>
<table>
  <thead><tr><th>Filename</th><th>Type</th><th>Size</th><th>Created</th><th></th></tr></thead>
  <tbody id="gallery"></tbody>
</table>

<div class="toast" id="toast"></div>
</div>

<script>
(function () {
  function init() {
    var API_KEY = window.__HEARTH_BEARER__;
    var PREFIX = window.__HEARTH_PLUGIN_PREFIX__;
    var recStart = null;
    var recTimer = null;

    function headers() { return {'Authorization': 'Bearer ' + API_KEY, 'Content-Type': 'application/json'}; }
    function toast(msg, err) {
      var t = document.getElementById('toast');
      t.textContent = msg;
      t.className = 'toast show' + (err ? ' error' : '');
      setTimeout(function () { t.className = 'toast'; }, 2000);
    }

    async function takeScreenshot() {
      try {
        var r = await fetch(PREFIX + '/screenshot', {method: 'POST', headers: headers()});
        if (!r.ok) throw 0;
        toast('Screenshot saved');
        loadGallery();
      } catch (e) { toast('Screenshot failed', true); }
    }

    async function toggleRecording() {
      var btn = document.getElementById('recBtn');
      if (!recStart) {
        try {
          var r = await fetch(PREFIX + '/recording/start', {method: 'POST', headers: headers()});
          if (!r.ok) throw 0;
          recStart = Date.now();
          btn.textContent = 'Stop Recording';
          btn.className = 'recording';
          recTimer = setInterval(updateTimer, 1000);
          updateTimer();
        } catch (e) { toast('Start failed', true); }
      } else {
        try {
          var r = await fetch(PREFIX + '/recording/stop', {method: 'POST', headers: headers()});
          if (!r.ok) throw 0;
          toast('Recording saved');
        } catch (e) { toast('Stop failed', true); }
        recStart = null;
        btn.textContent = 'Start Recording';
        btn.className = '';
        clearInterval(recTimer);
        document.getElementById('recStatus').textContent = '';
        loadGallery();
      }
    }

    function updateTimer() {
      if (!recStart) return;
      var secs = Math.floor((Date.now() - recStart) / 1000);
      var mm = String(Math.floor(secs / 60)).padStart(2, '0');
      var ss = String(secs % 60).padStart(2, '0');
      document.getElementById('recStatus').textContent = 'Recording ' + mm + ':' + ss;
    }

    function fmtSize(b) {
      if (b < 1024) return b + ' B';
      if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB';
      return (b / 1024 / 1024).toFixed(1) + ' MB';
    }

    async function loadGallery() {
      try {
        var r = await fetch(PREFIX + '/list', {headers: headers()});
        var items = await r.json();
        var tb = document.getElementById('gallery');
        tb.textContent = '';
        if (!items.length) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 5;
          td.style.color = '#666';
          td.style.textAlign = 'center';
          td.style.padding = '24px';
          td.textContent = 'No captures yet.';
          tr.appendChild(td);
          tb.appendChild(tr);
          return;
        }
        for (var i = 0; i < items.length; i++) {
          var it = items[i];
          var tr = document.createElement('tr');
          var td1 = document.createElement('td');
          td1.textContent = it.filename;
          var td2 = document.createElement('td');
          td2.textContent = it.type.toUpperCase();
          var td3 = document.createElement('td');
          td3.textContent = fmtSize(it.sizeBytes);
          var td4 = document.createElement('td');
          td4.textContent = new Date(it.createdAt).toLocaleString();
          var td5 = document.createElement('td');
          var dl = document.createElement('a');
          dl.href = PREFIX + '/file?name=' + encodeURIComponent(it.filename);
          dl.textContent = 'Download';
          var delBtn = document.createElement('button');
          delBtn.className = 'del';
          delBtn.textContent = 'Delete';
          (function (name) {
            delBtn.addEventListener('click', function () { deleteFile(name); });
          })(it.filename);
          td5.appendChild(dl);
          td5.appendChild(delBtn);
          tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3); tr.appendChild(td4); tr.appendChild(td5);
          tb.appendChild(tr);
        }
      } catch (e) { toast('Failed to load gallery', true); }
    }

    async function deleteFile(name) {
      try {
        var r = await fetch(PREFIX + '/file?name=' + encodeURIComponent(name),
          {method: 'DELETE', headers: headers()});
        if (!r.ok) throw 0;
        loadGallery();
      } catch (e) { toast('Delete failed', true); }
    }

    async function loadIndicator() {
      try {
        var r = await fetch(PREFIX + '/indicator-config', {headers: headers()});
        var c = await r.json();
        document.getElementById('ind_enabled').checked = c.enabled;
        document.getElementById('ind_color').value = '0x' + (c.colorArgb >>> 0).toString(16).toUpperCase().padStart(8, '0');
        document.getElementById('ind_radius').value = c.radius;
        document.getElementById('ind_radius_v').textContent = c.radius;
        document.getElementById('ind_fade').value = c.fadeMs;
        document.getElementById('ind_fade_v').textContent = c.fadeMs;
        document.getElementById('ind_style').value = c.style;
      } catch (e) {}
    }

    var saveTimer = null;
    function scheduleSave() {
      if (saveTimer) clearTimeout(saveTimer);
      saveTimer = setTimeout(saveIndicator, 300);
    }

    async function saveIndicator() {
      var body = {
        enabled: document.getElementById('ind_enabled').checked,
        colorArgb: parseInt(document.getElementById('ind_color').value.replace(/^0x/i, ''), 16),
        radius: parseFloat(document.getElementById('ind_radius').value),
        fadeMs: parseInt(document.getElementById('ind_fade').value),
        style: document.getElementById('ind_style').value,
      };
      document.getElementById('ind_radius_v').textContent = body.radius;
      document.getElementById('ind_fade_v').textContent = body.fadeMs;
      try {
        await fetch(PREFIX + '/indicator-config',
          {method: 'POST', headers: headers(), body: JSON.stringify(body)});
      } catch (e) { toast('Save failed', true); }
    }

    document.getElementById('cap-screenshot').addEventListener('click', takeScreenshot);
    document.getElementById('recBtn').addEventListener('click', toggleRecording);
    ['ind_enabled', 'ind_color', 'ind_radius', 'ind_fade', 'ind_style'].forEach(function (id) {
      document.getElementById(id).addEventListener('input', scheduleSave);
      document.getElementById(id).addEventListener('change', scheduleSave);
    });

    loadIndicator();
    loadGallery();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
</script>
''';
