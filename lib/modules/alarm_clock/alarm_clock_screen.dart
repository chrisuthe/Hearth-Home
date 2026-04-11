import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import 'alarm_editor_screen.dart';
import 'alarm_models.dart';
import 'alarm_service.dart';

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

    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Stack(
        children: [
          Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: _buildHeader(nextAlarmRecord),
              ),
              // Alarm list
              Expanded(
                child: alarms.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: alarms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
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
            right: 24,
            bottom: 24,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF646CFF),
              onPressed: () => _addAlarm(context, ref),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader((Alarm, DateTime)? nextAlarmRecord) {
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
        const Text(
          'Alarms',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w300,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w300,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off, size: 48, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No alarms',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w200,
              color: Colors.white38,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap + to create one',
            style: TextStyle(fontSize: 13, color: Colors.white24),
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
    return Material(
      color: kDialogBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        fontSize: 36,
                        fontWeight: FontWeight.w200,
                        color: alarm.enabled ? Colors.white : Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (alarm.label.isNotEmpty) ...[
                          Text(
                            alarm.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: alarm.enabled
                                  ? Colors.white70
                                  : Colors.white30,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\u2022',
                            style: TextStyle(
                              fontSize: 13,
                              color: alarm.enabled
                                  ? Colors.white38
                                  : Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          alarm.daySummary,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                alarm.enabled ? Colors.white54 : Colors.white24,
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
                activeTrackColor: const Color(0xFF646CFF),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
