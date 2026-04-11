import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'home_assistant_service.dart';

/// Day/night display modes — controls ambient brightness and content.
enum DisplayMode { day, night }

/// Resolves the current display mode from whichever source the user configured.
///
/// Four trigger sources, each independent:
/// - "none": always day mode (default until user configures)
/// - "api": external device sets mode via POST /api/display-mode
/// - "ha_entity": watches an HA entity (e.g., light.living_room off = night)
/// - "clock": uses configured start/end times (handles overnight spans)
///
/// Only one source is active at a time — no fallback chain. This keeps
/// behavior predictable: if your clock says night, it's night, regardless
/// of what HA says.
class DisplayModeService {
  DisplayMode _apiMode = DisplayMode.day;
  bool _entityIsOn = true;
  final _modeController = StreamController<DisplayMode>.broadcast();
  StreamSubscription? _entitySub;

  Stream<DisplayMode> get modeStream => _modeController.stream;

  void setModeFromApi(DisplayMode mode) {
    _apiMode = mode;
    _modeController.add(mode);
  }

  void setEntityState({required bool isOn}) {
    _entityIsOn = isOn;
    _modeController.add(isOn ? DisplayMode.day : DisplayMode.night);
  }

  /// Subscribes to a specific HA entity for night mode detection.
  /// Entity "off" = night mode (e.g., living room light off means bedtime).
  void listenToHaEntity(HomeAssistantService ha, String entityId) {
    _entitySub = ha.entityStream.listen((entity) {
      if (entity.entityId == entityId) {
        setEntityState(isOn: entity.isOn);
      }
    });
  }

  DisplayMode resolveMode({required HubConfig config, DateTime? now}) {
    switch (config.nightModeSource) {
      case 'none':
        return DisplayMode.day;
      case 'api':
        return _apiMode;
      case 'ha_entity':
        return _entityIsOn ? DisplayMode.day : DisplayMode.night;
      case 'clock':
        return _resolveClockMode(config, now ?? DateTime.now());
      default:
        return DisplayMode.day;
    }
  }

  /// Parses an "HH:MM" string into total minutes since midnight.
  /// Returns null if the string is malformed or out of range.
  static int? _parseTimeToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// Handles overnight time ranges (e.g., 22:00-07:00) by checking
  /// whether "now" falls within the wrapped range.
  DisplayMode _resolveClockMode(HubConfig config, DateTime now) {
    if (config.nightModeClockStart == null ||
        config.nightModeClockEnd == null) {
      return DisplayMode.day;
    }

    final startMinutes = _parseTimeToMinutes(config.nightModeClockStart!);
    final endMinutes = _parseTimeToMinutes(config.nightModeClockEnd!);
    if (startMinutes == null || endMinutes == null) return DisplayMode.day;
    final nowMinutes = now.hour * 60 + now.minute;

    if (startMinutes > endMinutes) {
      // Overnight range: 22:00 (1320) to 07:00 (420)
      if (nowMinutes >= startMinutes || nowMinutes < endMinutes) {
        return DisplayMode.night;
      }
    } else {
      if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
        return DisplayMode.night;
      }
    }
    return DisplayMode.day;
  }

  void dispose() {
    _entitySub?.cancel();
    _modeController.close();
  }
}

final displayModeServiceProvider = Provider<DisplayModeService>((ref) {
  final nightSource = ref.watch(hubConfigProvider.select((c) => c.nightModeSource));
  final nightEntity = ref.watch(hubConfigProvider.select((c) => c.nightModeHaEntity));
  final service = DisplayModeService();
  ref.onDispose(() => service.dispose());
  if (nightSource == 'ha_entity' && nightEntity != null) {
    final ha = ref.watch(homeAssistantServiceProvider);
    service.listenToHaEntity(ha, nightEntity);
  }
  return service;
});

final displayModeProvider = StreamProvider<DisplayMode>((ref) {
  final service = ref.watch(displayModeServiceProvider);
  return service.modeStream;
});
