import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'alarm_service.dart';
import 'sunrise_controller.dart';

/// Full-screen overlay shown when an alarm fires.
///
/// Follows the same pattern as _TimerAlertOverlay in hub_shell.dart:
/// - Isolated ConsumerWidget so rebuilds are scoped to this overlay
/// - Uses addPostFrameCallback to wake from idle without setState during build
/// - GestureDetector tap anywhere = snooze, explicit Dismiss button = dismiss
class AlarmAlertOverlay extends ConsumerWidget {
  final VoidCallback onWake;

  const AlarmAlertOverlay({super.key, required this.onWake});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmService = ref.watch(alarmServiceProvider);
    final firedAlarm = alarmService.firedAlarm;
    if (firedAlarm == null) return const SizedBox.shrink();

    // Wake from idle when an alarm fires — deferred to avoid
    // notifyListeners() during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => onWake());

    final sunriseController = ref.watch(sunriseControllerProvider);
    final bgColor = sunriseController.active
        ? sunriseController.currentColor
        : Colors.black;

    return GestureDetector(
      // Tap anywhere to snooze
      onTap: () {
        alarmService.snooze();
        if (sunriseController.active) {
          sunriseController.snooze(firedAlarm.snoozeDuration);
        }
      },
      child: Container(
        color: bgColor.withValues(alpha: 0.95),
        child: Stack(
          children: [
            // Main content — centered time and label
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current time (large)
                  _CurrentTimeDisplay(),
                  const SizedBox(height: 16),
                  // Alarm icon
                  const Icon(Icons.alarm,
                      size: 48, color: Color(0xFF646CFF)),
                  const SizedBox(height: 12),
                  // Alarm label
                  if (firedAlarm.label.isNotEmpty)
                    Text(
                      firedAlarm.label,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
            // Bottom controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dismiss button (explicit tap target)
                  SizedBox(
                    height: 60,
                    width: 200,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(30),
                      child: InkWell(
                        onTap: () {
                          alarmService.dismiss();
                          if (sunriseController.active) {
                            sunriseController.dismiss();
                          }
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: const Center(
                          child: Text(
                            'Dismiss',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Snooze hint
                  Text(
                    'Tap anywhere to snooze',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the current time, updating every second.
///
/// Isolated in its own widget so 1-second ticks only rebuild this text,
/// not the entire overlay.
class _CurrentTimeDisplay extends StatefulWidget {
  @override
  State<_CurrentTimeDisplay> createState() => _CurrentTimeDisplayState();
}

class _CurrentTimeDisplayState extends State<_CurrentTimeDisplay> {
  late Timer _ticker;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hour:$minute',
      style: const TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w200,
        color: Colors.white,
      ),
    );
  }
}
