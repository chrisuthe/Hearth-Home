import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/timer_service.dart';

/// Full-screen timer interface inspired by the Google Nest Hub.
///
/// All timer state lives in [TimerService] via Riverpod, so timers
/// keep counting when you navigate away. This screen is just a view
/// into the global timer state — setting timers, viewing countdowns,
/// and dismissing completed ones.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  bool _showPicker = false;

  // Duration picker state
  int _pickHours = 0;
  int _pickMinutes = 5;
  int _pickSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Show the picker if there are no active timers
    final service = ref.read(timerServiceProvider);
    _showPicker = service.timers.isEmpty;
  }

  void _startTimer() {
    final totalSeconds =
        _pickHours * 3600 + _pickMinutes * 60 + _pickSeconds;
    if (totalSeconds == 0) return;

    ref.read(timerServiceProvider).startTimer(Duration(seconds: totalSeconds));
    setState(() => _showPicker = false);
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(timerServiceProvider);
    final timers = service.timers;

    // Auto-show picker if all timers are dismissed
    if (timers.isEmpty && !_showPicker) {
      _showPicker = true;
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        children: [
          // Header with back button and add timer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                const Text('Timers',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        color: Colors.white)),
                const Spacer(),
                if (!_showPicker && timers.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.white70),
                    onPressed: () => setState(() => _showPicker = true),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),

          Expanded(
            child: _showPicker ? _buildPicker() : _buildTimerList(timers),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Set a timer',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w200,
                  color: Colors.white70)),
          const SizedBox(height: 32),
          SizedBox(
            height: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ScrollWheel(
                  label: 'hr',
                  maxValue: 23,
                  initialValue: _pickHours,
                  onChanged: (v) => _pickHours = v,
                ),
                const SizedBox(width: 16),
                _ScrollWheel(
                  label: 'min',
                  maxValue: 59,
                  initialValue: _pickMinutes,
                  onChanged: (v) => _pickMinutes = v,
                ),
                const SizedBox(width: 16),
                _ScrollWheel(
                  label: 'sec',
                  maxValue: 59,
                  initialValue: _pickSeconds,
                  onChanged: (v) => _pickSeconds = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _startTimer,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Text('Start',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PresetChip(label: '1 min', onTap: () {
                _pickHours = 0; _pickMinutes = 1; _pickSeconds = 0;
                _startTimer();
              }),
              const SizedBox(width: 10),
              _PresetChip(label: '5 min', onTap: () {
                _pickHours = 0; _pickMinutes = 5; _pickSeconds = 0;
                _startTimer();
              }),
              const SizedBox(width: 10),
              _PresetChip(label: '10 min', onTap: () {
                _pickHours = 0; _pickMinutes = 10; _pickSeconds = 0;
                _startTimer();
              }),
              const SizedBox(width: 10),
              _PresetChip(label: '15 min', onTap: () {
                _pickHours = 0; _pickMinutes = 15; _pickSeconds = 0;
                _startTimer();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimerList(List<HubTimer> timers) {
    final service = ref.read(timerServiceProvider);

    if (timers.length == 1) {
      return Center(
        child: TimerDisplay(
          timer: timers[0],
          size: 280,
          onDismiss: () => service.dismissTimer(timers[0].id),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: timers.length,
      itemBuilder: (context, index) {
        return TimerDisplay(
          timer: timers[index],
          size: 200,
          onDismiss: () => service.dismissTimer(timers[index].id),
        );
      },
    );
  }
}

/// Circular countdown display with progress ring.
/// Public so HubShell can reuse it in the fired-timer alert overlay.
class TimerDisplay extends StatelessWidget {
  final HubTimer timer;
  final double size;
  final VoidCallback? onDismiss;

  const TimerDisplay({
    super.key,
    required this.timer,
    required this.size,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = timer.isDone;

    return GestureDetector(
      onTap: isDone ? onDismiss : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring
            SizedBox(
              width: size * 0.9,
              height: size * 0.9,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: timer.progress,
                  isDone: isDone,
                ),
              ),
            ),
            // Countdown text
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDone) ...[
                  Icon(Icons.timer,
                      size: size * 0.15, color: const Color(0xFFFF9800)),
                  const SizedBox(height: 4),
                ],
                Text(
                  isDone ? "Time's up!" : timer.remainingLabel,
                  style: TextStyle(
                    fontSize: isDone ? size * 0.1 : size * 0.18,
                    fontWeight: FontWeight.w200,
                    color: isDone ? const Color(0xFFFF9800) : Colors.white,
                  ),
                ),
                if (isDone)
                  Text('Tap to dismiss',
                      style: TextStyle(
                          fontSize: size * 0.05, color: Colors.white38)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the circular progress ring.
class _RingPainter extends CustomPainter {
  final double progress;
  final bool isDone;

  _RingPainter({required this.progress, required this.isDone});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 6.0;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc — blue while counting, orange when done
    final progressColor =
        isDone ? const Color(0xFFFF9800) : const Color(0xFF4285F4);
    final sweepAngle = progress * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDone != isDone;
}

/// Scroll wheel for picking hours, minutes, or seconds.
class _ScrollWheel extends StatefulWidget {
  final String label;
  final int maxValue;
  final int initialValue;
  final ValueChanged<int> onChanged;

  const _ScrollWheel({
    required this.label,
    required this.maxValue,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_ScrollWheel> createState() => _ScrollWheelState();
}

class _ScrollWheelState extends State<_ScrollWheel> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        FixedExtentScrollController(initialItem: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 4),
        SizedBox(
          width: 70,
          height: 150,
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: 50,
            perspective: 0.005,
            diameterRatio: 1.2,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: widget.onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.maxValue + 1,
              builder: (context, index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w200,
                      color: index == _controller.selectedItem
                          ? Colors.white
                          : Colors.white38,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Quick-select duration chip below the picker.
class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
      ),
    );
  }
}
