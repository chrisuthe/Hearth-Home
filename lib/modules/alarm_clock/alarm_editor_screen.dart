import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../app/tokens/tokens.dart';
import 'alarm_models.dart';
import 'alarm_service.dart';

/// Available builtin alarm tones. Must match [AlarmAudioPlayer.builtinTones]
/// in alarm_audio.dart — both lists exist for layering reasons but ought to
/// be consolidated. If you add/remove a tone, update BOTH.
const builtinTones = <String, String>{
  'gentle_morning': 'Gentle Morning',
  'birds': 'Birdsong',
  'classic': 'Classic',
  'bright': 'Bright Day',
};

/// Full-screen editor for creating or editing an alarm.
///
/// Returns the modified [Alarm] via Navigator.pop, or null if cancelled.
/// In edit mode, a delete button is also available.
class AlarmEditorScreen extends ConsumerStatefulWidget {
  final Alarm? alarm;

  const AlarmEditorScreen({super.key, this.alarm});

  @override
  ConsumerState<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends ConsumerState<AlarmEditorScreen> {
  late int _hour;
  late int _minute;
  late List<int> _days;
  late String _label;
  late bool _sunriseEnabled;
  late int _sunriseDuration;
  late String _soundId;
  late int _snoozeDuration;
  late double _volume;
  late final TextEditingController _labelController;

  bool get _isEditing => widget.alarm != null;

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    _hour = a?.hour ?? 7;
    _minute = a?.minute ?? 0;
    _days = List<int>.from(a?.days ?? []);
    _label = a?.label ?? '';
    _sunriseEnabled = (a?.sunriseDuration ?? 0) > 0;
    _sunriseDuration = a?.sunriseDuration ?? 15;
    _soundId = a?.soundId ?? 'gentle_morning';
    _snoozeDuration = a?.snoozeDuration ?? 10;
    _volume = a?.volume ?? 0.7;
    _labelController = TextEditingController(text: _label);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Alarm _buildAlarm() {
    final id = widget.alarm?.id ?? _generateId();
    return Alarm(
      id: id,
      time:
          '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
      label: _label,
      enabled: widget.alarm?.enabled ?? true,
      days: _days,
      oneTime: _days.isEmpty,
      sunriseDuration: _sunriseEnabled ? _sunriseDuration : 0,
      soundId: _soundId,
      snoozeDuration: _snoozeDuration,
      volume: _volume,
    );
  }

  static String _generateId() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  void _save() {
    Navigator.of(context).pop(_buildAlarm());
  }

  void _delete() {
    if (widget.alarm != null) {
      ref.read(alarmServiceProvider).deleteAlarm(widget.alarm!.id);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(HearthSpacing.x2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    _isEditing ? 'Edit Alarm' : 'New Alarm',
                    style: const TextStyle(
                      fontSize: 16, // equidistant between body=15 and bodyLg=17
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: HearthSpacing.x12),
                ],
              ),
            ),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: HearthSpacing.x2),
                    // Time picker
                    _buildTimePicker(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Day-of-week toggles
                    _buildDayPicker(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Label
                    _buildLabelField(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Sunrise settings
                    _buildSunriseSection(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Sound picker
                    _buildSoundPicker(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Snooze duration
                    _buildSnoozeSection(),
                    const SizedBox(height: HearthSpacing.x6),
                    // Volume
                    _buildVolumeSlider(),
                    const SizedBox(height: HearthSpacing.x8),
                    // Action buttons
                    _buildActionButtons(),
                    const SizedBox(height: HearthSpacing.x8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker() {
    return Center(
      child: SizedBox(
        height: 180,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ScrollWheel(
              label: 'hr',
              maxValue: 23,
              initialValue: _hour,
              onChanged: (v) => setState(() => _hour = v),
            ),
            const Padding(
              padding: EdgeInsets.only(top: HearthSpacing.x5),
              child: Text(
                ':',
                style: TextStyle(
                  fontSize: HearthFont.display,
                  fontWeight: FontWeight.w200,
                  color: Colors.white38,
                ),
              ),
            ),
            _ScrollWheel(
              label: 'min',
              maxValue: 59,
              initialValue: _minute,
              onChanged: (v) => setState(() => _minute = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayPicker() {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    // ISO weekdays: Mon=1 .. Sun=7
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Repeat',
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w500,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: HearthSpacing.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(7, (index) {
            final day = index + 1; // 1=Mon .. 7=Sun
            final selected = _days.contains(day);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x1),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _days.remove(day);
                    } else {
                      _days.add(day);
                      _days.sort();
                    }
                  });
                },
                child: Container(
                  width: HearthSpacing.x10,
                  height: HearthSpacing.x10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFF646CFF)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    dayLabels[index],
                    style: TextStyle(
                      fontSize: 14, // equidistant between label=13 and body=15
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildLabelField() {
    return TextField(
      controller: _labelController,
      onChanged: (v) => _label = v,
      style: const TextStyle(color: Colors.white, fontSize: HearthFont.body),
      decoration: InputDecoration(
        labelText: 'Label',
        labelStyle: const TextStyle(color: Colors.white54, fontSize: HearthFont.label),
        filled: true,
        fillColor: kDialogBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(HearthSpacing.x3),
      ),
    );
  }

  Widget _buildSunriseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Sunrise effect',
              style: TextStyle(
                fontSize: HearthFont.label,
                fontWeight: FontWeight.w500,
                color: Colors.white54,
              ),
            ),
            const Spacer(),
            Switch(
              value: _sunriseEnabled,
              onChanged: (v) => setState(() => _sunriseEnabled = v),
              activeTrackColor: const Color(0xFF646CFF),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            ),
          ],
        ),
        if (_sunriseEnabled) ...[
          const SizedBox(height: HearthSpacing.x2),
          const Text(
            'Duration',
            style: TextStyle(fontSize: 12, color: Colors.white38), // equidistant caption=11/label=13
          ),
          const SizedBox(height: 6), // equidistant x1=4/x2=8
          Wrap(
            spacing: HearthSpacing.x2,
            children: [5, 10, 15, 20, 25, 30].map((minutes) {
              final selected = _sunriseDuration == minutes;
              return ChoiceChip(
                label: Text('${minutes}m'),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _sunriseDuration = minutes),
                selectedColor: const Color(0xFF646CFF),
                backgroundColor: kDialogBackground,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12, // equidistant caption=11/label=13
                ),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSoundPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alarm sound',
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w500,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: HearthSpacing.x2),
        ...builtinTones.entries.map((entry) {
          final selected = _soundId == entry.key;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _soundId = entry.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.x3, vertical: 10), // vertical 10: equidistant x2=8/x3=12
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF646CFF).withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18, // equidistant xs=16/sm=20
                      color: selected
                          ? const Color(0xFF646CFF)
                          : Colors.white38,
                    ),
                    const SizedBox(width: HearthSpacing.x3),
                    Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 14, // equidistant label=13/body=15
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSnoozeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Snooze duration',
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w500,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: HearthSpacing.x2),
        Wrap(
          spacing: HearthSpacing.x2,
          children: [5, 10, 15, 20].map((minutes) {
            final selected = _snoozeDuration == minutes;
            return ChoiceChip(
              label: Text('${minutes}m'),
              selected: selected,
              onSelected: (_) =>
                  setState(() => _snoozeDuration = minutes),
              selectedColor: const Color(0xFF646CFF),
              backgroundColor: kDialogBackground,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12, // equidistant caption=11/label=13
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVolumeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Volume',
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w500,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: HearthSpacing.x1),
        Row(
          children: [
            const Icon(Icons.volume_down, color: Colors.white38, size: HearthIcon.sm),
            Expanded(
              child: Slider(
                value: _volume,
                onChanged: (v) => setState(() => _volume = v),
                activeColor: const Color(0xFF646CFF),
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white38, size: HearthIcon.sm),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (_isEditing) ...[
          Expanded(
            child: Material(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: _delete,
                borderRadius: BorderRadius.circular(28),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFF5252),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: HearthSpacing.x4),
        ],
        Expanded(
          child: Material(
            color: const Color(0xFF646CFF),
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              onTap: _save,
              borderRadius: BorderRadius.circular(28),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Scroll wheel for picking hours or minutes.
///
/// Reuses the same pattern as timer_screen.dart _ScrollWheel.
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
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialValue;
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
            style: const TextStyle(fontSize: 12, color: Colors.white38)), // equidistant caption=11/label=13
        const SizedBox(height: HearthSpacing.x1),
        SizedBox(
          width: 70, // scroll wheel width — functional layout constraint
          height: 150, // scroll wheel height — layout constraint far outside palette
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: 50,
            perspective: 0.005,
            diameterRatio: 1.2,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              setState(() => _selectedIndex = index);
              widget.onChanged(index);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.maxValue + 1,
              builder: (context, index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: HearthFont.display,
                      fontWeight: FontWeight.w200,
                      color: index == _selectedIndex
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
