import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import '../../app/app.dart' show kDialogBackground;

/// Settings screen -- configure connections, display, night mode, and music.
///
/// All changes persist immediately via [HubConfigNotifier.update], so there's
/// no "save" button. Each setting opens an appropriate dialog (text input,
/// slider, or choice picker) to keep the main screen scannable.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: ListView(
        padding: const EdgeInsets.all(24),
      children: [
        // --- Connections section ---
        _SectionHeader(title: 'Connections'),
        const SizedBox(height: 8),

        _SettingsTile(
          icon: Icons.photo_library,
          title: 'Immich URL',
          subtitle: config.immichUrl.isEmpty ? 'Not configured' : config.immichUrl,
          onTap: () => _showTextInputDialog(
            title: 'Immich URL',
            currentValue: config.immichUrl,
            hint: 'http://192.168.1.x:2283',
            onSave: (value) => _updateConfig((c) => c.copyWith(immichUrl: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.key,
          title: 'Immich API Key',
          subtitle: config.immichApiKey.isEmpty
              ? 'Not configured'
              : '\u2022' * 8, // Mask the key for security
          onTap: () => _showTextInputDialog(
            title: 'Immich API Key',
            currentValue: config.immichApiKey,
            hint: 'Paste your Immich API key',
            obscure: true,
            onSave: (value) => _updateConfig((c) => c.copyWith(immichApiKey: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.home,
          title: 'Home Assistant URL',
          subtitle: config.haUrl.isEmpty ? 'Not configured' : config.haUrl,
          onTap: () => _showTextInputDialog(
            title: 'Home Assistant URL',
            currentValue: config.haUrl,
            hint: 'http://192.168.1.x:8123',
            onSave: (value) => _updateConfig((c) => c.copyWith(haUrl: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.token,
          title: 'Home Assistant Token',
          subtitle: config.haToken.isEmpty
              ? 'Not configured'
              : '\u2022' * 8,
          onTap: () => _showTextInputDialog(
            title: 'HA Long-Lived Access Token',
            currentValue: config.haToken,
            hint: 'Paste your HA token',
            obscure: true,
            onSave: (value) => _updateConfig((c) => c.copyWith(haToken: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.videocam,
          title: 'Frigate URL',
          subtitle: config.frigateUrl.isEmpty ? 'Not configured' : config.frigateUrl,
          onTap: () => _showTextInputDialog(
            title: 'Frigate URL',
            currentValue: config.frigateUrl,
            hint: 'http://192.168.1.x:5000',
            onSave: (value) => _updateConfig((c) => c.copyWith(frigateUrl: value)),
          ),
        ),

        const SizedBox(height: 24),

        // --- Display section ---
        _SectionHeader(title: 'Display'),
        const SizedBox(height: 8),

        _SettingsTile(
          icon: Icons.timer,
          title: 'Idle Timeout',
          subtitle: '${config.idleTimeoutSeconds}s before ambient mode',
          onTap: () => _showSliderDialog(
            title: 'Idle Timeout (seconds)',
            currentValue: config.idleTimeoutSeconds.toDouble(),
            min: 30,
            max: 600,
            divisions: 57, // 30 to 600 in 10-second steps
            labelBuilder: (v) => '${v.round()}s',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(idleTimeoutSeconds: value.round()),
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.schedule, color: Colors.white54),
          title: const Text('24-Hour Clock'),
          subtitle: Text(
            config.use24HourClock ? '14:30' : '2:30 PM',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          ),
          value: config.use24HourClock,
          onChanged: (v) => _updateConfig((c) => c.copyWith(use24HourClock: v)),
        ),
        _SettingsTile(
          icon: Icons.devices,
          title: 'Pinned Devices',
          subtitle: config.pinnedEntityIds.isEmpty
              ? 'No devices selected'
              : '${config.pinnedEntityIds.length} devices',
          onTap: () => _showEntityPicker(context, ref),
        ),

        const SizedBox(height: 24),

        // --- Weather section ---
        _SectionHeader(title: 'Weather'),
        const SizedBox(height: 8),

        _SettingsTile(
          icon: Icons.thermostat,
          title: 'Weather Entity',
          subtitle: config.weatherEntityId.isEmpty
              ? 'Not configured'
              : config.weatherEntityId,
          onTap: () => _showTextInputDialog(
            title: 'Weather Entity ID',
            currentValue: config.weatherEntityId,
            hint: 'weather.pirateweather',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(weatherEntityId: value),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // --- Night Mode section ---
        _SectionHeader(title: 'Night Mode'),
        const SizedBox(height: 8),

        _SettingsTile(
          icon: Icons.nightlight_round,
          title: 'Night Mode Source',
          subtitle: _nightModeLabel(config.nightModeSource),
          onTap: () => _showChoiceDialog(
            title: 'Night Mode Source',
            options: const {
              'none': 'Disabled',
              'clock': 'Clock Schedule',
              'ha_entity': 'HA Entity',
              'api': 'External API',
            },
            currentValue: config.nightModeSource,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(nightModeSource: value),
            ),
          ),
        ),

        // Conditional fields based on night mode source selection
        if (config.nightModeSource == 'ha_entity')
          _SettingsTile(
            icon: Icons.developer_board,
            title: 'Night Mode Entity',
            subtitle: config.nightModeHaEntity ?? 'Not set',
            onTap: () => _showTextInputDialog(
              title: 'HA Entity ID for Night Mode',
              currentValue: config.nightModeHaEntity ?? '',
              hint: 'binary_sensor.night_mode',
              onSave: (value) => _updateConfig(
                (c) => c.copyWith(nightModeHaEntity: value),
              ),
            ),
          ),

        if (config.nightModeSource == 'clock') ...[
          _SettingsTile(
            icon: Icons.schedule,
            title: 'Start Time',
            subtitle: config.nightModeClockStart ?? '22:00',
            onTap: () => _showTextInputDialog(
              title: 'Night Mode Start (HH:MM)',
              currentValue: config.nightModeClockStart ?? '22:00',
              hint: '22:00',
              onSave: (value) => _updateConfig(
                (c) => c.copyWith(nightModeClockStart: value),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.schedule,
            title: 'End Time',
            subtitle: config.nightModeClockEnd ?? '07:00',
            onTap: () => _showTextInputDialog(
              title: 'Night Mode End (HH:MM)',
              currentValue: config.nightModeClockEnd ?? '07:00',
              hint: '07:00',
              onSave: (value) => _updateConfig(
                (c) => c.copyWith(nightModeClockEnd: value),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // --- Music section ---
        _SectionHeader(title: 'Music'),
        const SizedBox(height: 8),

        _SettingsTile(
          icon: Icons.music_note,
          title: 'Music Assistant URL',
          subtitle: config.musicAssistantUrl.isEmpty
              ? 'Not configured'
              : config.musicAssistantUrl,
          onTap: () => _showTextInputDialog(
            title: 'Music Assistant URL',
            currentValue: config.musicAssistantUrl,
            hint: 'http://192.168.1.x:8095',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(musicAssistantUrl: value),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.key,
          title: 'Music Assistant Token',
          subtitle: config.musicAssistantToken.isEmpty
              ? 'Not configured'
              : '\u2022' * 8,
          onTap: () => _showTextInputDialog(
            title: 'Music Assistant Token',
            currentValue: config.musicAssistantToken,
            hint: 'Paste your MA long-lived token',
            obscure: true,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(musicAssistantToken: value),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.speaker_group,
          title: 'Default Zone',
          subtitle: config.defaultMusicZone ?? 'Not set',
          onTap: () => _showTextInputDialog(
            title: 'Default Music Zone',
            currentValue: config.defaultMusicZone ?? '',
            hint: 'media_player.living_room',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(defaultMusicZone: value),
            ),
          ),
        ),
      ],
      ),
    );
  }

  String _nightModeLabel(String source) {
    switch (source) {
      case 'clock':
        return 'Clock Schedule';
      case 'ha_entity':
        return 'HA Entity';
      case 'api':
        return 'External API';
      default:
        return 'Disabled';
    }
  }

  /// Persists a config change immediately -- no save button needed.
  Future<void> _updateConfig(HubConfig Function(HubConfig) updater) async {
    await ref.read(hubConfigProvider.notifier).update(updater);
  }

  /// Generic text input dialog for URL, key, and entity ID fields.
  Future<void> _showTextInputDialog({
    required String title,
    required String currentValue,
    required String hint,
    bool obscure = false,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }

  /// Slider dialog for numeric settings like idle timeout.
  Future<void> _showSliderDialog({
    required String title,
    required double currentValue,
    required double min,
    required double max,
    int? divisions,
    required String Function(double) labelBuilder,
    required ValueChanged<double> onSave,
  }) async {
    double value = currentValue;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: kDialogBackground,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelBuilder(value),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
              ),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: (v) => setDialogState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onSave(result);
  }

  /// Choice dialog for selecting from a fixed set of options.
  Future<void> _showChoiceDialog({
    required String title,
    required Map<String, String> options,
    required String currentValue,
    required ValueChanged<String> onSave,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: kDialogBackground,
        title: Text(title),
        children: options.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.key),
            child: Row(
              children: [
                if (entry.key == currentValue)
                  const Icon(Icons.check, size: 18, color: Colors.amber)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 12),
                Text(entry.value),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _showEntityPicker(BuildContext context, WidgetRef ref) async {
    final ha = ref.read(homeAssistantServiceProvider);
    final config = ref.read(hubConfigProvider);
    final allEntities = ha.entities.values
        .where((e) => ['light', 'switch', 'climate', 'fan', 'cover', 'lock', 'input_boolean']
            .contains(e.domain))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (allEntities.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No entities available. Is HA connected?')),
      );
      return;
    }

    final selected = Set<String>.from(config.pinnedEntityIds);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EntityPickerDialog(
        entities: allEntities,
        selected: selected,
        onSave: (ids) => _updateConfig(
          (c) => c.copyWith(pinnedEntityIds: ids.toList()),
        ),
      ),
    );
  }
}

/// Section header used to visually group related settings.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.4),
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Individual settings row with icon, title, subtitle, and tap action.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white54, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _EntityPickerDialog extends StatefulWidget {
  final List<HaEntity> entities;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSave;

  const _EntityPickerDialog({
    required this.entities,
    required this.selected,
    required this.onSave,
  });

  @override
  State<_EntityPickerDialog> createState() => _EntityPickerDialogState();
}

class _EntityPickerDialogState extends State<_EntityPickerDialog> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.entities
        .where((e) =>
            e.name.toLowerCase().contains(_search.toLowerCase()) ||
            e.entityId.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: const Text('Select Devices'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search entities...',
                prefixIcon: Icon(Icons.search, color: Colors.white38),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final entity = filtered[i];
                  final isSelected = _selected.contains(entity.entityId);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(entity.name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(entity.entityId,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.3))),
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(entity.entityId);
                        } else {
                          _selected.remove(entity.entityId);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_selected);
            Navigator.pop(context);
          },
          child: Text('Save (${_selected.length})'),
        ),
      ],
    );
  }
}
