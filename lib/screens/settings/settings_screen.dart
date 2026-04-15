import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import '../../services/local_api_server.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../services/sendspin/alsa_audio_sink.dart';
import '../../services/sendspin/sendspin_service.dart';
import '../../services/timezone_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import 'wifi_settings.dart';
import 'display_settings.dart';
import 'update_settings.dart';
import '../../modules/module_registry.dart';
import '../../services/toast_service.dart';
import '../../services/voice_assistant_service.dart';

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
        // ── 1. Screens ──────────────────────────────────────────────
        const _SectionHeader(
          title: 'Screens',
          description: 'Manage screens and their order',
        ),
        const SizedBox(height: 8),
        ...allModules.map((module) {
          final placements = List<String>.from(
              config.modulePlacements[module.id] ?? []);
          return ListTile(
            leading: Icon(module.icon, color: Colors.white54),
            title: Text(module.name),
            subtitle: Wrap(
              spacing: 6,
              children: [
                for (final placement in ['swipe', 'menu1', 'menu2'])
                  FilterChip(
                    label: Text(
                      placement == 'swipe' ? 'Swipe' :
                      placement == 'menu1' ? 'Menu 1' : 'Menu 2',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: placements.contains(placement),
                    onSelected: (selected) {
                      final updated = Map<String, List<String>>.from(
                          config.modulePlacements);
                      final list = List<String>.from(updated[module.id] ?? []);
                      if (selected) {
                        list.add(placement);
                      } else {
                        list.remove(placement);
                      }
                      if (list.isEmpty) {
                        updated.remove(module.id);
                      } else {
                        updated[module.id] = list;
                      }
                      _updateConfig((c) => c.copyWith(modulePlacements: updated));
                    },
                    selectedColor: const Color(0xFF646CFF),
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: TextStyle(
                      color: placements.contains(placement)
                          ? Colors.white : Colors.white70,
                      fontSize: 11,
                    ),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          );
        }),
        const SizedBox(height: 12),
        _ModuleReorderList(
          config: config,
          onReorder: (newOrder) =>
              _updateConfig((c) => c.copyWith(moduleOrder: newOrder)),
          onReset: () =>
              _updateConfig((c) => c.copyWith(moduleOrder: const [])),
        ),

        const SizedBox(height: 24),

        // ── 2. Services ─────────────────────────────────────────────
        const _SectionHeader(
          title: 'Services',
          description: 'Connect to your smart home services',
        ),
        const SizedBox(height: 8),

        // -- Home Assistant --
        const _ServiceSubHeader(title: 'Home Assistant'),
        _SettingsTile(
          icon: Icons.home,
          title: 'URL',
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
          title: 'Token',
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

        // -- Immich --
        const _ServiceSubHeader(title: 'Immich'),
        _SettingsTile(
          icon: Icons.photo_library,
          title: 'URL',
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
          title: 'API Key',
          subtitle: config.immichApiKey.isEmpty
              ? 'Not configured'
              : '\u2022' * 8,
          onTap: () => _showTextInputDialog(
            title: 'Immich API Key',
            currentValue: config.immichApiKey,
            hint: 'Paste your Immich API key',
            obscure: true,
            onSave: (value) => _updateConfig((c) => c.copyWith(immichApiKey: value)),
          ),
        ),

        // -- Music Assistant --
        const _ServiceSubHeader(title: 'Music Assistant'),
        _SettingsTile(
          icon: Icons.music_note,
          title: 'URL',
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
          title: 'Token',
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

        // -- Frigate --
        const _ServiceSubHeader(title: 'Frigate'),
        _SettingsTile(
          icon: Icons.videocam,
          title: 'URL',
          subtitle: config.frigateUrl.isEmpty ? 'Not configured' : config.frigateUrl,
          onTap: () => _showTextInputDialog(
            title: 'Frigate URL',
            currentValue: config.frigateUrl,
            hint: 'http://192.168.1.x:5000',
            onSave: (value) => _updateConfig((c) => c.copyWith(frigateUrl: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.person,
          title: 'Username',
          subtitle: config.frigateUsername.isEmpty ? 'Not configured' : config.frigateUsername,
          onTap: () => _showTextInputDialog(
            title: 'Frigate Username',
            currentValue: config.frigateUsername,
            hint: 'admin',
            onSave: (value) => _updateConfig((c) => c.copyWith(frigateUsername: value)),
          ),
        ),
        _SettingsTile(
          icon: Icons.key,
          title: 'Password',
          subtitle: config.frigatePassword.isEmpty
              ? 'Not configured'
              : '\u2022' * 8,
          onTap: () => _showTextInputDialog(
            title: 'Frigate Password',
            currentValue: config.frigatePassword,
            hint: 'Enter password for Frigate auth',
            obscure: true,
            onSave: (value) => _updateConfig((c) => c.copyWith(frigatePassword: value)),
          ),
        ),

        // -- Mealie (only when enabled) --
        if (config.enabledModules.contains('mealie')) ...[
          const _ServiceSubHeader(title: 'Mealie'),
          _SettingsTile(
            icon: Icons.restaurant_menu,
            title: 'URL',
            subtitle: config.mealieUrl.isEmpty ? 'Not configured' : config.mealieUrl,
            onTap: () => _showTextInputDialog(
              title: 'Mealie URL',
              currentValue: config.mealieUrl,
              hint: 'http://192.168.1.x:9925',
              onSave: (value) => _updateConfig((c) => c.copyWith(mealieUrl: value)),
            ),
          ),
          _SettingsTile(
            icon: Icons.key,
            title: 'API Token',
            subtitle: config.mealieToken.isEmpty
                ? 'Not configured'
                : '\u2022' * 8,
            onTap: () => _showTextInputDialog(
              title: 'Mealie API Token',
              currentValue: config.mealieToken,
              hint: 'Paste your Mealie API token',
              obscure: true,
              onSave: (value) => _updateConfig((c) => c.copyWith(mealieToken: value)),
            ),
          ),
        ],

        // -- Weather --
        const _ServiceSubHeader(title: 'Weather'),
        _SettingsTile(
          icon: Icons.thermostat,
          title: 'Entity ID',
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

        // ── 3. Display & Behavior ────────────────────────────────────
        const _SectionHeader(
          title: 'Display & Behavior',
          description: 'Appearance and interaction settings',
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          secondary: const Icon(Icons.schedule, color: Colors.white54),
          title: const Text('24-Hour Clock'),
          subtitle: Text(
            config.use24HourClock ? '14:30' : '2:30 PM',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          value: config.use24HourClock,
          onChanged: (v) => _updateConfig((c) => c.copyWith(use24HourClock: v)),
        ),
        _SettingsTile(
          icon: Icons.public,
          title: 'Timezone',
          subtitle: config.timezone.isEmpty
              ? 'System default'
              : config.timezone,
          onTap: () => _showTimezonePicker(),
        ),
        _SettingsTile(
          icon: Icons.timer,
          title: 'Idle Timeout',
          subtitle: '${config.idleTimeoutSeconds}s before ambient mode',
          onTap: () => _showSliderDialog(
            title: 'Idle Timeout (seconds)',
            currentValue: config.idleTimeoutSeconds.toDouble(),
            min: 30,
            max: 600,
            divisions: 57,
            labelBuilder: (v) => '${v.round()}s',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(idleTimeoutSeconds: value.round()),
            ),
          ),
        ),
        const DisplaySettingsSection(),

        // -- Night Mode --
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
              onSave: (value) {
                if (RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
                  _updateConfig((c) => c.copyWith(nightModeClockStart: value));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid time. Use HH:MM with valid hours (0-23) and minutes (0-59)')),
                  );
                }
              },
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
              onSave: (value) {
                if (RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
                  _updateConfig((c) => c.copyWith(nightModeClockEnd: value));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid time. Use HH:MM with valid hours (0-23) and minutes (0-59)')),
                  );
                }
              },
            ),
          ),
        ],

        // -- Gestures --
        _SettingsTile(
          icon: Icons.swipe_down,
          title: 'Swipe Down (Top Edge)',
          subtitle: _swipeActionLabel(config.topSwipeAction),
          onTap: () => _showChoiceDialog(
            title: 'Top Edge Swipe Action',
            options: const {
              'menu1': 'Menu 1',
              'menu2': 'Menu 2',
              'settings': 'Settings',
              'nextScreen': 'Next Screen',
              'previousScreen': 'Previous Screen',
            },
            currentValue: config.topSwipeAction,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(topSwipeAction: value),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.swipe_up,
          title: 'Swipe Up (Bottom Edge)',
          subtitle: _swipeActionLabel(config.bottomSwipeAction),
          onTap: () => _showChoiceDialog(
            title: 'Bottom Edge Swipe Action',
            options: const {
              'menu1': 'Menu 1',
              'menu2': 'Menu 2',
              'settings': 'Settings',
              'nextScreen': 'Next Screen',
              'previousScreen': 'Previous Screen',
            },
            currentValue: config.bottomSwipeAction,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(bottomSwipeAction: value),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── 4. Devices ──────────────────────────────────────────────
        const _SectionHeader(
          title: 'Devices',
          description: 'Pinned devices for the Controls screen',
        ),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.devices,
          title: 'Pinned Devices',
          subtitle: config.pinnedEntityIds.isEmpty
              ? 'No devices selected'
              : '${config.pinnedEntityIds.length} devices',
          onTap: () => _showEntityPicker(context, ref),
        ),

        const SizedBox(height: 24),

        // ── 5. Audio ────────────────────────────────────────────────
        const _SectionHeader(
          title: 'Audio',
          description: 'Sendspin audio streaming',
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          secondary: const Icon(Icons.speaker, color: Colors.white54),
          title: const Text('Enable Sendspin Player'),
          subtitle: Text(
            config.sendspinEnabled ? 'Active' : 'Disabled',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          value: config.sendspinEnabled,
          onChanged: config.sendspinPlayerName.isEmpty
              ? null
              : (v) async {
                  if (v && config.sendspinClientId.isEmpty) {
                    await _updateConfig((c) => c.copyWith(
                      sendspinEnabled: true,
                      sendspinClientId: HubConfig.generateApiKey(),
                    ));
                  } else {
                    await _updateConfig((c) => c.copyWith(sendspinEnabled: v));
                  }
                },
        ),
        _SettingsTile(
          icon: Icons.label,
          title: 'Player Name',
          subtitle: config.sendspinPlayerName.isEmpty
              ? 'Required — name shown in Music Assistant'
              : config.sendspinPlayerName,
          onTap: () => _showTextInputDialog(
            title: 'Sendspin Player Name',
            currentValue: config.sendspinPlayerName,
            hint: 'Kitchen Display',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(sendspinPlayerName: value),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.dns,
          title: 'Server URL',
          subtitle: config.sendspinServerUrl.isEmpty
              ? 'Auto-discover via mDNS'
              : config.sendspinServerUrl,
          onTap: () => _showTextInputDialog(
            title: 'Sendspin Server URL',
            currentValue: config.sendspinServerUrl,
            hint: 'ws://192.168.1.x:8095 (blank for auto)',
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(sendspinServerUrl: value),
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final devices = AlsaAudioSink.listPlaybackDevices();
            final options = {
              for (final d in devices) d.device: d.label,
            };
            final current = config.sendspinAlsaDevice;
            final currentLabel = options[current] ?? current;
            return _SettingsTile(
              icon: Icons.speaker,
              title: 'ALSA Device',
              subtitle: currentLabel,
              onTap: () => _showChoiceDialog(
                title: 'ALSA Output Device',
                options: options,
                currentValue: current,
                onSave: (value) => _updateConfig(
                  (c) => c.copyWith(sendspinAlsaDevice: value),
                ),
              ),
            );
          },
        ),
        _SettingsTile(
          icon: Icons.memory,
          title: 'Buffer Size',
          subtitle: '${config.sendspinBufferSeconds}s audio buffer',
          onTap: () => _showChoiceDialog(
            title: 'Buffer Size',
            options: const {
              '5': '5 seconds',
              '7': '7 seconds',
              '10': '10 seconds',
            },
            currentValue: config.sendspinBufferSeconds.toString(),
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(sendspinBufferSeconds: int.parse(value)),
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final sendspinState = ref.watch(sendspinStateProvider);
            final statusText = sendspinState.when(
              data: (s) {
                switch (s.connectionState) {
                  case SendspinConnectionState.disabled:
                    return 'Disabled';
                  case SendspinConnectionState.advertising:
                    return 'Waiting for server...';
                  case SendspinConnectionState.connected:
                    return 'Connected';
                  case SendspinConnectionState.syncing:
                    return 'Synchronizing...';
                  case SendspinConnectionState.streaming:
                    final codec = s.codec?.toUpperCase() ?? '';
                    final rate = s.sampleRate != null ? '${s.sampleRate! ~/ 1000}kHz' : '';
                    return 'Streaming $codec $rate';
                  case SendspinConnectionState.disconnected:
                    return 'Disconnected — reconnecting...';
                }
              },
              loading: () => 'Loading...',
              error: (_, e) => 'Error',
            );
            return _SettingsTile(
              icon: Icons.info_outline,
              title: 'Status',
              subtitle: statusText,
              onTap: () {},
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Voice Assistant ─────────────────────────────────────────
        const _SectionHeader(
          title: 'Voice Assistant',
          description: 'Visual feedback for Wyoming voice satellite',
        ),
        const SizedBox(height: 8),
        const _VoiceMuteToggle(),
        SwitchListTile(
          secondary: const Icon(Icons.mic, color: Colors.white54),
          title: const Text('Show voice feedback'),
          subtitle: Text(
            config.showVoiceFeedback
                ? 'Voice pill overlay visible during interactions'
                : 'Voice pill overlay hidden',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          value: config.showVoiceFeedback,
          onChanged: (v) => _updateConfig((c) => c.copyWith(showVoiceFeedback: v)),
        ),

        const SizedBox(height: 24),

        // ── 6. Network & Access ─────────────────────────────────────
        const _SectionHeader(
          title: 'Network & Access',
          description: 'WiFi and web portal',
        ),
        const SizedBox(height: 8),
        const WifiSettingsSection(),
        _SettingsTile(
          icon: Icons.pin,
          title: 'Web Portal PIN',
          subtitle: ref.watch(webPinProvider),
          onTap: () {},
        ),

        const SizedBox(height: 24),

        // ── 7. System ───────────────────────────────────────────────
        const _SectionHeader(
          title: 'System',
          description: 'Updates and maintenance',
        ),
        const SizedBox(height: 8),
        const UpdateSettingsSection(),

        // Per-module settings (only shown when module is enabled).
        ...allModules
            .where((m) => config.enabledModules.contains(m.id))
            .map((m) => m.buildSettingsSection())
            .whereType<Widget>(),
      ],
      ),
    );
  }

  String _swipeActionLabel(String action) {
    switch (action) {
      case 'menu1':
        return 'Menu 1';
      case 'menu2':
        return 'Menu 2';
      case 'settings':
        return 'Settings';
      case 'nextScreen':
        return 'Next Screen';
      case 'previousScreen':
        return 'Previous Screen';
      default:
        return action;
    }
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

  Future<void> _showTimezonePicker() async {
    final tzService = ref.read(timezoneServiceProvider);
    final allZones = await tzService.listTimezones();

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _TimezonePickerDialog(
        timezones: allZones,
        currentTimezone: ref.read(hubConfigProvider).timezone,
      ),
    );
    if (result != null) {
      await _updateConfig((c) => c.copyWith(timezone: result));
      // Apply immediately on Linux.
      await tzService.applyTimezone(result);
    }
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
  final String? description;
  const _SectionHeader({required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 1.2,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// Sub-header for grouping settings within a section (e.g., per-service).
class _ServiceSubHeader extends StatelessWidget {
  final String title;
  const _ServiceSubHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 12, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.5),
        ),
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
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

/// Reorderable list for customizing screen order in the PageView.
class _ModuleReorderList extends StatefulWidget {
  final HubConfig config;
  final ValueChanged<List<String>> onReorder;
  final VoidCallback onReset;

  const _ModuleReorderList({
    required this.config,
    required this.onReorder,
    required this.onReset,
  });

  @override
  State<_ModuleReorderList> createState() => _ModuleReorderListState();
}

class _ModuleReorderListState extends State<_ModuleReorderList> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = _buildOrder();
  }

  @override
  void didUpdateWidget(_ModuleReorderList old) {
    super.didUpdateWidget(old);
    if (old.config.enabledModules != widget.config.enabledModules ||
        old.config.moduleOrder != widget.config.moduleOrder) {
      _order = _buildOrder();
    }
  }

  /// Build the display order list from config.
  /// If moduleOrder is set, use it (filtered to enabled modules).
  /// Otherwise, sort enabled modules by defaultOrder.
  List<String> _buildOrder() {
    final enabledIds = widget.config.enabledModules;
    final enabled = allModules.where((m) => enabledIds.contains(m.id)).toList();

    if (widget.config.moduleOrder.isNotEmpty) {
      // Start with modules in the custom order that are still enabled.
      final ordered = widget.config.moduleOrder
          .where((id) => enabledIds.contains(id))
          .toList();
      // Add any newly enabled modules not yet in the order.
      for (final m in enabled) {
        if (!ordered.contains(m.id)) ordered.add(m.id);
      }
      return ordered;
    }

    // Default order: sort by defaultOrder, left-of-home first.
    enabled.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
    return enabled.map((m) => m.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isEmpty) return const SizedBox.shrink();

    final hasCustomOrder = widget.config.moduleOrder.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            children: [
              Text(
                'Screen Order',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              if (hasCustomOrder)
                GestureDetector(
                  onTap: widget.onReset,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                    child: Text(
                      'Reset to Default',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            proxyDecorator: (child, index, animation) {
              return Material(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                elevation: 4,
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _order.removeAt(oldIndex);
                _order.insert(newIndex, item);
              });
              widget.onReorder(List<String>.from(_order));
            },
            itemBuilder: (context, index) {
              final moduleId = _order[index];
              final module = allModules.firstWhere((m) => m.id == moduleId);
              return ListTile(
                key: ValueKey(moduleId),
                dense: true,
                leading: Icon(module.icon, color: Colors.white38, size: 20),
                title: Text(
                  module.name,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle, color: Colors.white24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              );
            },
          ),
        ),
      ],
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
                            color: Colors.white.withValues(alpha: 0.5))),
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

/// Searchable timezone picker dialog.
///
/// Shows common timezones at the top, then all available timezones
/// filtered by the search query. Selecting "System default" clears
/// the timezone config (empty string).
class _TimezonePickerDialog extends StatefulWidget {
  final List<String> timezones;
  final String currentTimezone;

  const _TimezonePickerDialog({
    required this.timezones,
    required this.currentTimezone,
  });

  @override
  State<_TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<_TimezonePickerDialog> {
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build filtered list: common timezones first, then the rest.
    final lowerFilter = _filter.toLowerCase();
    final common = TimezoneService.commonTimezones
        .where((tz) => lowerFilter.isEmpty || tz.toLowerCase().contains(lowerFilter))
        .toList();
    final rest = widget.timezones
        .where((tz) => !TimezoneService.commonTimezones.contains(tz))
        .where((tz) => lowerFilter.isEmpty || tz.toLowerCase().contains(lowerFilter))
        .toList();

    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: const Text('Timezone'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search timezones...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              autofocus: true,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  // "System default" option to clear the setting.
                  if (lowerFilter.isEmpty || 'system default'.contains(lowerFilter))
                    _buildTile('', 'System default'),
                  if (common.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                      child: Text(
                        'Common',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  ...common.map((tz) => _buildTile(tz, tz)),
                  if (rest.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 12, bottom: 4),
                      child: Text(
                        'All timezones',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  ...rest.map((tz) => _buildTile(tz, tz)),
                ],
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
      ],
    );
  }

  Widget _buildTile(String value, String label) {
    final isSelected = value == widget.currentTimezone;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: isSelected
          ? const Icon(Icons.check, size: 18, color: Colors.amber)
          : const SizedBox(width: 18),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}

/// Toggle that stops/starts the Wyoming satellite service to mute/unmute
/// the voice assistant. Checks service state on build.
class _VoiceMuteToggle extends ConsumerStatefulWidget {
  const _VoiceMuteToggle();

  @override
  ConsumerState<_VoiceMuteToggle> createState() => _VoiceMuteToggleState();
}

class _VoiceMuteToggleState extends ConsumerState<_VoiceMuteToggle> {
  bool _running = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final voice = ref.read(voiceAssistantServiceProvider);
    final running = await voice.isSatelliteRunning;
    if (mounted) setState(() { _running = running; _loading = false; });
  }

  Future<void> _toggle(bool enable) async {
    setState(() => _loading = true);
    final voice = ref.read(voiceAssistantServiceProvider);
    final success = enable ? await voice.unmute() : await voice.mute();
    if (success && mounted) {
      setState(() { _running = enable; _loading = false; });
      ref.read(toastProvider.notifier).show(
        enable ? 'Voice assistant listening' : 'Voice assistant muted',
        icon: enable ? Icons.record_voice_over : Icons.voice_over_off,
      );
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(
        _running ? Icons.record_voice_over : Icons.voice_over_off,
        color: Colors.white54,
      ),
      title: const Text('Voice assistant'),
      subtitle: Text(
        _loading ? 'Checking...' : _running ? 'Listening for wake word' : 'Muted — not listening',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      value: _running,
      onChanged: _loading ? null : _toggle,
    );
  }
}
