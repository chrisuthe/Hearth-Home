import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// First migrated plugin — the canary that proves the framework end-to-end.
///
/// Surfaces a single field (`weatherEntityId`) mapping to the existing
/// HubConfig field of the same name. No PageView screen, no HTTP routes,
/// no dependencies — the smallest possible plugin.
class WeatherPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.weather';

  @override
  String get name => 'Weather';

  @override
  IconData get icon => Icons.cloud_outlined;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 60; // after HA, Immich, MA, Frigate, Mealie in declared order

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return config.weatherEntityId.isEmpty
        ? PluginConfigStatus.needsSetup
        : PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'weatherEntityId',
          label: 'Weather Entity ID',
          hint: 'weather.pirate',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'weatherEntityId',
      label: 'Weather Entity ID',
      hint: 'weather.pirate',
    ).buildHtml(ctx);
  }
}
