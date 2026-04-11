import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/home_assistant_service.dart';
import '../../utils/logger.dart';

class SunriseController extends ChangeNotifier {
  static final _keyframes = <double, Color>{
    0.00: const Color(0xFF000000),
    0.15: const Color(0xFF0A1028),
    0.30: const Color(0xFF2A1040),
    0.50: const Color(0xFF4A2010),
    0.70: const Color(0xFFC05820),
    0.85: const Color(0xFFE8A030),
    1.00: const Color(0xFFFFD890),
  };

  double _progress = 0.0;
  Timer? _ticker;
  bool _active = false;
  int _durationMinutes = 15;
  List<String> _lightEntities = [];
  HomeAssistantService? _ha;
  DateTime? _startTime;

  double get progress => _progress;
  bool get active => _active;

  Color get currentColor {
    final entries = _keyframes.entries.toList();
    for (int i = 0; i < entries.length - 1; i++) {
      if (_progress >= entries[i].key && _progress <= entries[i + 1].key) {
        final t = (_progress - entries[i].key) /
            (entries[i + 1].key - entries[i].key);
        return Color.lerp(entries[i].value, entries[i + 1].value, t)!;
      }
    }
    return entries.last.value;
  }

  void start({
    required int durationMinutes,
    required List<String> lightEntities,
    HomeAssistantService? ha,
  }) {
    _durationMinutes = durationMinutes;
    _lightEntities = lightEntities;
    _ha = ha;
    _progress = 0.0;
    _active = true;
    _startTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Log.i('Sunrise', 'Started sunrise over $durationMinutes minutes');
    notifyListeners();
  }

  void _tick() {
    if (_startTime == null) return;
    final elapsed = DateTime.now().difference(_startTime!);
    _progress = (elapsed.inSeconds / (_durationMinutes * 60)).clamp(0.0, 1.0);
    notifyListeners();

    // Ramp HA lights every 30 seconds.
    if (elapsed.inSeconds % 30 == 0 && _ha != null) {
      _rampLights();
    }
  }

  void _rampLights() {
    // Quadratic ease-in: slow start, accelerating.
    final brightness = (_progress * _progress * 255).round().clamp(0, 255);
    // Color temp: 2200K (454 mireds) to 4000K (250 mireds).
    final mireds =
        (454 - (_progress * _progress * 204)).round().clamp(250, 454);

    for (final entityId in _lightEntities) {
      _ha!.callService(
        domain: 'light',
        service: 'turn_on',
        entityId: entityId,
        data: {
          'brightness': brightness,
          'color_temp': mireds,
        },
      );
    }
    Log.d('Sunrise',
        'Lights: brightness=$brightness, mireds=$mireds, progress=${_progress.toStringAsFixed(2)}');
  }

  void snooze(int snoozeDurationMinutes) {
    _durationMinutes = snoozeDurationMinutes;
    _progress = 0.3; // Dim to purple level.
    _startTime = DateTime.now();
    Log.i('Sunrise', 'Snoozed, restarting ramp over $snoozeDurationMinutes minutes');
    notifyListeners();
    // Dim lights to 30%.
    if (_ha != null) {
      for (final entityId in _lightEntities) {
        _ha!.callService(
          domain: 'light',
          service: 'turn_on',
          entityId: entityId,
          data: {'brightness': 77, 'color_temp': 454},
        );
      }
    }
  }

  void dismiss() {
    _ticker?.cancel();
    _ticker = null;
    _active = false;
    _progress = 0.0;
    _startTime = null;
    // Leave lights as-is — user is awake.
    Log.i('Sunrise', 'Dismissed');
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sunriseControllerProvider =
    ChangeNotifierProvider<SunriseController>((ref) {
  return SunriseController();
});
