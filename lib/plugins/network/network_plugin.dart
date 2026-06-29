import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/hub_config.dart';
import '../../screens/settings/wifi_settings.dart';
import '../../services/local_api_server.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Resolves the device's primary non-loopback IPv4 address, or null on failure.
///
/// Reuses the setup-wizard pattern ([NetworkInterface.list], first non-loopback
/// IPv4) so the Network settings panel can show the address a user types into a
/// browser to reach the web portal. Degrades gracefully — any failure (no
/// network, platform quirk) resolves to null rather than throwing to the UI.
final deviceIpProvider = FutureProvider<String?>((ref) async {
  try {
    final interfaces = await NetworkInterface.list();
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return null;
});

/// Network plugin — third device-category plugin.
///
/// Owns kiosk networking:
///   * Wi-Fi configuration (scan / connect / known networks) — reuses the
///     existing [WifiSettingsSection] bespoke widget for the on-device panel.
///   * Web Portal PIN — read-only display on-device. The PIN comes from
///     [webPinProvider] (regenerated each app launch); the user cannot change
///     it from settings, only consult it.
///
/// Surface differences:
///   * On-device: full WiFi picker dialog + PIN tile.
///   * Web portal: interactive WiFi UI (Scan / Connect) that calls the legacy
///     `/api/wifi/scan` and `/api/wifi/connect` routes directly. PIN is
///     omitted on the web — the user already saw it on the kiosk before
///     entering the portal, and the on-device Settings panel shows it for
///     reference.
///
/// The legacy `/api/wifi/*` routes stay in [LocalApiServer] for now rather
/// than moving under `/api/plugin/hearth.network/wifi/*`. Plugin HTTP routes
/// don't yet have a way to reach [wifiServiceProvider] (no ProviderContainer
/// in [PluginRequest]) and rewiring that just for this migration would
/// expand scope. See task plan for the deferred follow-up.
///
/// Status is always [PluginConfigStatus.configured] — network state is
/// runtime, not configuration, so there's nothing for the user to "fill in".
class NetworkPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.network';

  @override
  String get name => 'Network';

  @override
  IconData get icon => Icons.wifi;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 60;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Consumer(builder: (context, ref, _) {
      final pin = ref.watch(webPinProvider);
      final ip = ref.watch(deviceIpProvider).asData?.value;
      final ipUrl = ip != null ? 'http://$ip:8090' : null;
      const hostUrl = 'http://hearth.local:8090';
      // Prefer the IP URL for the QR — mDNS `.local` is less reliable to scan
      // from a phone — and fall back to the hostname when no IPv4 resolved.
      final qrData = ipUrl ?? hostUrl;
      const urlStyle = TextStyle(color: Color(0xFF646CFF), fontSize: 16);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WifiSettingsSection(),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language, color: Colors.white54),
            title: const Text(
              'Web Interface',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ipUrl != null) Text(ipUrl, style: urlStyle),
                const Text(hostUrl, style: urlStyle),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // White background + padding so the dark modules scan against the
          // true-black AMOLED theme.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 160,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.pin, color: Colors.white54),
            title: const Text(
              'Web Portal PIN',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              pin,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                letterSpacing: 4,
              ),
            ),
          ),
        ],
      );
    });
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    // Note on JS DOM-safety: the script constructs every list-item with
    // createElement + textContent rather than templating SSIDs into an HTML
    // string. SSIDs come from the WifiService scan which uses NetworkManager
    // (untrusted input from nearby APs), so avoiding innerHTML mitigates XSS
    // via crafted SSIDs.
    return '''
<div class="field">
  <label>WiFi Networks</label>
  <div id="wifi-status" style="color:#888;font-style:italic;margin-bottom:8px">Click "Scan" to discover networks.</div>
  <button type="button" id="wifi-scan-btn" style="padding:8px 16px;background:#646cff;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:13px;margin-bottom:12px">Scan for networks</button>
  <ul id="wifi-list" style="list-style:none;padding:0;margin:0"></ul>
  <div class="hint" style="font-size:11px;color:#666;margin-top:6px">Connection changes apply immediately on the kiosk.</div>
</div>

<script>
(function() {
  const TOKEN = window.__HEARTH_BEARER__;
  const statusEl = document.getElementById('wifi-status');
  const listEl = document.getElementById('wifi-list');
  const btn = document.getElementById('wifi-scan-btn');

  function clearList() {
    while (listEl.firstChild) listEl.removeChild(listEl.firstChild);
  }

  btn.addEventListener('click', async () => {
    statusEl.textContent = 'Scanning...';
    clearList();
    btn.disabled = true;
    try {
      const res = await fetch('/api/wifi/scan', {
        headers: { 'Authorization': 'Bearer ' + TOKEN }
      });
      if (!res.ok) throw new Error('scan failed: ' + res.status);
      const data = await res.json();
      const networks = data.networks || [];
      if (networks.length === 0) {
        statusEl.textContent = 'No networks found.';
      } else {
        statusEl.textContent = networks.length + ' networks found';
        networks.forEach(net => {
          const ssid = net.ssid || net.SSID || '';
          const signal = (net.signalStrength != null)
            ? (net.signalStrength + '%')
            : (net.signal || '');
          const li = document.createElement('li');
          li.style.cssText = 'padding:8px 12px;background:#161618;border-radius:6px;margin-bottom:4px;display:flex;align-items:center;gap:8px';
          const ssidSpan = document.createElement('span');
          ssidSpan.style.cssText = 'flex:1;color:#fff';
          ssidSpan.textContent = ssid;
          const signalSpan = document.createElement('span');
          signalSpan.style.cssText = 'color:#888;font-size:11px';
          signalSpan.textContent = signal;
          const connectBtn = document.createElement('button');
          connectBtn.type = 'button';
          connectBtn.dataset.ssid = ssid;
          connectBtn.style.cssText = 'padding:4px 12px;background:#333;color:#e0e0e0;border:none;border-radius:4px;cursor:pointer;font-size:12px';
          connectBtn.textContent = 'Connect';
          connectBtn.addEventListener('click', async (ev) => {
            const target = ev.currentTarget;
            const targetSsid = target.dataset.ssid;
            const password = prompt('Password for ' + targetSsid + ':');
            if (password === null) return;
            target.textContent = 'Connecting...';
            target.disabled = true;
            try {
              const cres = await fetch('/api/wifi/connect', {
                method: 'POST',
                headers: { 'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json' },
                body: JSON.stringify({ ssid: targetSsid, password: password })
              });
              if (cres.ok) {
                target.textContent = 'Connected';
              } else {
                target.textContent = 'Failed';
                target.disabled = false;
              }
            } catch (e) {
              target.textContent = 'Error';
              target.disabled = false;
            }
          });
          li.appendChild(ssidSpan);
          li.appendChild(signalSpan);
          li.appendChild(connectBtn);
          listEl.appendChild(li);
        });
      }
    } catch (e) {
      statusEl.textContent = 'Scan error: ' + e.message;
    } finally {
      btn.disabled = false;
    }
  });
})();
</script>
''';
  }
}
