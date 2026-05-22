import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Music Assistant integration.
///
/// Owns the `musicAssistantUrl`, `musicAssistantToken`, and
/// `defaultMusicZone` HubConfig fields. The Cinematic music player lives
/// in the existing `MediaModule` (lib/modules/media/) and is contributed
/// to HubShell's PageView via the legacy module registry. Plugin-
/// contributed pageScreens will be wired up in a separate pass; for now
/// this plugin only handles connection settings.
class MusicAssistantPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.music_assistant';

  @override
  String get name => 'Music Assistant';

  @override
  IconData get icon => Icons.music_note;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 30;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.musicAssistantUrl.isEmpty || config.musicAssistantToken.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    final zone = config.defaultMusicZone;
    if (zone == null || zone.isEmpty) {
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
          configPath: 'musicAssistantUrl',
          label: 'Music Assistant URL',
          hint: 'http://192.168.1.x:8095',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'musicAssistantToken',
          label: 'Music Assistant Token',
          hint: 'Paste your MA long-lived token',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'defaultMusicZone',
          label: 'Default Music Zone',
          hint: 'media_player.living_room',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return const TextSettingField(
      configPath: 'musicAssistantUrl',
      label: 'Music Assistant URL',
      hint: 'http://192.168.1.x:8095',
    ).buildHtml(ctx) +
        const PasswordSettingField(
          configPath: 'musicAssistantToken',
          label: 'Music Assistant Token',
          hint: 'Paste your MA long-lived token',
        ).buildHtml(ctx) +
        const TextSettingField(
          configPath: 'defaultMusicZone',
          label: 'Default Music Zone',
          hint: 'media_player.living_room',
        ).buildHtml(ctx);
  }
}
