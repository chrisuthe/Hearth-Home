import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../modules/alarm_clock/alarm_editor_screen.dart';
import '../../modules/alarm_clock/alarm_models.dart';
import '../../modules/alarm_clock/alarm_service.dart';
import '../framework/list_section.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Alarm Clock plugin.
///
/// Alarms are managed by [AlarmService] (persisted to `alarms.json`), not
/// HubConfig — so the plugin's on-device panel watches the service and
/// hands off add/edit/delete to the existing [AlarmEditorScreen]. The web
/// panel renders a read-only list (sourced from HubConfig isn't possible
/// here; the web render uses an empty placeholder until a future plugin
/// HTTP route exposes the alarm list to the web portal).
///
/// Deferred for later sessions:
///   * `/api/plugin/hearth.alarm_clock/alarms` GET/POST/DELETE routes
///     (legacy `/api/alarms` continues to work)
///   * Web-side editing
///   * Owning the PageView screen via [pageScreen]
class AlarmClockPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.alarm_clock';

  @override
  String get name => 'Alarm Clock';

  @override
  IconData get icon => Icons.alarm;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 70;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    // Alarms live in AlarmService, not HubConfig — there's no config the
    // user must fill in. Always report configured; the panel itself
    // surfaces the empty-state message.
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _AlarmClockPanel();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    // Web render has no direct access to AlarmService, so we emit a
    // ListSection placeholder. Editing always happens on-device for now.
    final section = ListSection<Alarm>(
      label: 'Alarms',
      items: const [],
      summaryFor: _alarmSummary,
      onListChanged: (_) async {},
      editorBuilder: (_, existing) async => null,
    );
    const handoffNote =
        '<div class="hint" style="font-size:12px;color:#888;margin-top:-6px;margin-bottom:16px">'
        'Edit alarms from the on-device Alarm Clock screen.'
        '</div>';
    return '${section.buildHtml()}$handoffNote';
  }
}

class _AlarmClockPanel extends ConsumerWidget {
  const _AlarmClockPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(alarmServiceProvider);
    final alarms = service.alarms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alarms.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No alarms set. Tap "Open Alarm Editor" below to add one.',
              style: TextStyle(
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final alarm in alarms)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.alarm,
                color: alarm.enabled ? Colors.white : Colors.white38,
              ),
              title: Text(
                alarm.time,
                style: TextStyle(
                  color: alarm.enabled ? Colors.white : Colors.white54,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(
                alarm.label.isEmpty
                    ? alarm.daySummary
                    : '${alarm.label} • ${alarm.daySummary}',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Open Alarm Editor'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AlarmEditorScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF646cff),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

String _alarmSummary(Alarm alarm) {
  final base =
      alarm.label.isEmpty ? alarm.time : '${alarm.time} — ${alarm.label}';
  return '$base (${alarm.daySummary})';
}
