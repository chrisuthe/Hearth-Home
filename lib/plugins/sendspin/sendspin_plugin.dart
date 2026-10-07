import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/hub_config.dart';
import '../../services/sendspin/sendspin_service.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Sendspin music streaming integration.
///
/// Owns:
///   * `sendspinEnabled`
///   * `sendspinPlayerName`
///   * `sendspinServerUrl`
///   * `sendspinBufferSeconds` (one of 5, 7, 10)
///   * `sendspinUnpairedAccess`
///
/// The device's identity is not a config field: it is a key pair the
/// Sendspin service creates on first use and keeps in its own file.
///
/// Live runtime status (streaming state, codec, sample rate) is observed
/// from `sendspinStateProvider` and shown elsewhere in the UI; this plugin
/// surfaces only the configuration fields. A future pass can wire it back in
/// via a `/api/plugin/<id>/status` route.
///
/// Web caveat: the pairing token is shown on the device only, like Plex
/// pairing. It carries the pairing key, so it stays off the network.
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
        const BoolSettingField(
          label: 'Allow unpaired servers',
          icon: Icons.lock_open,
          configPath: 'sendspinUnpairedAccess',
          subtitle: _unpairedAccessHelp,
        ).buildWidget(ref),
        const SizedBox(height: 12),
        const SendspinPairingSection(),
      ],
    );
  }

  static const _unpairedAccessHelp =
      'A server can play here once approved there, without pairing';

  @override
  String buildSettingsHtml(WebContext ctx) {
    final enable = BoolSettingField(
      label: 'Enable Sendspin Player',
      configPath: 'sendspinEnabled',
      disabledReason: (c) =>
          c.sendspinPlayerName.isEmpty ? 'Set player name first' : null,
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
    // Buffer size now works on the web: the auto-save helper posts the select
    // value as a string and `/api/config` coerces it to the int field. The
    // configPath drives the web auto-save; readOverride reads the int back as
    // the string the <select> expects.
    final bufferSize = SelectSettingField(
      configPath: 'sendspinBufferSeconds',
      label: 'Buffer Size',
      options: const {
        '5': '5 seconds',
        '7': '7 seconds',
        '10': '10 seconds',
      },
      readOverride: (c) => c.sendspinBufferSeconds.toString(),
    );
    const unpairedAccess = BoolSettingField(
      label: 'Allow unpaired servers',
      configPath: 'sendspinUnpairedAccess',
      subtitle: _unpairedAccessHelp,
    );
    return enable.buildHtml(ctx) +
        playerName.buildHtml(ctx) +
        serverUrl.buildHtml(ctx) +
        bufferSize.buildHtml(ctx) +
        unpairedAccess.buildHtml(ctx);
  }
}

/// The device's Sendspin pairing token, as a QR code and as text.
///
/// Pairing is started from the server: its operator scans or types this
/// token there, and the two then recognise each other on every later
/// connection. Shown only while the player is enabled, since the identity
/// behind the token is created when the service first starts.
class SendspinPairingSection extends ConsumerWidget {
  const SendspinPairingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hubConfigProvider.select((c) => c.sendspinEnabled))) {
      return const SizedBox.shrink();
    }
    final service = ref.watch(sendspinServiceProvider);
    return ValueListenableBuilder<SendspinPairingInfo?>(
      valueListenable: service.pairingInfo,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final paired = info.pairedServers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pair with a server',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              paired == 0
                  ? 'Not paired with any server'
                  : 'Paired with $paired server${paired == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: info.pairingToken,
                version: QrVersions.auto,
                size: 160,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan this in your Sendspin server, or enter the token:',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 4),
            SelectableText(
              info.pairingToken,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
