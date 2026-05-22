import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import '../../services/local_api_server.dart';
import '../../services/osk_integration.dart';
import '../../utils/alsa_utils.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../services/sendspin/sendspin_service.dart';
import '../../services/timezone_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import 'wifi_settings.dart';
import 'display_settings.dart';
import 'photo_sources_section.dart';
import 'update_settings.dart';
import '../../modules/hearth_module.dart';
import '../../modules/module_registry.dart';
import '../../modules/webview/webview_settings_section.dart';
import '../../services/toast_service.dart';
import '../../app/tokens/tokens.dart';
import '../../plugins/hearth_plugin.dart';
import '../../plugins/plugin_registry.dart';
import '../../plugins/framework/plugin_sidebar.dart';
import '../../plugins/framework/plugin_panel.dart';

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
  String _selectedId = 'hearth.weather';

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PluginSidebar(
            selectedId: _selectedId,
            onSelected: (id) => setState(() => _selectedId = id),
          ),
          Expanded(child: _buildSelectedPanel(config)),
        ],
      ),
    );
  }

  Widget _buildSelectedPanel(HubConfig config) {
    if (_selectedId == 'legacy') {
      return _buildLegacyPanel(config);
    }
    final plugins = ref.read(allPluginsProvider);
    HearthPlugin? plugin;
    for (final p in plugins) {
      if (p.id == _selectedId) {
        plugin = p;
        break;
      }
    }
    if (plugin == null && plugins.isNotEmpty) {
      plugin = plugins.first;
    }
    if (plugin == null) {
      return _buildLegacyPanel(config);
    }
    return PluginPanel(plugin: plugin);
  }

  Widget _buildLegacyPanel(HubConfig config) {
    final allModules = ref.watch(allModulesProvider);
    return ListView(
      padding: HearthSpacing.allX6,
      children: [
        // ── 1. Screens ──────────────────────────────────────────────
        const _SectionHeader(
          title: 'Screens',
          description: 'Manage screens and their order',
        ),
        const SizedBox(height: HearthSpacing.x2),
        ...allModules.where((m) => !m.isCommunity).map(
            (module) => _modulePlacementTile(module, config)),
        if (allModules.any((m) => m.isCommunity)) ...[
          const SizedBox(height: HearthSpacing.x4),
          const _ServiceSubHeader(title: 'Community Contributed'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
            child: Text(
              'Modules contributed by the community. Disabled by default — enable at your own discretion.',
              style: TextStyle(color: Colors.white54, fontSize: HearthFont.caption),
            ),
          ),
          const SizedBox(height: HearthSpacing.x1),
          ...allModules.where((m) => m.isCommunity).map(
              (module) => _modulePlacementTile(module, config)),
        ],
        const SizedBox(height: HearthSpacing.x3),
        _ModuleReorderList(
          config: config,
          modules: allModules,
          onReorder: (newOrder) =>
              _updateConfig((c) => c.copyWith(moduleOrder: newOrder)),
          onReset: () =>
              _updateConfig((c) => c.copyWith(moduleOrder: const [])),
        ),

        const SizedBox(height: HearthSpacing.x6),

        // ── 2. Services ─────────────────────────────────────────────
        const _SectionHeader(
          title: 'Services',
          description: 'Connect to your smart home services',
        ),
        const SizedBox(height: HearthSpacing.x2),

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
        const SizedBox(height: HearthSpacing.x4),
        const PhotoSourcesSection(),

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

        // -- Voice Assistant --
        // Pin to a specific assist_satellite entity. Empty = auto-pick the
        // first available one (fine for single-Hearth setups, breaks the
        // moment another satellite — second Hearth, Voice PE, etc — joins HA).
        const _ServiceSubHeader(title: 'Voice Assistant'),
        Builder(builder: (context) {
          final ha = ref.read(homeAssistantServiceProvider);
          final assistEntities = ha.entities.values
              .where((e) => e.entityId.startsWith('assist_satellite.'))
              .toList()
            ..sort((a, b) => a.entityId.compareTo(b.entityId));
          final options = <String, String>{
            '': "Auto-detect (match this Pi's MAC)",
            for (final e in assistEntities)
              e.entityId:
                  '${e.name.isNotEmpty ? e.name : e.entityId} (${e.entityId})',
          };
          final current = config.voiceAssistantEntityId;
          final currentLabel = options[current] ??
              (current.isEmpty ? "Auto-detect (match this Pi's MAC)" : current);
          return _SettingsTile(
            icon: Icons.record_voice_over,
            title: 'Satellite Entity',
            subtitle: currentLabel,
            onTap: () => _showChoiceDialog(
              title: 'Voice Assistant Satellite',
              options: options,
              currentValue: current,
              onSave: (value) => _updateConfig(
                (c) => c.copyWith(voiceAssistantEntityId: value),
              ),
            ),
          );
        }),

        const SizedBox(height: HearthSpacing.x6),

        // ── 3. Display & Behavior ────────────────────────────────────
        const _SectionHeader(
          title: 'Display & Behavior',
          description: 'Appearance and interaction settings',
        ),
        const SizedBox(height: HearthSpacing.x2),

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
        const UiScaleSection(),
        const DisplaySettingsSection(),
        _SettingsTile(
          icon: Icons.keyboard,
          title: 'On-Screen Keyboard',
          subtitle: OnScreenKeyboardMode.fromWire(
                  config.onScreenKeyboardMode)
              .label,
          onTap: () => _showChoiceDialog(
            title: 'On-Screen Keyboard',
            options: {
              for (final mode in OnScreenKeyboardMode.values) mode.wire: mode.label,
            },
            currentValue: config.onScreenKeyboardMode,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(onScreenKeyboardMode: value),
            ),
          ),
        ),

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

        const SizedBox(height: HearthSpacing.x6),

        // ── 4. Devices ──────────────────────────────────────────────
        const _SectionHeader(
          title: 'Devices',
          description: 'Pinned devices for the Controls screen',
        ),
        const SizedBox(height: HearthSpacing.x2),
        _SettingsTile(
          icon: Icons.devices,
          title: 'Pinned Devices',
          subtitle: config.pinnedEntityIds.isEmpty
              ? 'No devices selected'
              : '${config.pinnedEntityIds.length} devices',
          onTap: () => _showEntityPicker(context, ref),
        ),

        const SizedBox(height: HearthSpacing.x6),

        // ── 5. Audio ────────────────────────────────────────────────
        const _SectionHeader(
          title: 'Audio',
          description: 'Sendspin audio streaming',
        ),
        const SizedBox(height: HearthSpacing.x2),

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

        const SizedBox(height: HearthSpacing.x6),

        // ── Voice Assistant ─────────────────────────────────────────
        const _SectionHeader(
          title: 'Voice Assistant',
          description: 'Visual feedback for Wyoming voice satellite',
        ),
        const SizedBox(height: HearthSpacing.x2),
        SwitchListTile(
          secondary: Icon(
            config.micMuted ? Icons.mic_off : Icons.mic,
            color: config.micMuted ? Colors.red : Colors.white54,
          ),
          title: const Text('Microphone'),
          subtitle: Text(
            config.micMuted ? 'Muted — wake word disabled' : 'Listening for wake word',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          value: !config.micMuted,
          onChanged: (listening) {
            final muted = !listening;
            _updateConfig((c) => c.copyWith(micMuted: muted));
            setMicMuted(muted);
            ref.read(toastProvider.notifier).show(
              muted ? 'Microphone muted' : 'Microphone unmuted',
              icon: muted ? Icons.mic_off : Icons.mic,
            );
          },
        ),
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

        const SizedBox(height: HearthSpacing.x6),

        // ── 6. Network & Access ─────────────────────────────────────
        const _SectionHeader(
          title: 'Network & Access',
          description: 'WiFi and web portal',
        ),
        const SizedBox(height: HearthSpacing.x2),
        const WifiSettingsSection(),
        _SettingsTile(
          icon: Icons.pin,
          title: 'Web Portal PIN',
          subtitle: ref.watch(webPinProvider),
          onTap: () {},
        ),

        const SizedBox(height: HearthSpacing.x6),

        // ── 7. System ───────────────────────────────────────────────
        const _SectionHeader(
          title: 'System',
          description: 'Updates and maintenance',
        ),
        const SizedBox(height: HearthSpacing.x2),
        const UpdateSettingsSection(),

        const SizedBox(height: HearthSpacing.x6),

        // ── 8. Webviews ────────────────────────────────────────────
        const _SectionHeader(
          title: 'Webviews',
          description: 'Embed Home Assistant dashboards and external pages as full-screen views',
        ),
        const SizedBox(height: HearthSpacing.x2),
        const WebviewSettingsSection(),

        const SizedBox(height: HearthSpacing.x6),

        // Per-module settings (only shown when module is enabled).
        ...allModules
            .where((m) => config.enabledModules.contains(m.id))
            .map((m) => m.buildSettingsSection())
            .whereType<Widget>(),
      ],
    );
  }

  Widget _modulePlacementTile(HearthModule module, HubConfig config) {
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
                style: const TextStyle(fontSize: HearthFont.caption),
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
                fontSize: HearthFont.caption,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
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
                style: const TextStyle(fontSize: HearthFont.headline, fontWeight: FontWeight.w300),
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
                  const Icon(Icons.check, size: HearthIcon.xs, color: Colors.amber)
                else
                  const SizedBox(width: HearthIcon.xs),
                const SizedBox(width: HearthSpacing.x3),
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
            fontSize: HearthFont.label,
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
              fontSize: HearthFont.caption,
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
      padding: const EdgeInsets.only(left: HearthSpacing.x2, top: HearthSpacing.x3, bottom: HearthSpacing.x1),
      child: Text(
        title,
        style: TextStyle(
          fontSize: HearthFont.caption,
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
      leading: Icon(icon, color: Colors.white54, size: HearthIcon.md),
      title: Text(title, style: const TextStyle(fontSize: HearthFont.body)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: HearthFont.label,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }
}

/// Reorderable list for customizing screen order in the PageView.
class _ModuleReorderList extends StatefulWidget {
  final HubConfig config;
  final List<HearthModule> modules;
  final ValueChanged<List<String>> onReorder;
  final VoidCallback onReset;

  const _ModuleReorderList({
    required this.config,
    required this.modules,
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
        old.config.moduleOrder != widget.config.moduleOrder ||
        old.modules != widget.modules) {
      _order = _buildOrder();
    }
  }

  /// Build the display order list from config.
  /// If moduleOrder is set, use it (filtered to enabled modules).
  /// Otherwise, sort enabled modules by defaultOrder.
  List<String> _buildOrder() {
    final enabledIds = widget.config.enabledModules;
    final enabled = widget.modules.where((m) => enabledIds.contains(m.id)).toList();

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
          padding: const EdgeInsets.only(left: HearthSpacing.x2, bottom: HearthSpacing.x1),
          child: Row(
            children: [
              Text(
                'Screen Order',
                style: TextStyle(
                  fontSize: HearthFont.caption,
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
                        horizontal: HearthSpacing.x2, vertical: HearthSpacing.x3),
                    child: Text(
                      'Reset to Default',
                      style: TextStyle(
                        fontSize: HearthFont.caption,
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
              final module = widget.modules.firstWhere((m) => m.id == moduleId);
              return ListTile(
                key: ValueKey(moduleId),
                dense: true,
                leading: Icon(module.icon, color: Colors.white38, size: HearthIcon.sm),
                title: Text(
                  module.name,
                  style: const TextStyle(fontSize: HearthFont.body),
                ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle, color: Colors.white24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3),
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
            const SizedBox(height: HearthSpacing.x2),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final entity = filtered[i];
                  final isSelected = _selected.contains(entity.entityId);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(entity.name, style: const TextStyle(fontSize: HearthFont.body)),
                    subtitle: Text(entity.entityId,
                        style: TextStyle(
                            fontSize: HearthFont.caption,
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
                prefixIcon: Icon(Icons.search, size: HearthIcon.sm),
                isDense: true,
              ),
              autofocus: true,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: HearthSpacing.x2),
            Expanded(
              child: ListView(
                children: [
                  // "System default" option to clear the setting.
                  if (lowerFilter.isEmpty || 'system default'.contains(lowerFilter))
                    _buildTile('', 'System default'),
                  if (common.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: HearthSpacing.x1, top: HearthSpacing.x2, bottom: HearthSpacing.x1),
                      child: Text(
                        'Common',
                        style: TextStyle(
                          fontSize: HearthFont.caption,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  ...common.map((tz) => _buildTile(tz, tz)),
                  if (rest.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: HearthSpacing.x1, top: HearthSpacing.x3, bottom: HearthSpacing.x1),
                      child: Text(
                        'All timezones',
                        style: TextStyle(
                          fontSize: HearthFont.caption,
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
          ? const Icon(Icons.check, size: HearthIcon.xs, color: Colors.amber)
          : const SizedBox(width: HearthIcon.xs),
      title: Text(label, style: const TextStyle(fontSize: HearthFont.body)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}

