import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/toast_service.dart';
import '../../utils/alsa_utils.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Voice plugin — first device-category plugin.
///
/// Owns kiosk-side voice settings:
///   * `micMuted` — toggles the ALSA capture device on/off. Side effect:
///     calls [setMicMuted] so the hardware mic actually mutes, and shows a
///     toast notification matching legacy behaviour. The on-device toggle is
///     semantically inverted (UI shows "Microphone on/off", config stores
///     "muted"); the web checkbox is presented as a raw "Mute microphone"
///     option so the bool maps directly to the field and `hearth.js` needs no
///     special-case inversion handling.
///   * `showVoiceFeedback` — toggles the floating voice-pill overlay.
///
/// Status is always [PluginConfigStatus.configured] — these are toggles, not
/// configuration that can be "missing".
///
/// NOTE: The ALSA mute side effect only fires on-device. When the web client
/// updates `micMuted` via `/api/config`, the legacy server-side update path
/// applies the config change without touching ALSA (legacy didn't either).
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
            // Side effect: actually mute/unmute the ALSA mic.
            await setMicMuted(muted);
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
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    // Web shows the raw "Mute microphone" checkbox (checked = muted) so the
    // bool maps directly to `micMuted` without needing inversion logic in
    // hearth.js. The ALSA side-effect only applies on-device.
    return const BoolSettingField(
          label: 'Mute microphone',
          configPath: 'micMuted',
          subtitle:
              'Disables wake word. ALSA mute side-effect applies on-device only.',
        ).buildHtml(ctx) +
        const BoolSettingField(
          label: 'Show voice feedback',
          configPath: 'showVoiceFeedback',
          subtitle: 'Voice pill overlay during interactions',
        ).buildHtml(ctx);
  }
}
