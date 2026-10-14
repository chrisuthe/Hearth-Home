import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/toast_service.dart';
import '../../services/voice_assistant_service.dart';
import '../../services/voice_satellite_bridge.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/plugin_router.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Voice plugin — first device-category plugin.
///
/// Owns kiosk-side voice settings:
///   * `micMuted` — the on-device toggle mutes the LVA satellite by driving its
///     HA Mute switch (via [VoiceAssistantService.setSatelliteMuted]) and shows
///     a toast. The in-app satellite on Android is muted by `micMuted` alone,
///     through the bridge. `micMuted` is kept as the persisted local intent / display
///     hint. The on-device toggle is semantically inverted (UI shows
///     "Microphone on/off", config stores "muted"); the web checkbox is
///     presented as a raw "Mute microphone" option so the bool maps directly to
///     the field and `hearth.js` needs no special-case inversion handling.
///   * `showVoiceFeedback` — toggles the floating voice-pill overlay.
///   * On Android only, the in-app voice satellite: on/off, name, wake words,
///     sensitivity, wake sound and audio source, plus read-only MAC,
///     connection state and last health event. The group is absent on every
///     other platform, on both surfaces. The web portal is served by the
///     kiosk itself, so "on Android" means the kiosk, not the browser.
///
/// Status is always [PluginConfigStatus.configured] — these are toggles, not
/// configuration that can be "missing".
///
/// NOTE: The HA mute side effect only fires on-device. When the web client
/// updates `micMuted` via `/api/config`, the server-side update path applies
/// the config change without driving HA.
class VoicePlugin extends HearthPlugin {
  @override
  String get id => 'hearth.voice';

  @override
  String get name => 'Voice';

  @override
  IconData get icon => Icons.record_voice_over;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 30;

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
        BoolSettingField(
          label: 'Microphone',
          icon: Icons.mic,
          // micMuted=true means the mic is muted. The toggle in the UI is
          // "Microphone (on/off)" — semantically inverted.
          // Read: !config.micMuted -> listening=true
          // Write: !value -> micMuted
          readOverride: (c) => !c.micMuted,
          writeOverride: (ref, listening) async {
            final muted = !listening;
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update((c) => c.copyWith(micMuted: muted));
            // Side effect: actually mute/unmute the LVA satellite via HA.
            ref.read(voiceAssistantServiceProvider).setSatelliteMuted(muted);
            // Show a toast notification (matching legacy behaviour).
            ref.read(toastProvider.notifier).show(
                  muted ? 'Microphone muted' : 'Microphone unmuted',
                  icon: muted ? Icons.mic_off : Icons.mic,
                );
          },
        ).buildWidget(ref),
        const BoolSettingField(
          label: 'Show voice feedback',
          icon: Icons.notifications,
          configPath: 'showVoiceFeedback',
          subtitle: 'Voice pill overlay during interactions',
        ).buildWidget(ref),
        if (voiceSatelliteSupported) const _SatellitePanel(),
      ],
    );
  }

  @override
  void registerHttpRoutes(PluginRouter router) {
    router.get('satellite', _satelliteStatus);
  }

  /// Live satellite state for the portal: what the on-device panel reads
  /// straight from the bridge.
  Future<void> _satelliteStatus(PluginRequest req) async {
    if (!voiceSatelliteSupported) {
      await req.respondError(404, 'not found');
      return;
    }
    final bridge = req.readProvider(voiceSatelliteBridgeProvider);
    final status = bridge.status;
    await req.respondJson({
      'connection': status.connectionLabel,
      'health': status.health == null
          ? null
          : '${status.health!.label}: ${status.health!.message}',
      'wakeWords': [
        for (final w in bridge.wakeWords) {'id': w.id, 'name': w.name},
      ],
    });
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    // Web shows the raw "Mute microphone" checkbox (checked = muted) so the
    // bool maps directly to `micMuted` without needing inversion logic in
    // hearth.js. The HA mute side-effect only applies on-device.
    return const BoolSettingField(
          label: 'Mute microphone',
          configPath: 'micMuted',
          subtitle:
              'Disables wake word. Mute switch is driven on-device only.',
        ).buildHtml(ctx) +
        const BoolSettingField(
          label: 'Show voice feedback',
          configPath: 'showVoiceFeedback',
          subtitle: 'Voice pill overlay during interactions',
        ).buildHtml(ctx) +
        (voiceSatelliteSupported ? _satelliteHtml(ctx) : '');
  }

  String _satelliteHtml(WebContext ctx) {
    final config = ctx.config;
    final first = _escapeHtml(config.voiceWakeWords.first);
    final second = _escapeHtml(
        config.voiceWakeWords.length > 1 ? config.voiceWakeWords[1] : '');
    final mac = config.voiceSatelliteMac.isEmpty
        ? 'Generated when the satellite is first enabled'
        : _escapeHtml(config.voiceSatelliteMac);
    return [
      '<h3 style="margin:24px 0 12px;font-size:15px;font-weight:500;color:#fff">Voice satellite</h3>',
      const BoolSettingField(
        label: 'Voice satellite',
        configPath: 'voiceSatelliteEnabled',
        subtitle: _satelliteSubtitle,
      ).buildHtml(ctx),
      const TextSettingField(
        label: 'Satellite name',
        configPath: 'voiceSatelliteName',
        hint: _nameHint,
      ).buildHtml(ctx),
      // Two selects back one list field, so they save through the script
      // below instead of the auto-save helper.
      '''
<div class="field">
  <label>Wake word</label>
  <select id="voice-wake-1" data-config-path="voiceWakeWords" data-no-auto-save
          style="$_selectStyle">
    <option value="$first" selected>$first</option>
  </select>
</div>
<div class="field">
  <label>Second wake word</label>
  <select id="voice-wake-2" style="$_selectStyle">
    <option value="">None</option>
    ${second.isEmpty ? '' : '<option value="$second" selected>$second</option>'}
  </select>
</div>
''',
      const SelectSettingField(
        label: 'Wake word sensitivity',
        configPath: 'voiceWakeSensitivity',
        options: kVoiceWakeSensitivities,
      ).buildHtml(ctx),
      const BoolSettingField(
        label: 'Wake sound',
        configPath: 'voiceWakeSound',
        subtitle: 'Chime when the wake word is heard',
      ).buildHtml(ctx),
      const SelectSettingField(
        label: 'Audio source (advanced)',
        configPath: 'voiceAudioSource',
        options: kVoiceAudioSources,
      ).buildHtml(ctx),
      '''
<div class="field">
  <label>Satellite MAC</label>
  <div class="hint" style="font-size:13px;color:#e0e0e0">$mac</div>
</div>
<div class="field">
  <label>Home Assistant</label>
  <div class="hint" id="voice-connection" style="font-size:13px;color:#e0e0e0">Unknown</div>
</div>
<div class="field">
  <label>Last health event</label>
  <div class="hint" id="voice-health" style="font-size:13px;color:#e0e0e0">None</div>
</div>
<div class="field">
  <div class="hint" style="font-size:12px;color:#888">$_firstRunNote</div>
</div>
<script>
(function () {
  const first = document.getElementById('voice-wake-1');
  const second = document.getElementById('voice-wake-2');
  function saveWords() {
    const words = [first.value];
    if (second.value && second.value !== first.value) words.push(second.value);
    hearth.save('voiceWakeWords', words);
  }
  first.addEventListener('change', saveWords);
  second.addEventListener('change', saveWords);
  function fill(select, words, keep) {
    const current = select.value;
    while (select.options.length > keep) select.remove(keep);
    for (const w of words) select.add(new Option(w.name, w.id));
    select.value = current;
  }
  async function refresh() {
    let s;
    try { s = await hearth.action('satellite'); } catch (e) { return; }
    document.getElementById('voice-connection').textContent = s.connection;
    document.getElementById('voice-health').textContent = s.health || 'None';
    if (s.wakeWords.length && first.dataset.filled !== '1') {
      first.dataset.filled = '1';
      fill(first, s.wakeWords, 0);
      fill(second, s.wakeWords, 1);
    }
  }
  // hearth.js loads after the panel markup.
  document.addEventListener('DOMContentLoaded', () => {
    refresh();
    setInterval(refresh, 5000);
  });
})();
</script>
''',
    ].join();
  }
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _satelliteSubtitle = 'Wake word and Assist on this tablet';
const _nameHint = 'Defaults to the device hostname';
const _firstRunNote =
    'Home Assistant discovers the satellite as an ESPHome device. Add it '
    'under Settings, Devices & services.';
const _selectStyle =
    'width:100%;padding:10px 12px;background:#161618;border:1px solid #333;'
    'border-radius:6px;color:#e0e0e0;font-size:14px;outline:none';

/// The Android-only satellite group of the on-device panel.
class _SatellitePanel extends ConsumerWidget {
  const _SatellitePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final bridge = ref.watch(voiceSatelliteBridgeProvider);
    final status =
        ref.watch(voiceSatelliteStatusProvider).valueOrNull ?? bridge.status;
    final health = status.health;

    // Active words stay selectable even before the bundled list has loaded.
    final words = <String, String>{
      for (final w in bridge.wakeWords) w.id: w.name,
      for (final id in config.voiceWakeWords)
        if (!bridge.wakeWords.any((w) => w.id == id)) id: id,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 24, bottom: 4),
          child: Text('Voice satellite',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        const BoolSettingField(
          label: 'Voice satellite',
          icon: Icons.settings_voice,
          configPath: 'voiceSatelliteEnabled',
          subtitle: _satelliteSubtitle,
        ).buildWidget(ref),
        const TextSettingField(
          label: 'Satellite name',
          configPath: 'voiceSatelliteName',
          hint: _nameHint,
        ).buildWidget(ref),
        SelectSettingField(
          label: 'Wake word',
          options: words,
          readOverride: (c) => c.voiceWakeWords.first,
          writeOverride: (ref, id) => _setWakeWords(ref, first: id),
        ).buildWidget(ref),
        SelectSettingField(
          label: 'Second wake word',
          options: {'': 'None', ...words},
          readOverride: (c) =>
              c.voiceWakeWords.length > 1 ? c.voiceWakeWords[1] : '',
          writeOverride: (ref, id) => _setWakeWords(ref, second: id),
        ).buildWidget(ref),
        const SelectSettingField(
          label: 'Wake word sensitivity',
          configPath: 'voiceWakeSensitivity',
          options: kVoiceWakeSensitivities,
        ).buildWidget(ref),
        const BoolSettingField(
          label: 'Wake sound',
          icon: Icons.volume_up,
          configPath: 'voiceWakeSound',
          subtitle: 'Chime when the wake word is heard',
        ).buildWidget(ref),
        const SelectSettingField(
          label: 'Audio source (advanced)',
          configPath: 'voiceAudioSource',
          options: kVoiceAudioSources,
        ).buildWidget(ref),
        _ReadOnlyRow(
          label: 'Satellite MAC',
          value: config.voiceSatelliteMac.isEmpty
              ? 'Generated when the satellite is first enabled'
              : config.voiceSatelliteMac,
        ),
        _ReadOnlyRow(label: 'Home Assistant', value: status.connectionLabel),
        _ReadOnlyRow(
          label: 'Last health event',
          value:
              health == null ? 'None' : '${health.label}: ${health.message}',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(_firstRunNote,
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ],
    );
  }

  /// Rewrites the one- or two-entry list from whichever dropdown changed.
  static Future<void> _setWakeWords(WidgetRef ref,
      {String? first, String? second}) {
    return ref.read(hubConfigProvider.notifier).update((c) {
      final a = first ?? c.voiceWakeWords.first;
      final b =
          second ?? (c.voiceWakeWords.length > 1 ? c.voiceWakeWords[1] : '');
      return c.copyWith(voiceWakeWords: [a, if (b.isNotEmpty && b != a) b]);
    });
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
