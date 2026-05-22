import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Immich photo-server integration.
///
/// Owns the `immichUrl` + `immichApiKey` HubConfig fields. The album /
/// photo-source picker (PhotoSourcesSection) is a bespoke widget that
/// remains in the legacy panel for now — it can migrate later as a richer
/// custom widget contribution.
class ImmichPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.immich';

  @override
  String get name => 'Immich';

  @override
  IconData get icon => Icons.photo_library;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 20;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.immichUrl.isEmpty || config.immichApiKey.isEmpty) {
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
          configPath: 'immichUrl',
          label: 'Immich URL',
          hint: 'http://192.168.1.x:2283',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'immichApiKey',
          label: 'API Key',
          hint: 'Paste your Immich API key',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'immichUrl',
      label: 'Immich URL',
      hint: 'http://192.168.1.x:2283',
    ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'immichApiKey',
          label: 'API Key',
          hint: 'Paste your Immich API key',
        ).buildHtml(ctx);
  }
}
