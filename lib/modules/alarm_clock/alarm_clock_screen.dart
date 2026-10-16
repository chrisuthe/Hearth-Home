import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/tokens/tokens.dart';
import 'alarm_editor_screen.dart';
import 'alarm_models.dart';
import 'alarm_service.dart';
import '../../widgets/themed_background.dart';

/// Alarm list screen showing all configured alarms.
///
/// Displays a header with time-until-next-alarm, a scrollable list of
/// alarm cards, and a FAB to create new alarms.
class AlarmClockScreen extends ConsumerWidget {
  const AlarmClockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(alarmServiceProvider);
    final alarms = service.alarms;
    final nextAlarmRecord = service.nextAlarm;
    final c = context.hearthColors;

    return ThemedBackground.photo(
      strength: TintStrength.heavy,
      child: Stack(
        children: [
          Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.x4),
                child: _buildHeader(c, nextAlarmRecord),
              ),
              // Alarm list
              Expanded(
                child: alarms.isEmpty
                    ? _buildEmptyState(c)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: HearthSpacing.x4, vertical: HearthSpacing.x2),
                        itemCount: alarms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: HearthSpacing.x2),
                        itemBuilder: (context, index) {
                          return _AlarmCard(
                            alarm: alarms[index],
                            onTap: () => _editAlarm(context, ref, alarms[index]),
                            onToggle: () =>
                                service.toggleEnabled(alarms[index].id),
                          );
                        },
                      ),
              ),
            ],
          ),
          // FAB
          Positioned(
            right: HearthSpacing.x6,
            bottom: HearthSpacing.x6,
            child: FloatingActionButton(
              backgroundColor: c.accentFill,
              onPressed: () => _addAlarm(context, ref),
              child: Icon(Icons.add, color: c.onAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(HearthColors c, (Alarm, DateTime)? nextAlarmRecord) {
    String subtitle;
    if (nextAlarmRecord != null) {
      final now = DateTime.now();
      final nextFire = nextAlarmRecord.$2;
      final diff = nextFire.difference(now);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (hours > 0) {
        subtitle = 'Next alarm in ${hours}h ${minutes}m';
      } else {
        subtitle = 'Next alarm in ${minutes}m';
      }
    } else {
      subtitle = 'No alarms set';
    }

    return Column(
      children: [
        Text(
          'Alarms',
          style: TextStyle(
            fontSize: HearthFont.title,
            fontWeight: FontWeight.w300,
            color: c.text,
          ),
        ),
        const SizedBox(height: HearthSpacing.x1),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14, // equidistant between label=13 and body=15
            fontWeight: FontWeight.w300,
            color: c.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(HearthColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off, size: HearthIcon.xl, color: c.inkAt(0.24)),
          const SizedBox(height: HearthSpacing.x4),
          Text(
            'No alarms',
            style: TextStyle(
              fontSize: HearthFont.bodyLg,
              fontWeight: FontWeight.w200,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: HearthSpacing.x2),
          Text(
            'Tap + to create one',
            style: TextStyle(fontSize: HearthFont.label, color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _addAlarm(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<Alarm>(
      MaterialPageRoute(builder: (_) => const AlarmEditorScreen()),
    );
    if (result != null) {
      ref.read(alarmServiceProvider).addAlarm(result);
    }
  }

  Future<void> _editAlarm(
      BuildContext context, WidgetRef ref, Alarm alarm) async {
    final result = await Navigator.of(context).push<Alarm>(
      MaterialPageRoute(builder: (_) => AlarmEditorScreen(alarm: alarm)),
    );
    if (result != null) {
      ref.read(alarmServiceProvider).updateAlarm(result);
    }
  }
}

/// A single alarm card in the list.
class _AlarmCard extends StatelessWidget {
  final Alarm alarm;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _AlarmCard({
    required this.alarm,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Material(
      color: c.raised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x4, vertical: HearthSpacing.x3),
          child: Row(
            children: [
              // Time and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alarm.time,
                      style: TextStyle(
                        fontSize: HearthFont.display,
                        fontWeight: FontWeight.w200,
                        color: alarm.enabled ? c.text : c.textFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (alarm.label.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              alarm.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: HearthFont.label,
                                color: alarm.enabled
                                    ? c.textSecondary
                                    : c.inkAt(0.3),
                              ),
                            ),
                          ),
                          const SizedBox(width: HearthSpacing.x2),
                          Text(
                            '\u2022',
                            style: TextStyle(
                              fontSize: HearthFont.label,
                              color: alarm.enabled
                                  ? c.textFaint
                                  : c.inkAt(0.24),
                            ),
                          ),
                          const SizedBox(width: HearthSpacing.x2),
                        ],
                        Text(
                          alarm.daySummary,
                          style: TextStyle(
                            fontSize: HearthFont.label,
                            color:
                                alarm.enabled ? c.textMuted : c.inkAt(0.24),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Enable/disable switch
              Switch(
                value: alarm.enabled,
                onChanged: (_) => onToggle(),
                activeTrackColor: c.accent,
                inactiveTrackColor: c.inkAt(0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
