import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';
import '../../widgets/entity_picker_dialog.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/list_section.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Home Assistant integration plugin.
///
/// Owns the `haUrl`, `haToken`, `voiceAssistantEntityId`, and
/// `pinnedEntityIds` HubConfig fields. The Controls module
/// (`lib/modules/controls/`) keeps its existing PageView screen and the
/// long-lived [HomeAssistantService]; this plugin only handles the
/// connection settings, the voice satellite picker, and the pinned-entity
/// list management.
///
/// Surface differences:
///   * On-device: voice satellite is a [SelectSettingField] whose options
///     are populated dynamically from the live HA entity list (any
///     `assist_satellite.*`). Pinned devices opens [EntityPickerDialog].
///   * Web portal: voice satellite degrades to a plain text input (paste
///     the entity ID). Pinned devices renders as a read-only [ListSection]
///     with a hand-off note to the on-device Settings.
///
/// Out of scope (stays in the legacy panel for now):
///   * Mic mute toggle (`micMuted`) — lives in the Voice plugin (drives the
///     satellite's HA Mute switch under the hood).
///   * Show voice feedback (`showVoiceFeedback`) — kiosk UI, not HA.
///   * The Controls module's PageView screen.
class HomeAssistantPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.ha';

  @override
  String get name => 'Home Assistant';

  @override
  IconData get icon => Icons.home;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 10;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.haUrl.isEmpty || config.haToken.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    if (config.pinnedEntityIds.isEmpty) {
      // Connection works but the Controls screen would be empty.
      return PluginConfigStatus.partial;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _HomeAssistantPanel();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final urlHtml = const TextSettingField(
      configPath: 'haUrl',
      label: 'Home Assistant URL',
      hint: 'http://192.168.1.x:8123',
    ).buildHtml(ctx);

    final tokenHtml = const PasswordSettingField(
      configPath: 'haToken',
      label: 'Long-Lived Access Token',
      hint: 'Paste your HA token',
    ).buildHtml(ctx);

    // Web degradation: the browser has no live HA entity list, so we
    // render a plain text input where the user pastes the entity ID
    // (or leaves blank for MAC auto-detect). A future enhancement can
    // wire a `voice-satellites` plugin HTTP route + dynamic <select>
    // once the framework gives plugins access to live services.
    final satelliteHtml = const TextSettingField(
      configPath: 'voiceAssistantEntityId',
      label: 'Voice Assistant Satellite Entity',
      hint: 'assist_satellite.hearth_kiosk (blank = auto-detect by MAC)',
    ).buildHtml(ctx);

    // Pinned devices: read-only on web. Editing happens on-device via
    // EntityPickerDialog (no HA state in the browser).
    final pinnedSection = ListSection<String>(
      label: 'Pinned Devices',
      items: ctx.config.pinnedEntityIds,
      summaryFor: (id) => id,
      onListChanged: (_) async {},
      editorBuilder: (_, existing) async => null,
    );

    return urlHtml + tokenHtml + satelliteHtml + pinnedSection.buildHtml();
  }
}

class _HomeAssistantPanel extends ConsumerWidget {
  const _HomeAssistantPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final ha = ref.watch(homeAssistantServiceProvider);

    // Dynamic voice satellite options from the live HA entity list.
    final assistEntities = ha.entities.values
        .where((e) => e.entityId.startsWith('assist_satellite.'))
        .toList()
      ..sort((a, b) => a.entityId.compareTo(b.entityId));
    final voiceOptions = <String, String>{
      '': "Auto-detect (match this Pi's MAC)",
      for (final e in assistEntities)
        e.entityId:
            '${e.name.isNotEmpty ? e.name : e.entityId} (${e.entityId})',
    };
    // If the saved value isn't in the live list (HA still loading, or
    // entity went away), include it so the dropdown doesn't crash on a
    // missing key.
    final current = config.voiceAssistantEntityId;
    if (current.isNotEmpty && !voiceOptions.containsKey(current)) {
      voiceOptions[current] = current;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TextSettingField(
          configPath: 'haUrl',
          label: 'Home Assistant URL',
          hint: 'http://192.168.1.x:8123',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'haToken',
          label: 'Long-Lived Access Token',
          hint: 'Paste your HA token',
        ).buildWidget(ref),
        SelectSettingField(
          configPath: 'voiceAssistantEntityId',
          label: 'Voice Assistant Satellite',
          options: voiceOptions,
        ).buildWidget(ref),
        const SizedBox(height: 16),
        _PinnedEntitiesRow(pinnedCount: config.pinnedEntityIds.length),
      ],
    );
  }
}

/// Pinned-entity row: shows the current count and an "Edit" button that
/// opens the shared [EntityPickerDialog]. The dialog itself writes the
/// new list back to HubConfig.
class _PinnedEntitiesRow extends ConsumerWidget {
  final int pinnedCount;
  const _PinnedEntitiesRow({required this.pinnedCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = pinnedCount == 0
        ? 'No devices selected'
        : '$pinnedCount device${pinnedCount == 1 ? "" : "s"}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pinned Devices',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices, color: Colors.white54),
            title: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              onPressed: () => showDialog<List<String>>(
                context: context,
                builder: (_) => const EntityPickerDialog(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF646cff),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
