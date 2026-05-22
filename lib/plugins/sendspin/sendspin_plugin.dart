import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Sendspin music streaming integration.
///
/// Owns:
///   * `sendspinEnabled`  (with side-effect: generate clientId on first enable)
///   * `sendspinPlayerName`
///   * `sendspinServerUrl`
///   * `sendspinBufferSeconds` (one of 5, 7, 10)
///
/// `sendspinClientId` is internal — not surfaced as a field; written by the
/// enable toggle's [BoolSettingField.writeOverride] when the user first
/// flips the toggle on with an empty clientId.
///
/// Live runtime status (streaming state, codec, sample rate) is observed
/// from `sendspinStateProvider` and shown elsewhere in the UI; this plugin
/// surfaces only the configuration fields. A future pass can wire it back in
/// via a `/api/plugin/<id>/status` route.
///
/// Web caveats (deferred until a plugin HTTP route handles them):
///   * The enable checkbox in the web portal posts `sendspinEnabled` directly
///     to `/api/config` and does NOT generate `sendspinClientId`. Users must
///     toggle once on-device to seed the clientId. Legacy behavior matched
///     this — the web form never generated a clientId either.
///   * Buffer size is intentionally omitted from the web panel because the
///     auto-save helper writes string values, which would corrupt the int
///     field on save. Edit buffer size on-device.
class SendspinPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.sendspin';

  @override
  String get name => 'Sendspin';

  @override
  IconData get icon => Icons.speaker;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 80;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.sendspinPlayerName.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    // Enable is opt-in; the streaming state is runtime, not config, so a
    // disabled-but-named player is still "configured".
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoolSettingField(
          label: 'Enable Sendspin Player',
          icon: Icons.speaker,
          configPath: 'sendspinEnabled',
          disabledReason: (c) =>
              c.sendspinPlayerName.isEmpty ? 'Set player name first' : null,
          writeOverride: (ref, value) async {
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update((c) {
              if (value && c.sendspinClientId.isEmpty) {
                return c.copyWith(
                  sendspinEnabled: true,
                  sendspinClientId: HubConfig.generateApiKey(),
                );
              }
              return c.copyWith(sendspinEnabled: value);
            });
          },
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'sendspinPlayerName',
          label: 'Player Name',
          hint: 'Kitchen Display',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'sendspinServerUrl',
          label: 'Server URL',
          hint: 'ws://192.168.1.x:8095 (blank for mDNS auto-discover)',
        ).buildWidget(ref),
        SelectSettingField(
          label: 'Buffer Size',
          options: const {
            '5': '5 seconds',
            '7': '7 seconds',
            '10': '10 seconds',
          },
          readOverride: (c) => c.sendspinBufferSeconds.toString(),
          writeOverride: (ref, value) async {
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update(
              (c) => c.copyWith(sendspinBufferSeconds: int.parse(value)),
            );
          },
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    // Buffer size is omitted from the web until a plugin HTTP route handles
    // the string -> int conversion (the configPath auto-save would otherwise
    // write a string into the int field). On-device buffer size editing
    // works correctly via the SelectSettingField writeOverride above.
    final enable = BoolSettingField(
      label: 'Enable Sendspin Player',
      configPath: 'sendspinEnabled',
      disabledReason: (c) =>
          c.sendspinPlayerName.isEmpty ? 'Set player name first' : null,
      // No writeOverride on the web side: the legacy web form never generated
      // a clientId either, and the auto-save helper writes the bool directly.
      // Users must toggle once on-device to seed the clientId.
    );
    const playerName = TextSettingField(
      configPath: 'sendspinPlayerName',
      label: 'Player Name',
      hint: 'Kitchen Display',
    );
    const serverUrl = TextSettingField(
      configPath: 'sendspinServerUrl',
      label: 'Server URL',
      hint: 'ws://192.168.1.x:8095 (blank for mDNS auto-discover)',
    );
    return enable.buildHtml(ctx) +
        playerName.buildHtml(ctx) +
        serverUrl.buildHtml(ctx);
  }
}
