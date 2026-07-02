import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../screens/settings/update_settings.dart';
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
///     honors these in scripts/hearth-updater.sh.
///   * Update check / install actions — reuse the existing
///     `/api/update/check` and `/api/update/apply` HTTP routes
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
        _updateButtonsHtml();
  }

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
      if (res.ok) {
        status.textContent = 'Update started. Kiosk will restart shortly.';
      } else {
        status.textContent = 'Install failed: ' + res.status;
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
      if (res.ok) {
        status.textContent = 'Update started. Kiosk will restart shortly.';
      } else {
        status.textContent = 'Force update failed: ' + res.status;
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
