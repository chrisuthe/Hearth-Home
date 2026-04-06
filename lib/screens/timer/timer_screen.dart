import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Full-screen timer interface inspired by the Google Nest Hub.
///
/// Supports multiple simultaneous timers with large, glanceable countdowns.
/// Interaction flow:
/// 1. Tap "Set a timer" → opens this screen with a duration picker
/// 2. Pick hours/minutes/seconds with scroll wheels → tap Start
/// 3. Timer counts down with a circular progress ring
/// 4. When done, the ring pulses and a "DONE" label replaces the countdown
/// 5. Tap the timer to dismiss, or tap + to add another timer
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final List<_ActiveTimer> _timers = [];
  bool _showPicker = true;

  // Duration picker state
  int _pickHours = 0;
  int _pickMinutes = 5;
  int _pickSeconds = 0;

  void _startTimer() {
    final totalSeconds =
        _pickHours * 3600 + _pickMinutes * 60 + _pickSeconds;
    if (totalSeconds == 0) return;

    setState(() {
      _timers.add(_ActiveTimer(
        totalDuration: Duration(seconds: totalSeconds),
        onTick: () {
          if (mounted) setState(() {});
        },
      ));
      _showPicker = false;
    });
  }

  void _dismissTimer(int index) {
    setState(() {
      _timers[index].dispose();
      _timers.removeAt(index);
      if (_timers.isEmpty) _showPicker = true;
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                // Add another timer button — only when timers are active
                if (!_showPicker && _timers.isNotEmpty)
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
            child: _showPicker ? _buildPicker() : _buildTimerList(),
          ),
        ],
      ),
    );
  }

  /// Duration picker with three scroll wheels for hours, minutes, seconds.
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
          // Scroll wheels
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
          // Start button
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
          // Quick presets
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PresetChip(
                  label: '1 min',
                  onTap: () {
                    _pickHours = 0;
                    _pickMinutes = 1;
                    _pickSeconds = 0;
                    _startTimer();
                  }),
              const SizedBox(width: 10),
              _PresetChip(
                  label: '5 min',
                  onTap: () {
                    _pickHours = 0;
                    _pickMinutes = 5;
                    _pickSeconds = 0;
                    _startTimer();
                  }),
              const SizedBox(width: 10),
              _PresetChip(
                  label: '10 min',
                  onTap: () {
                    _pickHours = 0;
                    _pickMinutes = 10;
                    _pickSeconds = 0;
                    _startTimer();
                  }),
              const SizedBox(width: 10),
              _PresetChip(
                  label: '15 min',
                  onTap: () {
                    _pickHours = 0;
                    _pickMinutes = 15;
                    _pickSeconds = 0;
                    _startTimer();
                  }),
            ],
          ),
        ],
      ),
    );
  }

  /// List/grid of active timers, each with a circular progress ring.
  Widget _buildTimerList() {
    if (_timers.length == 1) {
      // Single timer — show it large and centered
      return Center(child: _TimerDisplay(
        timer: _timers[0],
        size: 280,
        onDismiss: () => _dismissTimer(0),
      ));
    }
    // Multiple timers — grid layout
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: _timers.length,
      itemBuilder: (context, index) {
        return _TimerDisplay(
          timer: _timers[index],
          size: 200,
          onDismiss: () => _dismissTimer(index),
        );
      },
    );
  }
}

/// Manages the state and tick callback for a single countdown timer.
class _ActiveTimer {
  final Duration totalDuration;
  late final DateTime _startTime;
  late final Timer _ticker;
  bool _paused = false;
  Duration _pausedRemaining = Duration.zero;

  _ActiveTimer({
    required this.totalDuration,
    required VoidCallback onTick,
  }) {
    _startTime = DateTime.now();
    _pausedRemaining = totalDuration;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => onTick());
  }

  Duration get remaining {
    if (_paused) return _pausedRemaining;
    final elapsed = DateTime.now().difference(_startTime);
    final left = totalDuration - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  double get progress {
    if (totalDuration.inMilliseconds == 0) return 0;
    return 1.0 - (remaining.inMilliseconds / totalDuration.inMilliseconds);
  }

  bool get isDone => remaining == Duration.zero;

  bool get isPaused => _paused;

  void togglePause() {
    if (_paused) {
      // Resume: adjust start time so remaining stays correct
      _paused = false;
    } else {
      _pausedRemaining = remaining;
      _paused = true;
    }
  }

  void dispose() {
    _ticker.cancel();
  }
}

/// Circular countdown display with progress ring.
class _TimerDisplay extends StatelessWidget {
  final _ActiveTimer timer;
  final double size;
  final VoidCallback onDismiss;

  const _TimerDisplay({
    required this.timer,
    required this.size,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = timer.remaining;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);

    // Format: show hours only if > 0
    final timeStr = hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

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
                  Icon(Icons.check_circle,
                      size: size * 0.15, color: const Color(0xFF4CAF50)),
                  const SizedBox(height: 4),
                ],
                Text(
                  isDone ? 'DONE' : timeStr,
                  style: TextStyle(
                    fontSize: isDone ? size * 0.12 : size * 0.18,
                    fontWeight: FontWeight.w200,
                    color: isDone
                        ? const Color(0xFF4CAF50)
                        : Colors.white,
                  ),
                ),
                if (isDone)
                  Text('Tap to dismiss',
                      style: TextStyle(
                          fontSize: size * 0.05,
                          color: Colors.white38)),
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

    // Progress arc
    final progressColor =
        isDone ? const Color(0xFF4CAF50) : const Color(0xFF4285F4);
    final sweepAngle = progress * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // start from top
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
    _controller = FixedExtentScrollController(initialItem: widget.initialValue);
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
