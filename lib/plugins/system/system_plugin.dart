import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../screens/settings/update_settings.dart';
import '../../services/app_restarter.dart';
import '../../services/backup/backup_service.dart';
import '../../utils/logger.dart';
import '../framework/plugin_router.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// System plugin — fourth device-category plugin.
///
/// Owns kiosk system controls:
///   * `autoUpdate` — install daily updates automatically
///   * `giteaApiToken` — web-only; typing a long token via OSK is painful,
///     so we expose it only in the web portal
///   * `captureToolsEnabled` — gates the Capture plugin's sidebar entry
///     (screenshots + recording)
///   * `devBundleEnabled` / `devBundleUrl` — developer OTA override. The URL is
///     web-only (OSK-hostile); the toggle is on both surfaces. The updater
///     honors these in scripts/hearth-updater.sh, and `AppUpdater` on Android
///     when the URL is an `.apk`.
///   * Update check / install actions — reuse the existing
///     `/api/update/check` and `/api/update/apply` HTTP routes
///   * Backup & Restore — portal only: `GET backup` downloads the whole
///     config, alarms and Sendspin secrets; `POST restore` writes them back
///     and restarts the kiosk. Both need the PIN session, not the bearer key
///     (see `LocalApiServer._sessionOnlyPluginPaths`). Design:
///     `docs/specs/2026-10-16-backup-restore-design.md`.
///   * Open-source licences — Flutter's licence page on-device, `/licenses`
///     in the portal. Both list [LicenseRegistry], which holds the Dart
///     packages and the notices in `assets/licenses/`.
///
/// Surface differences:
///   * On-device: full version display + auto-update toggle + force-update
///     button via the bespoke [UpdateSettingsSection] widget. Gitea API
///     token is NOT shown — set it from the web portal.
///   * Web portal: auto-update + capture-tools toggles, gitea token input,
///     and check/install buttons that call the existing update routes.
///
/// Status: always [PluginConfigStatus.configured] — every field has a sane
/// default and update controls are runtime actions, not setup state.
class SystemPlugin extends HearthPlugin {
  /// How long a restore waits after its response before restarting, so the
  /// portal hears the answer first.
  final Duration restartDelay;

  SystemPlugin({this.restartDelay = const Duration(milliseconds: 500)});

  @override
  String get id => 'hearth.system';

  @override
  String get name => 'System';

  @override
  IconData get icon => Icons.settings_applications;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 70;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('backup', _backup);
    router.post('restore', _restore);
  }

  Future<void> _backup(PluginRequest req) async {
    final service = req.readProvider(backupServiceProvider);
    final backup = await service.create();
    final response = req.raw.response;
    response.statusCode = 200;
    response.headers.contentType = ContentType.json;
    response.headers.add('Content-Disposition',
        'attachment; filename="${service.fileName()}"');
    response.write(const JsonEncoder.withIndent('  ').convert(backup));
    await response.close();
  }

  Future<void> _restore(PluginRequest req) async {
    final SendspinRestore sendspin;
    try {
      sendspin = await req.readProvider(backupServiceProvider).restore(req.body);
    } on BackupRejected catch (e) {
      await req.respondError(400, e.message);
      return;
    } catch (e) {
      // A write failed. The Sendspin keys are written first, so most failures
      // leave the config and alarms as they were.
      Log.e('Backup', 'Restore failed: $e');
      await req.respondError(500, 'Restore failed: $e');
      return;
    }
    final restarter = req.readProvider(appRestarterProvider);
    final restart = restarter.canRestart;
    await req.respondJson({
      'status': restart ? 'restarting' : 'restartManually',
      'sendspin': sendspin.name,
    });
    if (restart) unawaited(Future.delayed(restartDelay, restarter.restart));
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UpdateSettingsSection(),
        const SizedBox(height: 16),
        const BoolSettingField(
          label: 'Capture tools',
          icon: Icons.screen_share,
          configPath: 'captureToolsEnabled',
          subtitle: 'Enable screenshot/recording in the web portal',
        ).buildWidget(ref),
        const BoolSettingField(
          label: 'Dev bundle',
          icon: Icons.science_outlined,
          configPath: 'devBundleEnabled',
          subtitle: 'Load a bundle from a custom URL (set the URL in the web portal)',
        ).buildWidget(ref),
        // Gitea API token and the dev bundle URL are NOT shown on-device —
        // typing long strings via OSK is painful. Set them from the web portal.
        const SizedBox(height: 16),
        const _LicensesTile(),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const BoolSettingField(
          label: 'Auto-update',
          configPath: 'autoUpdate',
          subtitle: 'Automatically install daily updates',
        ).buildHtml(ctx) +
        const SelectSettingField(
          label: 'Update Source',
          configPath: 'updateSource',
          options: {
            'github': 'GitHub',
            'gitea': 'Gitea (registry.home)',
          },
        ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'giteaApiToken',
          label: 'Gitea API Token',
          hint: 'For private OTA builds (advanced)',
        ).buildHtml(ctx) +
        const BoolSettingField(
          label: 'Capture tools',
          configPath: 'captureToolsEnabled',
          subtitle: 'Enable screenshot/recording UI',
        ).buildHtml(ctx) +
        const TextSettingField(
          label: 'Dev bundle URL',
          configPath: 'devBundleUrl',
          hint: 'https://…/hearth-bundle-x.y.z.tar.gz',
        ).buildHtml(ctx) +
        const BoolSettingField(
          label: 'Dev bundle',
          configPath: 'devBundleEnabled',
          subtitle: 'Install from the URL above on the next update (skips release check)',
        ).buildHtml(ctx) +
        _updateButtonsHtml() +
        _backupHtml +
        _licensesHtml;
  }

  static const _licensesHtml = '''
<div class="field">
  <label>Open-source licences</label>
  <div class="hint"><a href="/licenses" target="_blank" style="color:#646CFF">View the licences for the code and content Hearth ships</a></div>
</div>
''';

  static const _buttonStyle =
      'padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;'
      'border-radius:6px;cursor:pointer;font-size:13px';

  static const _backupHtml = '''
<div class="field">
  <label>Backup &amp; Restore</label>
  <div class="hint">The file contains every password and token Hearth uses. Keep it somewhere safe.</div>
  <a id="backup-download" href="/api/plugin/hearth.system/backup" style="display:block;text-align:center;text-decoration:none;margin-top:8px;$_buttonStyle">Download backup</a>
  <div style="display:flex;gap:8px;margin-top:8px;align-items:center">
    <input type="file" id="restore-file" accept=".json,application/json" style="flex:1;font-size:13px;color:#e0e0e0">
    <button type="button" id="restore-btn" style="$_buttonStyle" disabled>Restore</button>
  </div>
  <div id="restore-status" class="hint" style="font-size:12px;color:#888;margin-top:6px"></div>
</div>
<script>
(function() {
  const input = document.getElementById('restore-file');
  const btn = document.getElementById('restore-btn');
  const status = document.getElementById('restore-status');
  input.addEventListener('change', () => { btn.disabled = !input.files.length; });

  // Sessions live in memory, so this session's key turns 401 once the
  // restarted kiosk is answering, however quickly it came back.
  async function awaitRestart() {
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 2000));
      try {
        const res = await fetch('/api/session/key', { cache: 'no-store' });
        if (res.status === 401) { location.reload(); return; }
      } catch (_) {}
    }
    status.textContent = 'The kiosk did not come back. Check it and restart Hearth by hand.';
  }

  btn.addEventListener('click', async () => {
    const file = input.files[0];
    if (!file) return;
    if (!confirm('This replaces all settings on this kiosk and restarts it. Continue?')) return;
    btn.disabled = true;
    status.textContent = 'Restoring...';
    try {
      const res = await fetch('/api/plugin/hearth.system/restore', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: await file.text(),
      });
      let data = {};
      try { data = await res.json(); } catch (_) {}
      if (!res.ok) {
        status.textContent = data.error || ('Restore failed: ' + res.status);
        btn.disabled = false;
        return;
      }
      const note = data.sendspin === 'skipped'
        ? ' Sendspin pairing was not restored (backup is from another platform).'
        : '';
      if (data.status === 'restarting') {
        status.textContent = 'Restored — restarting…' + note;
        awaitRestart();
      } else {
        status.textContent = 'Restored. Restart Hearth to finish.' + note;
      }
    } catch (e) {
      status.textContent = 'Restore error: ' + e.message;
      btn.disabled = false;
    }
  });
})();
</script>
''';

  String _updateButtonsHtml() {
    return '''
<div class="field">
  <label>System updates</label>
  <div style="display:flex;gap:8px;margin-top:8px">
    <button type="button" id="check-updates-btn" style="flex:1;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px">Check for Updates</button>
    <button type="button" id="apply-update-btn" style="flex:1;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px;display:none">Install Update</button>
  </div>
  <button type="button" id="force-update-btn" style="width:100%;margin-top:8px;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px">Force Update</button>
  <div id="update-status" class="hint" style="font-size:12px;color:#888;margin-top:6px"></div>
</div>

<script>
(function() {
  const TOKEN = window.__HEARTH_BEARER__;
  const checkBtn = document.getElementById('check-updates-btn');
  const applyBtn = document.getElementById('apply-update-btn');
  const forceBtn = document.getElementById('force-update-btn');
  const status = document.getElementById('update-status');

  async function updateMessage(res) {
    try { return (await res.json()).message || ''; } catch (_) { return ''; }
  }

  checkBtn.addEventListener('click', async () => {
    status.textContent = 'Checking...';
    checkBtn.disabled = true;
    try {
      const res = await fetch('/api/update/check', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + TOKEN }
      });
      if (!res.ok) throw new Error(res.status);
      const data = await res.json();
      if (data.updateAvailable) {
        status.textContent = 'Update available: v' + (data.latestVersion || 'unknown');
        applyBtn.style.display = 'block';
      } else {
        status.textContent = 'Up to date.';
      }
    } catch (e) {
      status.textContent = 'Check failed: ' + e.message;
    } finally {
      checkBtn.disabled = false;
    }
  });

  applyBtn.addEventListener('click', async () => {
    if (!confirm('Install update? The kiosk will restart.')) return;
    status.textContent = 'Installing...';
    applyBtn.disabled = true;
    try {
      const res = await fetch('/api/update/apply', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + TOKEN }
      });
      // Android reports where it stopped in `message`; the Pi does not.
      const msg = await updateMessage(res);
      if (res.ok) {
        status.textContent = msg || 'Update started. Kiosk will restart shortly.';
      } else {
        status.textContent = msg || ('Install failed: ' + res.status);
        applyBtn.disabled = false;
      }
    } catch (e) {
      status.textContent = 'Install error: ' + e.message;
      applyBtn.disabled = false;
    }
  });

  // Force update — download and install the latest bundle without a prior
  // check, matching the on-device Force Update affordance. Hits the same
  // /api/update/apply route.
  forceBtn.addEventListener('click', async () => {
    if (!confirm('Force download and install the latest bundle? The kiosk will restart.')) return;
    status.textContent = 'Forcing update...';
    forceBtn.disabled = true;
    try {
      const res = await fetch('/api/update/apply', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + TOKEN }
      });
      const msg = await updateMessage(res);
      if (res.ok) {
        status.textContent = msg || 'Update started. Kiosk will restart shortly.';
      } else {
        status.textContent = msg || ('Force update failed: ' + res.status);
        forceBtn.disabled = false;
      }
    } catch (e) {
      status.textContent = 'Force update error: ' + e.message;
      forceBtn.disabled = false;
    }
  });
})();
</script>
''';
  }
}

class _LicensesTile extends ConsumerWidget {
  const _LicensesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(installedVersionProvider).valueOrNull ?? '';
    return ListTile(
      leading: const Icon(Icons.gavel_outlined,
          color: Colors.white54, size: HearthIcon.md),
      title: const Text('Open-source licences',
          style: TextStyle(fontSize: HearthFont.body)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'Hearth',
        applicationVersion: version,
        applicationLegalese: 'MIT License',
      ),
    );
  }
}
