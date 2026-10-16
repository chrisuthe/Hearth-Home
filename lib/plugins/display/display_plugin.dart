import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/display_orientation.dart';
import '../../config/hearth_theme_id.dart';
import '../../config/hub_config.dart';
import '../../screens/settings/display_settings.dart';
import '../../services/display_rotation_service.dart';
import '../../services/osk_integration.dart';
import '../../services/timezone_service.dart';
import '../../services/toast_service.dart';
import '../../widgets/timezone_picker_dialog.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/ha_entity_picker_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/fields/slider_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/plugin_router.dart';
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
///   * `displayOrientation` — plus a "Restart to apply" action on the Pi,
///     where flutter-pi only reads the rotation at launch
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
  void registerHttpRoutes(PluginRouter router) {
    router.get('rotation', _rotationStatus);
    router.post('restart', _rotationRestart);
  }

  Future<void> _rotationStatus(PluginRequest req) async {
    final service = req.readProvider(displayRotationServiceProvider);
    final configured =
        DisplayOrientation.fromWire(req.config.displayOrientation);
    await req.respondJson({
      'status': service.statusFor(configured).name,
      'configuredDegrees': configured.piRotationDegrees,
      'appliedDegrees': service.appliedDegrees,
    });
  }

  /// Gated on a pending rotation: the portal can bounce the kiosk only when
  /// doing so would actually change something.
  Future<void> _rotationRestart(PluginRequest req) async {
    final service = req.readProvider(displayRotationServiceProvider);
    final configured =
        DisplayOrientation.fromWire(req.config.displayOrientation);
    if (service.statusFor(configured) != RotationStatus.restartNeeded) {
      await req.respondError(409, 'no orientation change to apply');
      return;
    }
    // Answer first: a successful restart kills this process mid-response.
    await req.respondJson({'status': 'restarting'});
    await service.restart();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final clockHtml = const BoolSettingField(
      label: 'Use 24-Hour Clock',
      configPath: 'use24HourClock',
    ).buildHtml(ctx);

    // Web parity with the on-device TimezonePickerDialog: a searchable picker
    // over IANA zones. A `<datalist>`-backed text input filters as the user
    // types (the searchable part) while still accepting free-text entry (the
    // fallback). The zone list is inlined from TimezoneService — the web HTML
    // renders synchronously and can't run the async system enumeration.
    final timezoneHtml = _timezoneHtml(ctx);

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

    final themeHtml = SelectSettingField(
      configPath: 'theme',
      label: 'Theme',
      options: _themeOptions,
    ).buildHtml(ctx);

    final backgroundHtml = const SelectSettingField(
      configPath: 'screenBackground',
      label: 'Background',
      options: _backgroundOptions,
    ).buildHtml(ctx);

    const displayProfileNote =
        '<div class="field"><label>Display Profile</label>'
        '<div class="hint" style="font-size:12px;color:#888;">'
        'Configure display profile and connector from the on-device Settings.'
        '</div></div>';

    final orientationHtml = SelectSettingField(
          configPath: 'displayOrientation',
          label: 'Screen Orientation',
          options: _orientationOptions,
        ).buildHtml(ctx) +
        _rotationStatusHtml;

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
        themeHtml +
        backgroundHtml +
        displayProfileNote +
        orientationHtml +
        oskHtml +
        nightSourceHtml +
        nightEntityHtml +
        nightStartHtml +
        nightEndHtml +
        topSwipeHtml +
        bottomSwipeHtml;
  }

  /// Searchable timezone picker for the web portal — the parity counterpart of
  /// the on-device [TimezonePickerDialog]. Common zones lead (mirroring the
  /// dialog's "Common" group), then the rest of the curated IANA list, deduped.
  String _timezoneHtml(WebContext ctx) {
    final seen = <String>{};
    final zones = <String>[
      ...TimezoneService.commonTimezones,
      ...TimezoneService.fallbackTimezones,
    ].where(seen.add);
    final options =
        zones.map((z) => '<option value="${_escapeHtml(z)}"></option>').join();
    final current = _escapeHtml(ctx.config.timezone);
    return '''
<div class="field">
  <label>Timezone</label>
  <input type="text"
         class="hearth-field"
         data-config-path="timezone"
         list="timezone-zones"
         value="$current"
         placeholder="Search or type an IANA zone (blank = system default)">
  <datalist id="timezone-zones">
    $options
  </datalist>
</div>
''';
  }
}

final _themeOptions = {
  for (final t in HearthThemeId.values) t.wire: t.label,
};

const _backgroundOptions = {'solid': 'Solid', 'blurred': 'Blurred photo'};

final _orientationOptions = {
  for (final o in DisplayOrientation.values) o.wire: o.label,
};

const _launcherMissingNote =
    'Rotation on the Pi needs the Hearth launcher, which the next update '
    'installs. Until then the screen stays as it is.';

/// Status line under the orientation select. Server-rendered HTML cannot know
/// what flutter-pi was launched with, so it asks the `rotation` route — on
/// load and again after each change, once the debounced save has landed.
const _rotationStatusHtml = '''
<div class="field" id="rotation-status" style="display:none">
  <div class="hint" id="rotation-note" style="font-size:12px;color:#888;"></div>
  <button type="button" id="rotation-restart-btn" style="display:none;width:100%;margin-top:8px;padding:10px;background:#333;color:#e0e0e0;border:1px solid #444;border-radius:6px;cursor:pointer;font-size:13px">Restart to apply</button>
</div>
<script>
(function () {
  const box = document.getElementById('rotation-status');
  const note = document.getElementById('rotation-note');
  const btn = document.getElementById('rotation-restart-btn');
  async function refresh() {
    let s;
    try { s = await hearth.action('rotation'); } catch (e) { return; }
    btn.disabled = false;
    if (s.status === 'restartNeeded') {
      note.textContent = 'Hearth must restart to turn the screen.';
      btn.style.display = '';
      box.style.display = '';
    } else if (s.status === 'launcherMissing') {
      note.textContent = '$_launcherMissingNote';
      btn.style.display = 'none';
      box.style.display = '';
    } else {
      box.style.display = 'none';
    }
  }
  btn.addEventListener('click', async () => {
    btn.disabled = true;
    note.textContent = 'Restarting Hearth…';
    try { await hearth.action('restart', {}); } catch (e) {}
    // Either the kiosk is back at the new rotation or the restart never ran.
    setTimeout(refresh, 10000);
  });
  document.addEventListener('DOMContentLoaded', () => {
    const select = document.querySelector('select[data-config-path="displayOrientation"]');
    if (select) select.addEventListener('change', () => setTimeout(refresh, 800));
    refresh();
  });
})();
</script>
''';

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
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
        SelectSettingField(
          configPath: 'theme',
          label: 'Theme',
          options: _themeOptions,
        ).buildWidget(ref),
        const SelectSettingField(
          configPath: 'screenBackground',
          label: 'Background',
          options: _backgroundOptions,
        ).buildWidget(ref),
        const DisplaySettingsSection(),
        SelectSettingField(
          configPath: 'displayOrientation',
          label: 'Screen Orientation',
          options: _orientationOptions,
        ).buildWidget(ref),
        _RotationStatusTile(
          orientation: DisplayOrientation.fromWire(config.displayOrientation),
        ),
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

/// Shown under the orientation select on the Pi: either the restart that
/// applies a pending rotation, or why rotation cannot be applied yet.
class _RotationStatusTile extends ConsumerStatefulWidget {
  final DisplayOrientation orientation;
  const _RotationStatusTile({required this.orientation});

  @override
  ConsumerState<_RotationStatusTile> createState() =>
      _RotationStatusTileState();
}

class _RotationStatusTileState extends ConsumerState<_RotationStatusTile> {
  bool _restarting = false;

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    final ok = await ref.read(displayRotationServiceProvider).restart();
    if (!mounted) return;
    setState(() => _restarting = false);
    if (!ok) {
      ref.read(toastProvider.notifier).show(
            'Could not restart Hearth',
            icon: Icons.error_outline,
            type: ToastType.error,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final status = ref
        .watch(displayRotationServiceProvider)
        .statusFor(widget.orientation);
    final hintStyle =
        TextStyle(fontSize: 12, color: c.inkAt(0.5));
    switch (status) {
      case RotationStatus.inEffect:
        return const SizedBox.shrink();
      case RotationStatus.launcherMissing:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_launcherMissingNote, style: hintStyle),
        );
      case RotationStatus.restartNeeded:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Hearth must restart to turn the screen.',
                  style: hintStyle),
              FilledButton.tonal(
                onPressed: _restarting ? null : _restart,
                child: const Text('Restart to apply'),
              ),
            ],
          ),
        );
    }
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
    final c = context.hearthColors;
    final subtitle =
        currentTimezone.isEmpty ? 'System default' : currentTimezone;
    return ListTile(
      leading: Icon(Icons.public, color: c.textMuted),
      title: const Text('Timezone'),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: c.inkAt(0.5)),
      ),
      trailing: Icon(Icons.chevron_right, color: c.inkAt(0.24)),
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
        backgroundColor: context.hearthColors.raised,
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
    final c = context.hearthColors;
    return ListTile(
      leading: Icon(Icons.developer_board, color: c.textMuted),
      title: const Text('Night Mode Entity'),
      subtitle: Text(
        currentValue.isEmpty ? 'Not set' : currentValue,
        style: TextStyle(color: c.inkAt(0.5)),
      ),
      trailing: Icon(Icons.chevron_right, color: c.inkAt(0.24)),
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
        backgroundColor: context.hearthColors.raised,
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
    final c = context.hearthColors;
    return ListTile(
      leading: Icon(Icons.schedule, color: c.textMuted),
      title: Text(label),
      subtitle: Text(
        currentValue,
        style: TextStyle(color: c.inkAt(0.5)),
      ),
      trailing: Icon(Icons.chevron_right, color: c.inkAt(0.24)),
      onTap: () => _openDialog(context),
      contentPadding: EdgeInsets.zero,
    );
  }
}
