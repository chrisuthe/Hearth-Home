import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Frigate integration.
///
/// Owns the `frigateUrl`, `frigateUsername`, and `frigatePassword`
/// HubConfig fields. The Cameras module (lib/modules/cameras/) keeps
/// its existing PageView screen and the long-lived `FrigateService`;
/// this plugin only handles connection settings.
///
/// Some Frigate setups have no auth (open access). The status logic
/// reflects that: URL alone is enough for `configured`, but a partial
/// username/password pair is treated as `partial` (incomplete auth).
class FrigatePlugin extends HearthPlugin {
  @override
  String get id => 'hearth.frigate';

  @override
  String get name => 'Frigate';

  @override
  IconData get icon => Icons.videocam;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 40;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.frigateUrl.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    final hasUser = config.frigateUsername.isNotEmpty;
    final hasPass = config.frigatePassword.isNotEmpty;
    if (hasUser != hasPass) {
      // One half of the credentials filled in — incomplete auth.
      return PluginConfigStatus.partial;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'frigateUrl',
          label: 'Frigate URL',
          hint: 'http://192.168.1.x:5000',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'frigateUsername',
          label: 'Username',
          hint: 'admin',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'frigatePassword',
          label: 'Password',
          hint: 'Enter password for Frigate auth',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'frigateUrl',
      label: 'Frigate URL',
      hint: 'http://192.168.1.x:5000',
    ).buildHtml(ctx) +
        const TextSettingField(
          configPath: 'frigateUsername',
          label: 'Username',
          hint: 'admin',
        ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'frigatePassword',
          label: 'Password',
          hint: 'Enter password for Frigate auth',
        ).buildHtml(ctx);
  }
}
