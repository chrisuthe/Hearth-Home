import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// UniFi Protect integration.
///
/// Owns the `unifiProtectUrl` and `unifiProtectApiKey` HubConfig fields. The
/// Protect module (lib/modules/protect/) owns the screen and the long-lived
/// `ProtectService`; this plugin only handles connection settings.
///
/// Both fields are required — Protect's local Integration API rejects every
/// request without an `X-API-Key`, so a URL alone is not enough to connect.
class ProtectPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.protect';

  @override
  String get name => 'UniFi Protect';

  @override
  IconData get icon => Icons.security;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 41;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.unifiProtectUrl.isEmpty ||
        config.unifiProtectApiKey.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'unifiProtectUrl',
          label: 'Protect URL',
          hint: 'https://192.168.1.1',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'unifiProtectApiKey',
          label: 'API key',
          hint: 'Settings → Control Plane → Integrations',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'unifiProtectUrl',
      label: 'Protect URL',
      hint: 'https://192.168.1.1',
    ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'unifiProtectApiKey',
          label: 'API key',
          hint: 'Settings → Control Plane → Integrations',
        ).buildHtml(ctx);
  }
}
