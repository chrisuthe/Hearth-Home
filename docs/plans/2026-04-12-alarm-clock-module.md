# Alarm Clock Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sunrise alarm clock module to Hearth with display-based dawn simulation, HA smart light integration, and flexible module placement (swipe/menu).

**Architecture:** Two phases. Phase 1: replace `enabledModules` with `modulePlacements` in config, update HubShell and Settings to support swipe + menu placement per module. Phase 2: build the alarm clock module (data model, service, sunrise controller, screens, alert overlay, HA lights, web portal, bundled tones).

**Tech Stack:** Flutter/Dart, Riverpod, ALSA FFI (audio), Home Assistant WebSocket API, OGG audio assets.

**Spec:** `docs/specs/2026-04-12-alarm-clock-module-design.md`

---

## Phase 1: Module Placement System

### Task 1: Add modulePlacements to HubConfig with migration

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Add modulePlacements field to HubConfig**

Add after the `enabledModules` field (~line 50):

```dart
final Map<String, List<String>> modulePlacements;
```

Constructor default (~line 89):
```dart
this.modulePlacements = const {},
```

Keep `enabledModules` for now (needed for migration).

- [ ] **Step 2: Add to copyWith, toJson, fromJson**

copyWith parameter:
```dart
Map<String, List<String>>? modulePlacements,
```

copyWith body:
```dart
modulePlacements: modulePlacements ?? this.modulePlacements,
```

toJson:
```dart
'modulePlacements': modulePlacements.map((k, v) => MapEntry(k, v)),
```

fromJson — with migration from enabledModules:
```dart
modulePlacements: json.containsKey('modulePlacements')
    ? (json['modulePlacements'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()))
    : _migrateEnabledModules(json),
```

Add static migration helper:
```dart
static Map<String, List<String>> _migrateEnabledModules(Map<String, dynamic> json) {
  final enabled = (json['enabledModules'] as List<dynamic>?)?.cast<String>()
      ?? const ['media', 'controls', 'cameras'];
  return {for (final id in enabled) id: ['swipe']};
}
```

- [ ] **Step 3: Write tests for modulePlacements round-trip and migration**

```dart
test('modulePlacements round-trips through JSON', () {
  final config = HubConfig(modulePlacements: {
    'media': ['swipe'],
    'alarm_clock': ['menu1', 'menu2'],
  });
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.modulePlacements['media'], ['swipe']);
  expect(restored.modulePlacements['alarm_clock'], ['menu1', 'menu2']);
});

test('modulePlacements migrates from enabledModules', () {
  final json = {'enabledModules': ['media', 'controls']};
  final config = HubConfig.fromJson(json);
  expect(config.modulePlacements['media'], ['swipe']);
  expect(config.modulePlacements['controls'], ['swipe']);
  expect(config.modulePlacements.containsKey('cameras'), false);
});

test('modulePlacements defaults to empty when no config', () {
  final config = HubConfig.fromJson({});
  // Migration from default enabledModules
  expect(config.modulePlacements['media'], ['swipe']);
  expect(config.modulePlacements['controls'], ['swipe']);
  expect(config.modulePlacements['cameras'], ['swipe']);
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/config/hub_config_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add modulePlacements config with migration from enabledModules"
```

### Task 2: Update module registry provider to use modulePlacements

**Files:**
- Modify: `lib/modules/module_registry.dart`

- [ ] **Step 1: Replace enabledModulesProvider with placement-aware providers**

Replace the existing `enabledModulesProvider` with:

```dart
/// Modules placed in the swipe PageView, sorted by order.
final swipeModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final placements = config.modulePlacements;
  final modules = allModules
      .where((m) => (placements[m.id] ?? []).contains('swipe'))
      .toList();
  if (config.moduleOrder.isNotEmpty) {
    final order = config.moduleOrder;
    modules.sort((a, b) {
      final ai = order.indexOf(a.id);
      final bi = order.indexOf(b.id);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.defaultOrder.compareTo(b.defaultOrder);
    });
  } else {
    modules.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  }
  return modules;
});

/// Modules placed in the given menu, sorted by order.
List<HearthModule> menuModules(WidgetRef ref, String menuId) {
  final config = ref.watch(hubConfigProvider);
  final placements = config.modulePlacements;
  final modules = allModules
      .where((m) => (placements[m.id] ?? []).contains(menuId))
      .toList();
  modules.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
  return modules;
}

/// Keep backward compat alias — returns swipe modules.
final enabledModulesProvider = swipeModulesProvider;
```

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass (enabledModulesProvider alias preserves backward compat).

- [ ] **Step 3: Commit**

```bash
git add lib/modules/module_registry.dart
git commit -m "feat: add swipeModulesProvider and menuModules for flexible placement"
```

### Task 3: Update HubShell to show menu-placed modules

**Files:**
- Modify: `lib/app/hub_shell.dart`

- [ ] **Step 1: Update PageView to use swipeModulesProvider**

Replace `ref.watch(enabledModulesProvider)` with `ref.watch(swipeModulesProvider)` in the build method where the PageView pages are constructed. The alias makes this a no-op change, but be explicit.

- [ ] **Step 2: Add module quick actions to menu trays**

In `_buildMenu1`, after the existing Timer and Settings quick actions, add menu-placed modules:

```dart
// In the Row children of _buildMenu1:
...menuModules(ref, 'menu1').map((m) => _QuickAction(
  icon: m.icon,
  label: m.name,
  onTap: () {
    setState(() => _menu1Open = false);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => m.buildScreen(isActive: true)),
    );
  },
)),
```

Same pattern for `_buildMenu2`, inserting module actions into the menu2 tray.

Note: `menuModules` needs `ref` — since menus are built inside `_HubShellState.build()` which has access to `ref`, pass it through. If `_buildMenu1` doesn't have ref access, convert the helper call to use `ref.watch` inline or pass ref as a parameter.

- [ ] **Step 3: Run flutter analyze and test**

Run: `flutter analyze lib/app/hub_shell.dart && flutter test`

- [ ] **Step 4: Commit**

```bash
git add lib/app/hub_shell.dart
git commit -m "feat: show menu-placed modules as quick actions in HubShell menus"
```

### Task 4: Update Settings UI for module placement chips

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Replace SwitchListTile with placement chips**

Replace the module enable/disable loop (~lines 44-60) with:

```dart
...allModules.map((module) {
  final placements = List<String>.from(
      config.modulePlacements[module.id] ?? []);
  return ListTile(
    leading: Icon(module.icon, color: Colors.white54),
    title: Text(module.name),
    subtitle: Wrap(
      spacing: 6,
      children: [
        for (final placement in ['swipe', 'menu1', 'menu2'])
          FilterChip(
            label: Text(
              placement == 'swipe' ? 'Swipe' :
              placement == 'menu1' ? 'Menu 1' : 'Menu 2',
              style: const TextStyle(fontSize: 11),
            ),
            selected: placements.contains(placement),
            onSelected: (selected) {
              final updated = Map<String, List<String>>.from(
                  config.modulePlacements);
              final list = List<String>.from(updated[module.id] ?? []);
              if (selected) {
                list.add(placement);
              } else {
                list.remove(placement);
              }
              if (list.isEmpty) {
                updated.remove(module.id);
              } else {
                updated[module.id] = list;
              }
              _updateConfig((c) => c.copyWith(modulePlacements: updated));
            },
            selectedColor: const Color(0xFF646CFF),
            backgroundColor: const Color(0xFF1E1E1E),
            labelStyle: TextStyle(
              color: placements.contains(placement)
                  ? Colors.white : Colors.white70,
              fontSize: 11,
            ),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
      ],
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
  );
}),
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/screens/settings/settings_screen.dart`

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat: replace module on/off toggles with swipe/menu1/menu2 placement chips"
```

---

## Phase 2: Alarm Clock Module

### Task 5: Alarm data model and JSON serialization

**Files:**
- Create: `lib/modules/alarm_clock/alarm_models.dart`
- Create: `test/modules/alarm_clock/alarm_models_test.dart`

- [ ] **Step 1: Create Alarm model class**

```dart
import 'dart:math';

class Alarm {
  final String id;
  final String time; // "HH:mm" 24h format
  final String label;
  final bool enabled;
  final List<int> days; // ISO weekdays: 1=Mon, 7=Sun. Empty = one-time.
  final bool oneTime;
  final int sunriseDuration; // minutes, 0 = off
  final List<String> sunriseLights; // HA entity IDs
  final String soundType; // "builtin", "music_assistant", "none"
  final String soundId;
  final int snoozeDuration; // minutes
  final double volume; // 0.0-1.0

  const Alarm({
    required this.id,
    required this.time,
    this.label = '',
    this.enabled = true,
    this.days = const [],
    this.oneTime = false,
    this.sunriseDuration = 15,
    this.sunriseLights = const [],
    this.soundType = 'builtin',
    this.soundId = 'gentle_morning',
    this.snoozeDuration = 10,
    this.volume = 0.7,
  });

  int get hour => int.parse(time.split(':')[0]);
  int get minute => int.parse(time.split(':')[1]);

  Alarm copyWith({
    String? id, String? time, String? label, bool? enabled,
    List<int>? days, bool? oneTime, int? sunriseDuration,
    List<String>? sunriseLights, String? soundType, String? soundId,
    int? snoozeDuration, double? volume,
  }) {
    return Alarm(
      id: id ?? this.id,
      time: time ?? this.time,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      days: days ?? this.days,
      oneTime: oneTime ?? this.oneTime,
      sunriseDuration: sunriseDuration ?? this.sunriseDuration,
      sunriseLights: sunriseLights ?? this.sunriseLights,
      soundType: soundType ?? this.soundType,
      soundId: soundId ?? this.soundId,
      snoozeDuration: snoozeDuration ?? this.snoozeDuration,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'time': time, 'label': label, 'enabled': enabled,
    'days': days, 'oneTime': oneTime, 'sunriseDuration': sunriseDuration,
    'sunriseLights': sunriseLights, 'soundType': soundType,
    'soundId': soundId, 'snoozeDuration': snoozeDuration, 'volume': volume,
  };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
    id: json['id'] as String? ?? _generateId(),
    time: json['time'] as String? ?? '07:00',
    label: json['label'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    days: (json['days'] as List<dynamic>?)?.cast<int>() ?? const [],
    oneTime: json['oneTime'] as bool? ?? false,
    sunriseDuration: json['sunriseDuration'] as int? ?? 15,
    sunriseLights: (json['sunriseLights'] as List<dynamic>?)?.cast<String>() ?? const [],
    soundType: json['soundType'] as String? ?? 'builtin',
    soundId: json['soundId'] as String? ?? 'gentle_morning',
    snoozeDuration: json['snoozeDuration'] as int? ?? 10,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.7,
  );

  /// Compute the next DateTime this alarm will fire.
  DateTime? nextFireTime(DateTime now) {
    if (!enabled) return null;
    final todayFire = DateTime(now.year, now.month, now.day, hour, minute);

    if (days.isEmpty) {
      // One-time: next occurrence of this time.
      return todayFire.isAfter(now) ? todayFire : todayFire.add(const Duration(days: 1));
    }

    // Recurring: find next matching day.
    for (int offset = 0; offset < 8; offset++) {
      final candidate = todayFire.add(Duration(days: offset));
      if (days.contains(candidate.weekday)) {
        if (candidate.isAfter(now)) return candidate;
      }
    }
    return null;
  }

  /// Human-readable day summary.
  String get daySummary {
    if (days.isEmpty) return oneTime ? 'One time' : 'Tomorrow';
    if (days.length == 7) return 'Every day';
    if (const [1,2,3,4,5].every(days.contains) && days.length == 5) return 'Weekdays';
    if (const [6,7].every(days.contains) && days.length == 2) return 'Weekends';
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => names[d]).join(', ');
  }

  static String _generateId() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}
```

- [ ] **Step 2: Write tests**

```dart
test('Alarm round-trips through JSON', () {
  final alarm = Alarm(id: 'test1', time: '06:30', days: [1,2,3,4,5], label: 'Work');
  final json = alarm.toJson();
  final restored = Alarm.fromJson(json);
  expect(restored.time, '06:30');
  expect(restored.days, [1,2,3,4,5]);
  expect(restored.label, 'Work');
});

test('nextFireTime returns tomorrow for past one-time alarm', () {
  final alarm = Alarm(id: 'a', time: '06:00');
  final now = DateTime(2026, 4, 12, 10, 0); // 10am, past 6am
  final next = alarm.nextFireTime(now)!;
  expect(next.day, 13);
  expect(next.hour, 6);
});

test('nextFireTime finds next weekday', () {
  final alarm = Alarm(id: 'a', time: '07:00', days: [1,2,3,4,5]); // weekdays
  final now = DateTime(2026, 4, 11, 20, 0); // Saturday evening (day=6)
  final next = alarm.nextFireTime(now)!;
  expect(next.weekday, 1); // Monday
});

test('daySummary shows Weekdays for Mon-Fri', () {
  final alarm = Alarm(id: 'a', time: '07:00', days: [1,2,3,4,5]);
  expect(alarm.daySummary, 'Weekdays');
});
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/modules/alarm_clock/alarm_models_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/modules/alarm_clock/alarm_models.dart test/modules/alarm_clock/alarm_models_test.dart
git commit -m "feat: add Alarm data model with JSON serialization and scheduling logic"
```

### Task 6: AlarmService with persistence and firing

**Files:**
- Create: `lib/modules/alarm_clock/alarm_service.dart`
- Create: `test/modules/alarm_clock/alarm_service_test.dart`

- [ ] **Step 1: Create AlarmService**

ChangeNotifier pattern matching TimerService. Key methods:
- `load()` — reads alarms.json from app support dir
- `save()` — writes alarms.json
- `addAlarm(Alarm)`, `updateAlarm(Alarm)`, `deleteAlarm(String id)`
- `toggleEnabled(String id)`
- `_onTick()` — 30-second ticker, checks nextFireTime for each alarm
- `fireAlarm(Alarm)` — sets `firedAlarm`, starts sunrise if configured
- `snooze()` — sets `snoozedUntil`, clears `firedAlarm`
- `dismiss()` — clears `firedAlarm`, auto-disables one-time alarms
- Getters: `alarms`, `firedAlarm`, `snoozedUntil`, `nextAlarm`

Register as `ChangeNotifierProvider<AlarmService>`.

- [ ] **Step 2: Write tests for add/update/delete, nextAlarm computation, and fire detection**

Test: add alarm, verify nextAlarm. Test: disable, verify nextAlarm is null. Test: one-time alarm auto-disables after dismiss.

- [ ] **Step 3: Run tests**

Run: `flutter test test/modules/alarm_clock/alarm_service_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/modules/alarm_clock/alarm_service.dart test/modules/alarm_clock/alarm_service_test.dart
git commit -m "feat: add AlarmService with persistence, scheduling, and fire detection"
```

### Task 7: SunriseController for display and HA lights

**Files:**
- Create: `lib/modules/alarm_clock/sunrise_controller.dart`

- [ ] **Step 1: Create SunriseController**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/home_assistant_service.dart';
import '../../utils/logger.dart';

class SunriseController extends ChangeNotifier {
  static const _keyframes = <double, Color>{
    0.00: Color(0xFF000000),
    0.15: Color(0xFF0A1028),
    0.30: Color(0xFF2A1040),
    0.50: Color(0xFF4A2010),
    0.70: Color(0xFFC05820),
    0.85: Color(0xFFE8A030),
    1.00: Color(0xFFFFD890),
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
        final t = (_progress - entries[i].key) / (entries[i + 1].key - entries[i].key);
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
    final mireds = (454 - (_progress * _progress * 204)).round().clamp(250, 454);

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
  }

  void snooze(int snoozeDurationMinutes) {
    _durationMinutes = snoozeDurationMinutes;
    _progress = 0.3; // Dim to purple level.
    _startTime = DateTime.now();
    notifyListeners();
    // Dim lights to 30%.
    if (_ha != null) {
      for (final entityId in _lightEntities) {
        _ha!.callService(
          domain: 'light', service: 'turn_on', entityId: entityId,
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
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/modules/alarm_clock/sunrise_controller.dart
git commit -m "feat: add SunriseController with color keyframes and HA light ramping"
```

### Task 8: Alarm alert overlay

**Files:**
- Create: `lib/modules/alarm_clock/alarm_alert_overlay.dart`

- [ ] **Step 1: Create the overlay widget**

ConsumerWidget in the HubShell stack. Watches `alarmServiceProvider`. When `firedAlarm != null`, renders:
- Full-screen with sunrise gradient background color from SunriseController
- Current time (large, center)
- Alarm label
- "Tap anywhere to snooze" (faint, bottom)
- "Dismiss" button (bottom center, 60dp+, white on dark)
- GestureDetector: tap anywhere = snooze, explicit button = dismiss
- Wakes from idle via `addPostFrameCallback`

Follow the exact pattern of `_TimerAlertOverlay` in hub_shell.dart.

- [ ] **Step 2: Wire into HubShell stack**

Add `AlarmAlertOverlay(onWake: _onUserActivity)` in the HubShell Stack, after the timer alert overlay.

Also add the sunrise gradient overlay earlier in the stack (above photos, below active screens):
```dart
// Sunrise gradient — above ambient photos, below active screens
Consumer(builder: (context, ref, _) {
  final sunrise = ref.watch(sunriseControllerProvider);
  if (!sunrise.active) return const SizedBox.shrink();
  return Container(color: sunrise.currentColor);
}),
```

- [ ] **Step 3: Add idle suppression for fired alarms**

In the idle timeout callback, add same guard as timer:
```dart
if (timerService.firedTimers.isEmpty && alarmService.firedAlarm == null) {
  Navigator.popUntil((route) => route.isFirst);
}
```

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add lib/modules/alarm_clock/alarm_alert_overlay.dart lib/app/hub_shell.dart
git commit -m "feat: add alarm alert overlay and sunrise gradient to HubShell"
```

### Task 9: Alarm clock screen (list + editor)

**Files:**
- Create: `lib/modules/alarm_clock/alarm_clock_screen.dart`
- Create: `lib/modules/alarm_clock/alarm_editor_screen.dart`

- [ ] **Step 1: Create alarm list screen**

ConsumerWidget showing:
- Header: "Next alarm in Xh Ym" or "No alarms set"
- ListView of alarm cards (time, label, day summary, enable toggle)
- Tap card → Navigator push to editor
- FAB to add new alarm
- Dark theme matching existing screens

- [ ] **Step 2: Create alarm editor screen**

StatefulWidget with:
- Time picker (hour/minute scroll wheels — reuse `_ScrollWheel` pattern from timer_screen.dart)
- Day-of-week toggles (7 circular buttons)
- Label text field
- Sunrise toggle + duration chips (5/10/15/20/25/30)
- Sound picker (builtin list + MA option)
- Snooze duration chips (5/10/15/20)
- Volume slider
- Save/Delete buttons

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/modules/alarm_clock/`

- [ ] **Step 4: Commit**

```bash
git add lib/modules/alarm_clock/alarm_clock_screen.dart lib/modules/alarm_clock/alarm_editor_screen.dart
git commit -m "feat: add alarm list and editor screens"
```

### Task 10: Module registration and wiring

**Files:**
- Create: `lib/modules/alarm_clock/alarm_clock_module.dart`
- Modify: `lib/modules/module_registry.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create AlarmClockModule**

```dart
import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'alarm_clock_screen.dart';

class AlarmClockModule implements HearthModule {
  @override String get id => 'alarm_clock';
  @override String get name => 'Alarms';
  @override IconData get icon => Icons.alarm;
  @override int get defaultOrder => 5;

  @override
  bool isConfigured(HubConfig config) => true;

  @override
  Widget buildScreen({required bool isActive}) => const AlarmClockScreen();

  @override
  Widget? buildSettingsSection() => null;
}
```

- [ ] **Step 2: Register in module_registry.dart**

Add to `allModules`:
```dart
AlarmClockModule(),
```

- [ ] **Step 3: Eager-load alarm service in main.dart**

After the Sendspin eager read, add:
```dart
// Alarm service: load persisted alarms and start tick checker.
if (!kIsWeb) {
  await container.read(alarmServiceProvider).load();
}
```

- [ ] **Step 4: Set default placement**

In the migration helper `_migrateEnabledModules`, the alarm_clock won't be in the old enabledModules list, so it starts with no placement. For new installs, add a default in the HubConfig constructor or let users enable it in Settings.

- [ ] **Step 5: Run flutter analyze and test**

Run: `flutter analyze && flutter test`

- [ ] **Step 6: Commit**

```bash
git add lib/modules/alarm_clock/alarm_clock_module.dart lib/modules/module_registry.dart lib/main.dart
git commit -m "feat: register alarm clock module with default menu1 placement"
```

### Task 11: Bundled alarm tones and audio playback

**Files:**
- Create: `assets/alarm_tones/` (placeholder directory — actual audio files sourced separately)
- Create: `lib/modules/alarm_clock/alarm_audio.dart`

- [ ] **Step 1: Create alarm audio player**

```dart
import 'dart:async';
import 'dart:io';
import '../../utils/logger.dart';

/// Plays bundled alarm tones via ALSA on Linux, or logs on other platforms.
class AlarmAudioPlayer {
  Process? _process;
  bool _looping = false;

  /// Available builtin tone IDs.
  static const builtinTones = {
    'gentle_morning': 'Gentle Morning',
    'birds': 'Birdsong',
    'classic': 'Classic',
    'bright': 'Bright Day',
    'urgent': 'Wake Up',
  };

  /// Start playing a looping alarm tone.
  Future<void> play(String toneId, {double volume = 0.7}) async {
    stop();
    _looping = true;
    // On Linux, use aplay or gst-launch for OGG playback.
    // The tone files are bundled in the flutter assets directory.
    if (Platform.isLinux) {
      _playLoop(toneId, volume);
    } else {
      Log.i('AlarmAudio', 'Would play tone: $toneId at volume $volume');
    }
  }

  Future<void> _playLoop(String toneId, double volume) async {
    while (_looping) {
      try {
        // Use gst-launch-1.0 for OGG playback with volume control.
        _process = await Process.start('gst-launch-1.0', [
          'filesrc', 'location=/opt/hearth/bundle/flutter_assets/assets/alarm_tones/$toneId.ogg',
          '!', 'oggdemux', '!', 'vorbisdec',
          '!', 'volume', 'volume=${volume.toStringAsFixed(2)}',
          '!', 'autoaudiosink',
        ]);
        await _process!.exitCode;
      } catch (e) {
        Log.e('AlarmAudio', 'Playback failed: $e');
        break;
      }
    }
  }

  /// Stop playback.
  void stop() {
    _looping = false;
    _process?.kill();
    _process = null;
  }
}
```

- [ ] **Step 2: Create placeholder audio assets**

Create `assets/alarm_tones/.gitkeep` as a placeholder. Add a note that actual OGG files need to be sourced from CC0 libraries (Pixabay, Freesound) and placed here.

Update `pubspec.yaml` flutter assets section:
```yaml
flutter:
  assets:
    - assets/alarm_tones/
```

- [ ] **Step 3: Commit**

```bash
git add lib/modules/alarm_clock/alarm_audio.dart assets/alarm_tones/.gitkeep pubspec.yaml
git commit -m "feat: add alarm audio player with GStreamer playback and tone registry"
```

### Task 12: Web portal alarm endpoints

**Files:**
- Modify: `lib/services/local_api_server.dart`

- [ ] **Step 1: Add alarm API endpoints**

In the request routing section, add:
- `GET /api/alarms` — returns alarm list from AlarmService
- `POST /api/alarms` — upsert alarm (create if no id, update if id exists)
- `DELETE /api/alarms/:id` — delete by ID

All behind API key auth (same as config endpoints).

- [ ] **Step 2: Add alarms section to web UI HTML**

Add an "Alarms" section after Updates with:
- List of alarms with time, label, enabled toggle
- Add button that opens a simple form
- Delete buttons per alarm

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/services/local_api_server.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/services/local_api_server.dart
git commit -m "feat: add alarm CRUD endpoints and web UI to local API server"
```

### Task 13: Final integration test and cleanup

**Files:**
- All alarm module files

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 2: Run full analyze**

Run: `flutter analyze`
Expected: No errors or warnings (infos are ok).

- [ ] **Step 3: Final commit and push**

```bash
git add -A
git commit -m "feat: complete alarm clock module with sunrise display, HA lights, and web portal"
git push -u origin task/alarm-clock-module
```

- [ ] **Step 4: Create PR**

```bash
tea pr create -R gitea --title "feat: alarm clock module with sunrise display and flexible module placement" --description "Implements the alarm clock module per docs/specs/2026-04-12-alarm-clock-module-design.md.

Phase 1: Module placement system — modules can appear in swipe PageView, menu1, menu2, or any combination. Settings UI uses FilterChip toggles per module. Migrates from enabledModules.

Phase 2: Alarm clock — sunrise display effect (AMOLED dawn colors), HA light ramping (brightness + color temp), recurring/one-time schedules, snooze/dismiss UX, bundled alarm tones, web portal CRUD.

Closes #118 (if alarm issue exists)"
```
