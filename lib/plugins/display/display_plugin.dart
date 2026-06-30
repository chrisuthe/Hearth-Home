import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart' show kDialogBackground;
import '../../config/hub_config.dart';
import '../../screens/settings/display_settings.dart';
import '../../services/osk_integration.dart';
import '../../services/timezone_service.dart';
import '../../widgets/timezone_picker_dialog.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/slider_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Display & Behavior plugin — second device-category plugin.
///
/// Owns kiosk display, idle, gesture, and night-mode settings:
///   * `use24HourClock`, `timezone`
///   * `idleTimeoutSeconds`
///   * `uiScale` (via [UiScaleSection] bespoke widget)
///   * `displayProfile` (via [DisplaySettingsSection] bespoke widget — on
///     device only; web omits this entirely)
///   * `onScreenKeyboardMode`
///   * `nightModeSource` + conditional sub-fields (`nightModeHaEntity`,
///     `nightModeClockStart`, `nightModeClockEnd`)
///   * `topSwipeAction`, `bottomSwipeAction`
///
/// Surface differences:
///   * On-device: timezone uses [TimezonePickerDialog] (searchable list).
///     UI scale uses bespoke slider with reset button. Display profile uses
///     bespoke dialog. Night-mode sub-fields are cascading — only the
///     relevant ones render based on `nightModeSource`.
///   * Web portal: timezone degrades to text input. UI scale is a slider
///     bound directly to the `uiScale` double (the `/api/config` POST handler
///     coerces it to the right type). Display profile is omitted with a
///     hand-off hint. The night-mode HA entity is a searchable
///     [HaEntityPickerField] fed by the HA plugin's shared `entities` route.
///     Night-mode sub-fields all render at once (HTML can't reactively
///     show/hide without scripting we don't have for plugin panels yet).
///
/// Status: always [PluginConfigStatus.configured] — every field has a sane
/// default; there's nothing the user must fill in.
class DisplayPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.display';

  @override
  String get name => 'Display';

  @override
  IconData get icon => Icons.display_settings;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 20;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _DisplayPanel();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final clockHtml = const BoolSettingField(
      label: 'Use 24-Hour Clock',
      configPath: 'use24HourClock',
    ).buildHtml(ctx);

    // Web degradation: free-text IANA zone (the legacy panel used the same
    // approach with a datalist of common zones). A future enhancement could
    // expose a plugin route returning the full list.
    final timezoneHtml = const TextSettingField(
      configPath: 'timezone',
      label: 'Timezone',
      hint: 'America/New_York (blank = system default)',
    ).buildHtml(ctx);

    final idleHtml = SliderSettingField(
      configPath: 'idleTimeoutSeconds',
      label: 'Idle Timeout',
      min: 30,
      max: 600,
      divisions: 57,
      labelBuilder: (v) => '${v.round()}s',
    ).buildHtml(ctx);

    // UI scale is a plain double field now that `/api/config` coerces typed
    // values, so the shared slider drives it directly (htmlDisplayScale/suffix
    // make the live-drag readout show a percentage). Display profile stays a
    // hand-off note — it picks a flutter-pi connector the browser can't query.
    final uiScaleHtml = SliderSettingField(
      configPath: 'uiScale',
      label: 'UI Scale',
      min: 0.75,
      max: 1.5,
      divisions: 15,
      labelBuilder: (v) => '${(v * 100).round()}%',
      htmlDisplayScale: 100,
      htmlDisplaySuffix: '%',
    ).buildHtml(ctx);

    const displayProfileNote =
        '<div class="field"><label>Display Profile</label>'
        '<div class="hint" style="font-size:12px;color:#888;">'
        'Configure display profile and connector from the on-device Settings.'
        '</div></div>';

    final oskHtml = SelectSettingField(
      configPath: 'onScreenKeyboardMode',
      label: 'On-Screen Keyboard',
      options: {
        for (final m in OnScreenKeyboardMode.values) m.wire: m.label,
      },
    ).buildHtml(ctx);

    final nightSourceHtml = const SelectSettingField(
      configPath: 'nightModeSource',
      label: 'Night Mode Source',
      options: {
        'none': 'Disabled',
        'clock': 'Clock Schedule',
        'ha_entity': 'HA Entity',
        'api': 'External API',
      },
    ).buildHtml(ctx);

    // Conditional fields render unconditionally on web — HTML can't react
    // to the source dropdown without bespoke JS, so the user just ignores
    // the ones not relevant to their chosen mode.
    //
    // The HA entity is a searchable picker over the live entity list (any
    // domain, mirroring the on-device free-text dialog), served by the Home
    // Assistant plugin's shared `entities` route. It reaches that route by
    // absolute path because this Display panel's own plugin prefix can't see
    // it. Free-text fallback persists when HA is unreachable.
    final nightEntityHtml = const HaEntityPickerField(
      configPath: 'nightModeHaEntity',
      label: 'Night Mode HA Entity',
      hint: 'binary_sensor.night_mode (only used when source = HA Entity)',
    ).buildHtml(ctx);

    final nightStartHtml = const TextSettingField(
      configPath: 'nightModeClockStart',
      label: 'Night Mode Start (HH:MM)',
      hint: '22:00 (only used when source = Clock Schedule)',
    ).buildHtml(ctx);

    final nightEndHtml = const TextSettingField(
      configPath: 'nightModeClockEnd',
      label: 'Night Mode End (HH:MM)',
      hint: '07:00 (only used when source = Clock Schedule)',
    ).buildHtml(ctx);

    final topSwipeHtml = const SelectSettingField(
      configPath: 'topSwipeAction',
      label: 'Top Edge Swipe',
      options: {
        'menu1': 'Menu 1',
        'menu2': 'Menu 2',
        'settings': 'Settings',
        'nextScreen': 'Next Screen',
        'previousScreen': 'Previous Screen',
      },
    ).buildHtml(ctx);

    final bottomSwipeHtml = const SelectSettingField(
      configPath: 'bottomSwipeAction',
      label: 'Bottom Edge Swipe',
      options: {
        'menu1': 'Menu 1',
        'menu2': 'Menu 2',
        'settings': 'Settings',
        'nextScreen': 'Next Screen',
        'previousScreen': 'Previous Screen',
      },
    ).buildHtml(ctx);

    return clockHtml +
        timezoneHtml +
        idleHtml +
        uiScaleHtml +
        displayProfileNote +
        oskHtml +
        nightSourceHtml +
        nightEntityHtml +
        nightStartHtml +
        nightEndHtml +
        topSwipeHtml +
        bottomSwipeHtml;
  }
}

class _DisplayPanel extends ConsumerWidget {
  const _DisplayPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BoolSettingField(
          label: '24-Hour Clock',
          icon: Icons.schedule,
          configPath: 'use24HourClock',
        ).buildWidget(ref),
        _TimezoneTile(currentTimezone: config.timezone),
        SliderSettingField(
          label: 'Idle Timeout',
          min: 30,
          max: 600,
          divisions: 57,
          labelBuilder: (v) => '${v.round()}s',
          readOverride: (c) => c.idleTimeoutSeconds.toDouble(),
          writeOverride: (ref, v) async {
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update(
                (c) => c.copyWith(idleTimeoutSeconds: v.round()));
          },
        ).buildWidget(ref),
        const UiScaleSection(),
        const DisplaySettingsSection(),
        SelectSettingField(
          configPath: 'onScreenKeyboardMode',
          label: 'On-Screen Keyboard',
          options: {
            for (final m in OnScreenKeyboardMode.values) m.wire: m.label,
          },
        ).buildWidget(ref),
        const SelectSettingField(
          configPath: 'nightModeSource',
          label: 'Night Mode Source',
          options: {
            'none': 'Disabled',
            'clock': 'Clock Schedule',
            'ha_entity': 'HA Entity',
            'api': 'External API',
          },
        ).buildWidget(ref),
        if (config.nightModeSource == 'ha_entity')
          _NightModeEntityTile(
            currentValue: config.nightModeHaEntity ?? '',
          ),
        if (config.nightModeSource == 'clock') ...[
          _NightModeClockTile(
            label: 'Night Mode Start',
            currentValue: config.nightModeClockStart ?? '22:00',
            defaultValue: '22:00',
            onSave: (v) async {
              await ref.read(hubConfigProvider.notifier).update(
                    (c) => c.copyWith(nightModeClockStart: v),
                  );
            },
          ),
          _NightModeClockTile(
            label: 'Night Mode End',
            currentValue: config.nightModeClockEnd ?? '07:00',
            defaultValue: '07:00',
            onSave: (v) async {
              await ref.read(hubConfigProvider.notifier).update(
                    (c) => c.copyWith(nightModeClockEnd: v),
                  );
            },
          ),
        ],
        const SelectSettingField(
          configPath: 'topSwipeAction',
          label: 'Top Edge Swipe',
          icon: Icons.swipe_down,
          options: {
            'menu1': 'Menu 1',
            'menu2': 'Menu 2',
            'settings': 'Settings',
            'nextScreen': 'Next Screen',
            'previousScreen': 'Previous Screen',
          },
        ).buildWidget(ref),
        const SelectSettingField(
          configPath: 'bottomSwipeAction',
          label: 'Bottom Edge Swipe',
          icon: Icons.swipe_up,
          options: {
            'menu1': 'Menu 1',
            'menu2': 'Menu 2',
            'settings': 'Settings',
            'nextScreen': 'Next Screen',
            'previousScreen': 'Previous Screen',
          },
        ).buildWidget(ref),
      ],
    );
  }
}

/// Bespoke tile that opens [TimezonePickerDialog].
class _TimezoneTile extends ConsumerWidget {
  final String currentTimezone;
  const _TimezoneTile({required this.currentTimezone});

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final tzService = ref.read(timezoneServiceProvider);
    final allZones = await tzService.listTimezones();
    if (!context.mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TimezonePickerDialog(
        timezones: allZones,
        currentTimezone: currentTimezone,
      ),
    );
    if (result != null) {
      await ref
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(timezone: result));
      await tzService.applyTimezone(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle =
        currentTimezone.isEmpty ? 'System default' : currentTimezone;
    return ListTile(
      leading: const Icon(Icons.public, color: Colors.white54),
      title: const Text('Timezone'),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => _openPicker(context, ref),
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Bespoke tile for the HA night-mode entity ID. Free text dialog.
class _NightModeEntityTile extends ConsumerWidget {
  final String currentValue;
  const _NightModeEntityTile({required this.currentValue});

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: const Text('HA Entity ID for Night Mode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'binary_sensor.night_mode',
          ),
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
    if (result != null) {
      await ref
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(nightModeHaEntity: result));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.developer_board, color: Colors.white54),
      title: const Text('Night Mode Entity'),
      subtitle: Text(
        currentValue.isEmpty ? 'Not set' : currentValue,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => _openDialog(context, ref),
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Bespoke tile for an HH:MM clock value with regex validation.
class _NightModeClockTile extends StatelessWidget {
  final String label;
  final String currentValue;
  final String defaultValue;
  final Future<void> Function(String value) onSave;

  const _NightModeClockTile({
    required this.label,
    required this.currentValue,
    required this.defaultValue,
    required this.onSave,
  });

  Future<void> _openDialog(BuildContext context) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text('$label (HH:MM)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: defaultValue),
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
    if (result == null) return;
    if (RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(result)) {
      await onSave(result);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Invalid time. Use HH:MM with valid hours (0-23) and minutes (0-59)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.schedule, color: Colors.white54),
      title: Text(label),
      subtitle: Text(
        currentValue,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => _openDialog(context),
      contentPadding: EdgeInsets.zero,
    );
  }
}
