import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Mealie recipe-server integration.
///
/// Owns the `mealieUrl` + `mealieToken` HubConfig fields. The Recipes
/// screen lives in the existing `MealieModule` (lib/modules/mealie/) and
/// is contributed to HubShell's PageView via the legacy module registry.
/// Plugin-contributed pageScreens will be wired up in a separate pass;
/// for now this plugin only handles connection settings.
class MealiePlugin extends HearthPlugin {
  @override
  String get id => 'hearth.mealie';

  @override
  String get name => 'Mealie';

  @override
  IconData get icon => Icons.restaurant_menu;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 50;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.mealieUrl.isEmpty || config.mealieToken.isEmpty) {
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
          configPath: 'mealieUrl',
          label: 'Mealie URL',
          hint: 'http://192.168.1.x:9925',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'mealieToken',
          label: 'Mealie Token',
          hint: 'Paste your Mealie API token',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'mealieUrl',
      label: 'Mealie URL',
      hint: 'http://192.168.1.x:9925',
    ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'mealieToken',
          label: 'Mealie Token',
          hint: 'Paste your Mealie API token',
        ).buildHtml(ctx);
  }
}
