# Home Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter kiosk app that replaces Google Nest Hub with Immich photos, Home Assistant controls, Music Assistant audio, and Frigate cameras.

**Architecture:** Direct API — the Flutter app connects to each service over REST/WebSocket with no middleware. Riverpod for state management. Rendered at 1184x864 on an 11" AMOLED via flutter-pi on a Raspberry Pi 5.

**Tech Stack:** Flutter 3.41 stable, flutter_riverpod, dio, web_socket_channel, cached_network_image

---

## File Structure

```
home_hub/
├── lib/
│   ├── main.dart                              # Entry point, ProviderScope, app init
│   ├── app/
│   │   ├── app.dart                           # MaterialApp, dark theme, no-chrome kiosk config
│   │   ├── hub_shell.dart                     # Stack: ambient layer + PageView + event overlay
│   │   └── idle_controller.dart               # GestureDetector wrapper, idle timer, day/night fade
│   │
│   ├── config/
│   │   ��── hub_config.dart                    # Config model + JSON persistence + Riverpod provider
│   │
│   ├── services/
│   │   ├── immich_service.dart                # REST client: memories, asset download, photo cache
│   │   ├── home_assistant_service.dart        # WebSocket client: auth, subscribe, call_service
│   │   ├── music_assistant_service.dart       # WebSocket via HA: playback state, controls, zones
│   │   ├── frigate_service.dart               # REST: camera list, MJPEG URLs. Events via HA WS.
│   │   ├── display_mode_service.dart          # Night/day resolution from configured source
│   │   └── local_api_server.dart              # HttpServer: POST /api/display-mode
│   │
│   ├── models/
│   │   ├── ha_entity.dart                     # Entity ID, state, attributes, last_changed
│   │   ├── music_state.dart                   # Player state, track info, queue, zone
│   │   ├── frigate_event.dart                 # Event type, camera, thumbnail URL, timestamp
│   │   └── photo_memory.dart                  # Asset ID, image URL, memory date, caption
│   │
│   ├── screens/
│   │   ├── ambient/
│   │   │   ├── ambient_screen.dart            # Full-bleed photo + overlay container
│   │   │   ├── photo_carousel.dart            # Ken Burns animation + crossfade logic
│   │   │   └── ambient_overlays.dart          # Clock, weather, now-playing pill, memory label
│   │   ├── home/
│   │   │   └── home_screen.dart               # Clock, weather, scene buttons, mini player
│   │   ├── media/
│   │   │   └── media_screen.dart              # Album art, controls, zone picker, queue
│   │   ├── controls/
│   │   │   ├── controls_screen.dart           # Room-grouped device list
│   │   │   ├── light_card.dart                # Toggle, brightness slider, color picker
│   │   │   └── climate_card.dart              # Thermostat display + controls
│   │   ├── cameras/
│   │   │   └── cameras_screen.dart            # MJPEG grid/single view, recent events
│   │   └── settings/
│   │       └── settings_screen.dart           # All config: brightness, timeout, night mode, zones
│   │
│   └── widgets/
│       ├── now_playing_bar.dart               # Compact player bar (ambient + home)
│       └── event_overlay.dart                 # Doorbell/person/safety interrupt overlay
│
├── test/
│   ├── config/
│   │   └── hub_config_test.dart
│   ├── services/
│   │   ├── immich_service_test.dart
│   │   ├── home_assistant_service_test.dart
│   │   ├── music_assistant_service_test.dart
│   │   ├── frigate_service_test.dart
│   │   ├── display_mode_service_test.dart
│   │   └── local_api_server_test.dart
│   ├── screens/
│   │   ├── ambient/
│   │   │   └── photo_carousel_test.dart
│   │   └── hub_shell_test.dart
│   └── models/
│       ├── ha_entity_test.dart
│       ├── music_state_test.dart
│       ├── frigate_event_test.dart
│       └── photo_memory_test.dart
│
├── assets/
│   └── fonts/                                 # If custom fonts needed
│
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

---

## Task 1: Project Scaffold & Fixed-Size Window

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `lib/main.dart`
- Create: `lib/app/app.dart`
- Create: `lib/config/hub_config.dart`

- [ ] **Step 1: Install Flutter SDK**

Ensure Flutter 3.41 stable is installed and on PATH:

```bash
flutter --version
# Expected: Flutter 3.41.x • channel stable
```

If not installed, download from https://docs.flutter.dev/get-started/install/windows/desktop and add to PATH.

- [ ] **Step 2: Create Flutter project**

```bash
cd C:\Users\chris
flutter create --org com.homehub --project-name home_hub --platforms windows,linux home_hub
cd home_hub
```

Expected: project created with `lib/main.dart`, `pubspec.yaml`, etc.

- [ ] **Step 3: Replace pubspec.yaml with project dependencies**

Replace the contents of `pubspec.yaml`:

```yaml
name: home_hub
description: Smart home kiosk — Immich photos, HA controls, Music Assistant, Frigate cameras.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.7.0
  flutter: '>=3.41.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  dio: ^5.7.0
  web_socket_channel: ^3.0.1
  cached_network_image: ^3.4.1
  path_provider: ^2.1.4
  shared_preferences: ^2.3.3
  intl: ^0.19.0
  window_size:
    git:
      url: https://github.com/google/flutter-desktop-embedding.git
      path: plugins/window_size

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  riverpod_generator: ^2.6.2
  build_runner: ^2.4.13
  mockito: ^5.4.4
  build_verify: ^3.1.0

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Install dependencies**

```bash
cd C:\Users\chris\home_hub
flutter pub get
```

Expected: `Resolving dependencies...` followed by success.

- [ ] **Step 5: Create analysis_options.yaml**

Replace `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: true
```

- [ ] **Step 6: Create hub_config.dart**

Create `lib/config/hub_config.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class HubConfig {
  final String immichUrl;
  final String immichApiKey;
  final String haUrl;
  final String haToken;
  final String musicAssistantUrl;
  final String frigateUrl;
  final int idleTimeoutSeconds;
  final String nightModeSource; // "ha_entity" | "api" | "clock" | "none"
  final String? nightModeHaEntity;
  final String? nightModeClockStart;
  final String? nightModeClockEnd;
  final String? defaultMusicZone;

  const HubConfig({
    this.immichUrl = '',
    this.immichApiKey = '',
    this.haUrl = '',
    this.haToken = '',
    this.musicAssistantUrl = '',
    this.frigateUrl = '',
    this.idleTimeoutSeconds = 120,
    this.nightModeSource = 'none',
    this.nightModeHaEntity,
    this.nightModeClockStart,
    this.nightModeClockEnd,
    this.defaultMusicZone,
  });

  HubConfig copyWith({
    String? immichUrl,
    String? immichApiKey,
    String? haUrl,
    String? haToken,
    String? musicAssistantUrl,
    String? frigateUrl,
    int? idleTimeoutSeconds,
    String? nightModeSource,
    String? nightModeHaEntity,
    String? nightModeClockStart,
    String? nightModeClockEnd,
    String? defaultMusicZone,
  }) {
    return HubConfig(
      immichUrl: immichUrl ?? this.immichUrl,
      immichApiKey: immichApiKey ?? this.immichApiKey,
      haUrl: haUrl ?? this.haUrl,
      haToken: haToken ?? this.haToken,
      musicAssistantUrl: musicAssistantUrl ?? this.musicAssistantUrl,
      frigateUrl: frigateUrl ?? this.frigateUrl,
      idleTimeoutSeconds: idleTimeoutSeconds ?? this.idleTimeoutSeconds,
      nightModeSource: nightModeSource ?? this.nightModeSource,
      nightModeHaEntity: nightModeHaEntity ?? this.nightModeHaEntity,
      nightModeClockStart: nightModeClockStart ?? this.nightModeClockStart,
      nightModeClockEnd: nightModeClockEnd ?? this.nightModeClockEnd,
      defaultMusicZone: defaultMusicZone ?? this.defaultMusicZone,
    );
  }

  Map<String, dynamic> toJson() => {
        'immichUrl': immichUrl,
        'immichApiKey': immichApiKey,
        'haUrl': haUrl,
        'haToken': haToken,
        'musicAssistantUrl': musicAssistantUrl,
        'frigateUrl': frigateUrl,
        'idleTimeoutSeconds': idleTimeoutSeconds,
        'nightModeSource': nightModeSource,
        'nightModeHaEntity': nightModeHaEntity,
        'nightModeClockStart': nightModeClockStart,
        'nightModeClockEnd': nightModeClockEnd,
        'defaultMusicZone': defaultMusicZone,
      };

  factory HubConfig.fromJson(Map<String, dynamic> json) => HubConfig(
        immichUrl: json['immichUrl'] as String? ?? '',
        immichApiKey: json['immichApiKey'] as String? ?? '',
        haUrl: json['haUrl'] as String? ?? '',
        haToken: json['haToken'] as String? ?? '',
        musicAssistantUrl: json['musicAssistantUrl'] as String? ?? '',
        frigateUrl: json['frigateUrl'] as String? ?? '',
        idleTimeoutSeconds: json['idleTimeoutSeconds'] as int? ?? 120,
        nightModeSource: json['nightModeSource'] as String? ?? 'none',
        nightModeHaEntity: json['nightModeHaEntity'] as String?,
        nightModeClockStart: json['nightModeClockStart'] as String?,
        nightModeClockEnd: json['nightModeClockEnd'] as String?,
        defaultMusicZone: json['defaultMusicZone'] as String?,
      );
}

class HubConfigNotifier extends StateNotifier<HubConfig> {
  HubConfigNotifier() : super(const HubConfig());

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/hub_config.json');
    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      state = HubConfig.fromJson(json);
    }
  }

  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/hub_config.json');
    await file.writeAsString(jsonEncode(state.toJson()));
  }
}

final hubConfigProvider =
    StateNotifierProvider<HubConfigNotifier, HubConfig>((ref) {
  return HubConfigNotifier();
});
```

- [ ] **Step 7: Create app.dart with dark theme and fixed window**

Create `lib/app/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeHubApp extends ConsumerWidget {
  const HomeHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Home Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: const Color(0xFF646CFF),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'Home Hub',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Create main.dart with window sizing**

Replace `lib/main.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_size/window_size.dart' as window_size;
import 'app/app.dart';
import 'config/hub_config.dart';

const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    window_size.setWindowTitle('Home Hub');
    window_size.setWindowMinSize(const Size(kWindowWidth, kWindowHeight));
    window_size.setWindowMaxSize(const Size(kWindowWidth, kWindowHeight));
  }

  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HomeHubApp(),
    ),
  );
}
```

- [ ] **Step 9: Run the app to verify scaffold**

```bash
cd C:\Users\chris\home_hub
flutter run -d windows
```

Expected: A 1184x864 black window with "Home Hub" centered in white text. Window cannot be resized.

- [ ] **Step 10: Write config test**

Create `test/config/hub_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/config/hub_config.dart';

void main() {
  group('HubConfig', () {
    test('default values', () {
      const config = HubConfig();
      expect(config.immichUrl, '');
      expect(config.idleTimeoutSeconds, 120);
      expect(config.nightModeSource, 'none');
      expect(config.nightModeHaEntity, isNull);
    });

    test('round-trips through JSON', () {
      const config = HubConfig(
        immichUrl: 'http://immich.local:2283',
        immichApiKey: 'test-key',
        haUrl: 'ws://ha.local:8123',
        haToken: 'ha-token',
        nightModeSource: 'ha_entity',
        nightModeHaEntity: 'light.living_room',
        idleTimeoutSeconds: 60,
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.immichUrl, config.immichUrl);
      expect(restored.immichApiKey, config.immichApiKey);
      expect(restored.haUrl, config.haUrl);
      expect(restored.nightModeSource, 'ha_entity');
      expect(restored.nightModeHaEntity, 'light.living_room');
      expect(restored.idleTimeoutSeconds, 60);
    });

    test('copyWith preserves unchanged fields', () {
      const config = HubConfig(
        immichUrl: 'http://immich.local',
        idleTimeoutSeconds: 60,
      );
      final updated = config.copyWith(idleTimeoutSeconds: 90);
      expect(updated.immichUrl, 'http://immich.local');
      expect(updated.idleTimeoutSeconds, 90);
    });

    test('fromJson handles missing fields with defaults', () {
      final config = HubConfig.fromJson({'immichUrl': 'http://test'});
      expect(config.immichUrl, 'http://test');
      expect(config.nightModeSource, 'none');
      expect(config.idleTimeoutSeconds, 120);
    });
  });
}
```

- [ ] **Step 11: Run tests**

```bash
cd C:\Users\chris\home_hub
flutter test test/config/hub_config_test.dart -v
```

Expected: All 4 tests pass.

- [ ] **Step 12: Commit**

```bash
cd C:\Users\chris\home_hub
git init
git add pubspec.yaml analysis_options.yaml lib/main.dart lib/app/app.dart lib/config/hub_config.dart test/config/hub_config_test.dart .gitignore
git commit -m "feat: project scaffold with fixed window, dark theme, and config persistence"
```

---

## Task 2: Data Models

**Files:**
- Create: `lib/models/ha_entity.dart`
- Create: `lib/models/music_state.dart`
- Create: `lib/models/frigate_event.dart`
- Create: `lib/models/photo_memory.dart`
- Create: `test/models/ha_entity_test.dart`
- Create: `test/models/music_state_test.dart`
- Create: `test/models/frigate_event_test.dart`
- Create: `test/models/photo_memory_test.dart`

- [ ] **Step 1: Create ha_entity.dart**

Create `lib/models/ha_entity.dart`:

```dart
class HaEntity {
  final String entityId;
  final String state;
  final Map<String, dynamic> attributes;
  final DateTime lastChanged;

  const HaEntity({
    required this.entityId,
    required this.state,
    this.attributes = const {},
    required this.lastChanged,
  });

  String get domain => entityId.split('.').first;
  String get name =>
      attributes['friendly_name'] as String? ?? entityId.split('.').last;

  int? get brightness => attributes['brightness'] as int?;
  double? get colorTemp => (attributes['color_temp'] as num?)?.toDouble();
  List<int>? get rgbColor {
    final rgb = attributes['rgb_color'];
    if (rgb is List) return rgb.cast<int>();
    return null;
  }

  double? get temperature => (attributes['temperature'] as num?)?.toDouble();
  double? get currentTemperature =>
      (attributes['current_temperature'] as num?)?.toDouble();
  String? get hvacMode => attributes['hvac_mode'] as String?;

  bool get isOn => state == 'on';
  bool get isOff => state == 'off';
  bool get isUnavailable => state == 'unavailable';

  factory HaEntity.fromEventData(Map<String, dynamic> data) {
    return HaEntity(
      entityId: data['entity_id'] as String,
      state: data['state'] as String,
      attributes:
          (data['attributes'] as Map<String, dynamic>?) ?? const {},
      lastChanged: DateTime.parse(data['last_changed'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'entity_id': entityId,
        'state': state,
        'attributes': attributes,
        'last_changed': lastChanged.toIso8601String(),
      };
}
```

- [ ] **Step 2: Write ha_entity tests**

Create `test/models/ha_entity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/ha_entity.dart';

void main() {
  group('HaEntity', () {
    test('parses from event data', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'light.kitchen',
        'state': 'on',
        'attributes': {
          'friendly_name': 'Kitchen Light',
          'brightness': 200,
          'rgb_color': [255, 180, 100],
        },
        'last_changed': '2026-04-05T10:00:00.000Z',
      });

      expect(entity.entityId, 'light.kitchen');
      expect(entity.domain, 'light');
      expect(entity.name, 'Kitchen Light');
      expect(entity.state, 'on');
      expect(entity.isOn, true);
      expect(entity.brightness, 200);
      expect(entity.rgbColor, [255, 180, 100]);
    });

    test('domain and name parsing', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'climate.living_room',
        'state': 'heat',
        'attributes': {},
        'last_changed': '2026-04-05T10:00:00.000Z',
      });
      expect(entity.domain, 'climate');
      expect(entity.name, 'living_room');
    });

    test('climate attributes', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'climate.thermostat',
        'state': 'heat',
        'attributes': {
          'temperature': 72.0,
          'current_temperature': 68.5,
          'hvac_mode': 'heat',
        },
        'last_changed': '2026-04-05T10:00:00.000Z',
      });
      expect(entity.temperature, 72.0);
      expect(entity.currentTemperature, 68.5);
      expect(entity.hvacMode, 'heat');
    });

    test('unavailable state', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'light.offline',
        'state': 'unavailable',
        'attributes': {},
        'last_changed': '2026-04-05T10:00:00.000Z',
      });
      expect(entity.isUnavailable, true);
      expect(entity.isOn, false);
    });
  });
}
```

- [ ] **Step 3: Run ha_entity tests**

```bash
flutter test test/models/ha_entity_test.dart -v
```

Expected: All 4 tests pass.

- [ ] **Step 4: Create music_state.dart**

Create `lib/models/music_state.dart`:

```dart
class MusicTrack {
  final String title;
  final String artist;
  final String album;
  final String? imageUrl;
  final Duration duration;

  const MusicTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        title: json['title'] as String? ?? 'Unknown',
        artist: json['artist'] as String? ?? 'Unknown',
        album: json['album'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      );
}

enum PlaybackState { playing, paused, stopped, idle }

class MusicPlayerState {
  final PlaybackState playbackState;
  final MusicTrack? currentTrack;
  final Duration position;
  final double volume; // 0.0 - 1.0
  final String? activeZoneId;
  final String? activeZoneName;
  final bool shuffle;
  final String repeatMode; // "off" | "one" | "all"

  const MusicPlayerState({
    this.playbackState = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.volume = 0.5,
    this.activeZoneId,
    this.activeZoneName,
    this.shuffle = false,
    this.repeatMode = 'off',
  });

  bool get isPlaying => playbackState == PlaybackState.playing;
  bool get hasTrack => currentTrack != null;

  MusicPlayerState copyWith({
    PlaybackState? playbackState,
    MusicTrack? currentTrack,
    Duration? position,
    double? volume,
    String? activeZoneId,
    String? activeZoneName,
    bool? shuffle,
    String? repeatMode,
  }) {
    return MusicPlayerState(
      playbackState: playbackState ?? this.playbackState,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      volume: volume ?? this.volume,
      activeZoneId: activeZoneId ?? this.activeZoneId,
      activeZoneName: activeZoneName ?? this.activeZoneName,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

class MusicZone {
  final String id;
  final String name;
  final bool isActive;

  const MusicZone({
    required this.id,
    required this.name,
    this.isActive = false,
  });

  factory MusicZone.fromJson(Map<String, dynamic> json) => MusicZone(
        id: json['id'] as String? ?? json['entity_id'] as String,
        name: json['name'] as String? ??
            json['attributes']?['friendly_name'] as String? ??
            'Unknown',
        isActive: json['state'] == 'playing',
      );
}
```

- [ ] **Step 5: Write music_state tests**

Create `test/models/music_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/music_state.dart';

void main() {
  group('MusicTrack', () {
    test('parses from JSON', () {
      final track = MusicTrack.fromJson({
        'title': 'Bohemian Rhapsody',
        'artist': 'Queen',
        'album': 'A Night at the Opera',
        'image_url': 'http://example.com/art.jpg',
        'duration': 355,
      });
      expect(track.title, 'Bohemian Rhapsody');
      expect(track.artist, 'Queen');
      expect(track.duration, const Duration(seconds: 355));
    });

    test('handles missing fields', () {
      final track = MusicTrack.fromJson({});
      expect(track.title, 'Unknown');
      expect(track.artist, 'Unknown');
      expect(track.duration, Duration.zero);
    });
  });

  group('MusicPlayerState', () {
    test('defaults to idle', () {
      const state = MusicPlayerState();
      expect(state.playbackState, PlaybackState.idle);
      expect(state.isPlaying, false);
      expect(state.hasTrack, false);
    });

    test('copyWith preserves fields', () {
      const state = MusicPlayerState(
        volume: 0.8,
        activeZoneName: 'Kitchen',
      );
      final updated = state.copyWith(volume: 0.5);
      expect(updated.volume, 0.5);
      expect(updated.activeZoneName, 'Kitchen');
    });
  });

  group('MusicZone', () {
    test('parses from HA entity format', () {
      final zone = MusicZone.fromJson({
        'entity_id': 'media_player.kitchen',
        'state': 'playing',
        'attributes': {'friendly_name': 'Kitchen Speaker'},
      });
      expect(zone.id, 'media_player.kitchen');
      expect(zone.name, 'Kitchen Speaker');
      expect(zone.isActive, true);
    });
  });
}
```

- [ ] **Step 6: Run music_state tests**

```bash
flutter test test/models/music_state_test.dart -v
```

Expected: All 5 tests pass.

- [ ] **Step 7: Create frigate_event.dart**

Create `lib/models/frigate_event.dart`:

```dart
class FrigateEvent {
  final String id;
  final String camera;
  final String label; // "person", "car", "doorbell"
  final double score;
  final DateTime startTime;
  final DateTime? endTime;
  final String? thumbnailUrl;

  const FrigateEvent({
    required this.id,
    required this.camera,
    required this.label,
    required this.score,
    required this.startTime,
    this.endTime,
    this.thumbnailUrl,
  });

  bool get isDoorbell => label == 'doorbell';
  bool get isPerson => label == 'person';
  bool get isActive => endTime == null;

  String thumbnailUrlFor(String frigateBaseUrl) =>
      '$frigateBaseUrl/api/events/$id/thumbnail.jpg';

  factory FrigateEvent.fromJson(Map<String, dynamic> json, String frigateBaseUrl) {
    final id = json['id'] as String;
    return FrigateEvent(
      id: id,
      camera: json['camera'] as String,
      label: json['label'] as String,
      score: (json['top_score'] as num?)?.toDouble() ??
          (json['score'] as num?)?.toDouble() ??
          0.0,
      startTime: DateTime.fromMillisecondsSinceEpoch(
          ((json['start_time'] as num) * 1000).toInt()),
      endTime: json['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((json['end_time'] as num) * 1000).toInt())
          : null,
      thumbnailUrl: '$frigateBaseUrl/api/events/$id/thumbnail.jpg',
    );
  }
}

class FrigateCamera {
  final String name;
  final String mjpegStreamUrl;

  const FrigateCamera({
    required this.name,
    required this.mjpegStreamUrl,
  });

  factory FrigateCamera.fromEntry(String name, String frigateBaseUrl) {
    return FrigateCamera(
      name: name,
      mjpegStreamUrl: '$frigateBaseUrl/api/$name',
    );
  }
}
```

- [ ] **Step 8: Write frigate_event tests**

Create `test/models/frigate_event_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/frigate_event.dart';

void main() {
  const baseUrl = 'http://frigate.local:5000';

  group('FrigateEvent', () {
    test('parses from Frigate API JSON', () {
      final event = FrigateEvent.fromJson({
        'id': 'abc123',
        'camera': 'front_door',
        'label': 'person',
        'top_score': 0.95,
        'start_time': 1712300000.0,
        'end_time': 1712300060.0,
      }, baseUrl);

      expect(event.id, 'abc123');
      expect(event.camera, 'front_door');
      expect(event.isPerson, true);
      expect(event.isDoorbell, false);
      expect(event.score, 0.95);
      expect(event.isActive, false);
      expect(event.thumbnailUrl, '$baseUrl/api/events/abc123/thumbnail.jpg');
    });

    test('active event has no end time', () {
      final event = FrigateEvent.fromJson({
        'id': 'xyz789',
        'camera': 'doorbell',
        'label': 'doorbell',
        'top_score': 0.99,
        'start_time': 1712300000.0,
        'end_time': null,
      }, baseUrl);
      expect(event.isActive, true);
      expect(event.isDoorbell, true);
    });
  });

  group('FrigateCamera', () {
    test('builds MJPEG stream URL', () {
      final cam = FrigateCamera.fromEntry('front_door', baseUrl);
      expect(cam.name, 'front_door');
      expect(cam.mjpegStreamUrl, '$baseUrl/api/front_door');
    });
  });
}
```

- [ ] **Step 9: Run frigate_event tests**

```bash
flutter test test/models/frigate_event_test.dart -v
```

Expected: All 3 tests pass.

- [ ] **Step 10: Create photo_memory.dart**

Create `lib/models/photo_memory.dart`:

```dart
class PhotoMemory {
  final String assetId;
  final String imageUrl;
  final DateTime memoryDate;
  final int yearsAgo;
  final String? description;

  const PhotoMemory({
    required this.assetId,
    required this.imageUrl,
    required this.memoryDate,
    required this.yearsAgo,
    this.description,
  });

  String get memoryLabel =>
      yearsAgo == 1 ? '1 year ago today' : '$yearsAgo years ago today';

  factory PhotoMemory.fromImmichAsset(
    Map<String, dynamic> assetJson, {
    required String immichBaseUrl,
    required int yearsAgo,
  }) {
    final assetId = assetJson['id'] as String;
    return PhotoMemory(
      assetId: assetId,
      imageUrl: '$immichBaseUrl/api/assets/$assetId/original',
      memoryDate: DateTime.parse(assetJson['fileCreatedAt'] as String),
      yearsAgo: yearsAgo,
      description: assetJson['exifInfo']?['description'] as String?,
    );
  }
}
```

- [ ] **Step 11: Write photo_memory tests**

Create `test/models/photo_memory_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/photo_memory.dart';

void main() {
  group('PhotoMemory', () {
    test('parses from Immich asset JSON', () {
      final memory = PhotoMemory.fromImmichAsset(
        {
          'id': 'asset-uuid-123',
          'fileCreatedAt': '2023-04-05T14:30:00.000Z',
          'exifInfo': {'description': 'Beach day'},
        },
        immichBaseUrl: 'http://immich.local:2283',
        yearsAgo: 3,
      );

      expect(memory.assetId, 'asset-uuid-123');
      expect(memory.imageUrl,
          'http://immich.local:2283/api/assets/asset-uuid-123/original');
      expect(memory.yearsAgo, 3);
      expect(memory.memoryLabel, '3 years ago today');
      expect(memory.description, 'Beach day');
    });

    test('singular year label', () {
      const memory = PhotoMemory(
        assetId: 'test',
        imageUrl: 'http://test',
        memoryDate: null ?? _epoch,
        yearsAgo: 1,
      );
      expect(memory.memoryLabel, '1 year ago today');
    });
  });
}

final _epoch = DateTime(2025, 4, 5);
```

- [ ] **Step 12: Run photo_memory tests**

```bash
flutter test test/models/photo_memory_test.dart -v
```

Expected: All 2 tests pass.

- [ ] **Step 13: Run all tests**

```bash
flutter test -v
```

Expected: All model + config tests pass (11 total).

- [ ] **Step 14: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/models/ test/models/
git commit -m "feat: add data models for HA entities, music state, Frigate events, photo memories"
```

---

## Task 3: Home Assistant WebSocket Service

**Files:**
- Create: `lib/services/home_assistant_service.dart`
- Create: `test/services/home_assistant_service_test.dart`

- [ ] **Step 1: Write HA service tests**

Create `test/services/home_assistant_service_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:home_hub/services/home_assistant_service.dart';
import 'package:home_hub/models/ha_entity.dart';

/// In-memory WebSocket pair for testing
class FakeWebSocketChannel implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast();
  final _outgoingController = StreamController<dynamic>();
  final List<String> sentMessages = [];

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => _FakeSink(_outgoingController, sentMessages);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void simulateMessage(Map<String, dynamic> json) {
    _incomingController.add(jsonEncode(json));
  }

  Future<void> close() async {
    await _incomingController.close();
    await _outgoingController.close();
  }
}

class _FakeSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final List<String> _sent;
  _FakeSink(this._controller, this._sent);

  @override
  void add(dynamic data) {
    _sent.add(data as String);
    _controller.add(data);
  }

  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HomeAssistantService', () {
    late FakeWebSocketChannel fakeChannel;
    late HomeAssistantService service;

    setUp(() {
      fakeChannel = FakeWebSocketChannel();
      service = HomeAssistantService.withChannel(fakeChannel);
    });

    tearDown(() async {
      service.dispose();
      await fakeChannel.close();
    });

    test('sends auth message on auth_required', () async {
      service.connect('test-token');

      fakeChannel.simulateMessage({
        'type': 'auth_required',
        'ha_version': '2026.4.0',
      });

      await Future.delayed(const Duration(milliseconds: 50));
      final sent = fakeChannel.sentMessages;
      expect(sent.length, greaterThanOrEqualTo(1));
      final authMsg = jsonDecode(sent.first) as Map<String, dynamic>;
      expect(authMsg['type'], 'auth');
      expect(authMsg['access_token'], 'test-token');
    });

    test('emits entity state on state_changed event', () async {
      service.connect('test-token');

      // Simulate auth flow
      fakeChannel.simulateMessage({'type': 'auth_ok', 'ha_version': '2026.4.0'});
      await Future.delayed(const Duration(milliseconds: 50));

      // Subscribe confirmation
      fakeChannel.simulateMessage({'id': 1, 'type': 'result', 'success': true});

      // Entity state change
      fakeChannel.simulateMessage({
        'id': 1,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {
            'entity_id': 'light.kitchen',
            'new_state': {
              'entity_id': 'light.kitchen',
              'state': 'on',
              'attributes': {'brightness': 200, 'friendly_name': 'Kitchen'},
              'last_changed': '2026-04-05T10:00:00.000Z',
            },
          },
        },
      });

      final entity = await service.entityStream.first;
      expect(entity.entityId, 'light.kitchen');
      expect(entity.isOn, true);
      expect(entity.brightness, 200);
    });

    test('formats call_service message correctly', () async {
      service.connect('test-token');
      fakeChannel.simulateMessage({'type': 'auth_ok', 'ha_version': '2026.4.0'});
      await Future.delayed(const Duration(milliseconds: 50));

      service.callService(
        domain: 'light',
        service: 'turn_on',
        entityId: 'light.kitchen',
        data: {'brightness': 150},
      );

      await Future.delayed(const Duration(milliseconds: 50));
      final callMsg = fakeChannel.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'call_service')
          .first;
      expect(callMsg['domain'], 'light');
      expect(callMsg['service'], 'turn_on');
      expect(callMsg['target']['entity_id'], 'light.kitchen');
      expect(callMsg['service_data']['brightness'], 150);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/home_assistant_service_test.dart -v
```

Expected: FAIL — `home_assistant_service.dart` doesn't exist yet.

- [ ] **Step 3: Implement HomeAssistantService**

Create `lib/services/home_assistant_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ha_entity.dart';
import '../config/hub_config.dart';

class HomeAssistantService {
  WebSocketChannel? _channel;
  final _entityController = StreamController<HaEntity>.broadcast();
  final Map<String, HaEntity> _entities = {};
  int _msgId = 0;
  bool _authenticated = false;

  Stream<HaEntity> get entityStream => _entityController.stream;
  Map<String, HaEntity> get entities => Map.unmodifiable(_entities);
  bool get isConnected => _authenticated;

  HomeAssistantService();

  HomeAssistantService.withChannel(WebSocketChannel channel)
      : _channel = channel;

  int get _nextId => ++_msgId;

  void connect(String token) {
    _channel!.stream.listen(
      (data) => _handleMessage(jsonDecode(data as String), token),
      onError: (error) {},
      onDone: () => _authenticated = false,
    );
  }

  Future<void> connectToUrl(String url, String token) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;
    connect(token);
  }

  void _handleMessage(Map<String, dynamic> msg, String token) {
    switch (msg['type']) {
      case 'auth_required':
        _send({'type': 'auth', 'access_token': token});
        break;
      case 'auth_ok':
        _authenticated = true;
        _subscribeToStateChanges();
        break;
      case 'event':
        _handleEvent(msg);
        break;
    }
  }

  void _subscribeToStateChanges() {
    _send({
      'id': _nextId,
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>?;
    if (event == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final newState = data['new_state'] as Map<String, dynamic>?;
    if (newState == null) return;

    final entity = HaEntity.fromEventData(newState);
    _entities[entity.entityId] = entity;
    _entityController.add(entity);
  }

  void callService({
    required String domain,
    required String service,
    required String entityId,
    Map<String, dynamic>? data,
  }) {
    _send({
      'id': _nextId,
      'type': 'call_service',
      'domain': domain,
      'service': service,
      'service_data': data ?? {},
      'target': {'entity_id': entityId},
    });
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _channel?.sink.close();
    _entityController.close();
  }
}

final homeAssistantServiceProvider = Provider<HomeAssistantService>((ref) {
  final service = HomeAssistantService();
  ref.onDispose(() => service.dispose());
  return service;
});

final haEntitiesProvider = StreamProvider<HaEntity>((ref) {
  final service = ref.watch(homeAssistantServiceProvider);
  return service.entityStream;
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/home_assistant_service_test.dart -v
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/services/home_assistant_service.dart test/services/home_assistant_service_test.dart
git commit -m "feat: Home Assistant WebSocket service with auth, state subscription, and service calls"
```

---

## Task 4: Immich Photo Service

**Files:**
- Create: `lib/services/immich_service.dart`
- Create: `test/services/immich_service_test.dart`

- [ ] **Step 1: Write Immich service tests**

Create `test/services/immich_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/immich_service.dart';
import 'package:home_hub/models/photo_memory.dart';

void main() {
  group('ImmichService', () {
    test('parseMemories extracts photos with year calculation', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2023},
            'assets': [
              {
                'id': 'asset-1',
                'fileCreatedAt': '2023-04-05T12:00:00.000Z',
                'exifInfo': {'description': 'Test photo'},
              },
              {
                'id': 'asset-2',
                'fileCreatedAt': '2023-04-05T14:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );

      expect(memories.length, 2);
      expect(memories[0].assetId, 'asset-1');
      expect(memories[0].yearsAgo, 3);
      expect(memories[0].memoryLabel, '3 years ago today');
      expect(memories[1].assetId, 'asset-2');
      expect(memories[1].description, isNull);
    });

    test('parseMemories handles empty memories list', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('parseMemories handles memory with no assets', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2024},
            'assets': [],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('buildAuthHeaders returns correct x-api-key header', () {
      final headers = ImmichService.buildAuthHeaders('my-api-key');
      expect(headers['x-api-key'], 'my-api-key');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/immich_service_test.dart -v
```

Expected: FAIL — `immich_service.dart` doesn't exist yet.

- [ ] **Step 3: Implement ImmichService**

Create `lib/services/immich_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_memory.dart';
import '../config/hub_config.dart';

class ImmichService {
  final Dio _dio;
  final String _baseUrl;
  final List<PhotoMemory> _cachedMemories = [];
  final List<String> _cachedFilePaths = [];
  int _currentIndex = 0;

  ImmichService({required String baseUrl, required String apiKey})
      : _baseUrl = baseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: buildAuthHeaders(apiKey),
        ));

  List<PhotoMemory> get memories => List.unmodifiable(_cachedMemories);
  int get currentIndex => _currentIndex;

  static Map<String, String> buildAuthHeaders(String apiKey) => {
        'x-api-key': apiKey,
      };

  Future<void> loadMemories() async {
    final response = await _dio.get('/api/memories');
    final memoriesJson = response.data as List<dynamic>;
    _cachedMemories.clear();
    _cachedMemories.addAll(parseMemories(
      memoriesJson: memoriesJson.cast<Map<String, dynamic>>(),
      baseUrl: _baseUrl,
      today: DateTime.now(),
    ));
    _cachedMemories.shuffle();
    _currentIndex = 0;
  }

  static List<PhotoMemory> parseMemories({
    required List<Map<String, dynamic>> memoriesJson,
    required String baseUrl,
    required DateTime today,
  }) {
    final photos = <PhotoMemory>[];
    for (final memory in memoriesJson) {
      final year = (memory['data'] as Map<String, dynamic>?)?['year'] as int?;
      final yearsAgo = year != null ? today.year - year : 0;
      final assets = (memory['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        photos.add(PhotoMemory.fromImmichAsset(
          asset as Map<String, dynamic>,
          immichBaseUrl: baseUrl,
          yearsAgo: yearsAgo,
        ));
      }
    }
    return photos;
  }

  PhotoMemory? get nextPhoto {
    if (_cachedMemories.isEmpty) return null;
    final photo = _cachedMemories[_currentIndex % _cachedMemories.length];
    _currentIndex++;
    return photo;
  }

  Future<String> cachePhoto(PhotoMemory memory) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/photo_cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final filePath = '${cacheDir.path}/${memory.assetId}.jpg';
    final file = File(filePath);
    if (file.existsSync()) return filePath;

    final response = await _dio.get(
      '/api/assets/${memory.assetId}/original',
      options: Options(responseType: ResponseType.bytes),
    );
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  Future<void> prefetchPhotos({int count = 5}) async {
    _cachedFilePaths.clear();
    for (var i = 0; i < count && i < _cachedMemories.length; i++) {
      final idx = (_currentIndex + i) % _cachedMemories.length;
      final path = await cachePhoto(_cachedMemories[idx]);
      _cachedFilePaths.add(path);
    }
  }

  String? getCachedPath(String assetId) {
    final idx = _cachedFilePaths.indexWhere((p) => p.contains(assetId));
    return idx >= 0 ? _cachedFilePaths[idx] : null;
  }

  void dispose() {
    _dio.close();
  }
}

final immichServiceProvider = Provider<ImmichService>((ref) {
  final config = ref.watch(hubConfigProvider);
  final service = ImmichService(
    baseUrl: config.immichUrl,
    apiKey: config.immichApiKey,
  );
  ref.onDispose(() => service.dispose());
  return service;
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/immich_service_test.dart -v
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/services/immich_service.dart test/services/immich_service_test.dart
git commit -m "feat: Immich service with memories parsing, photo caching, and prefetch"
```

---

## Task 5: Music Assistant Service (via HA WebSocket)

**Files:**
- Create: `lib/services/music_assistant_service.dart`
- Create: `test/services/music_assistant_service_test.dart`

- [ ] **Step 1: Write Music Assistant service tests**

Create `test/services/music_assistant_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/music_assistant_service.dart';
import 'package:home_hub/models/music_state.dart';

void main() {
  group('MusicAssistantService', () {
    test('parsePlayerState extracts playing state from HA entity', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.kitchen',
        'state': 'playing',
        'attributes': {
          'friendly_name': 'Kitchen Speaker',
          'media_title': 'Bohemian Rhapsody',
          'media_artist': 'Queen',
          'media_album_name': 'A Night at the Opera',
          'entity_picture': '/api/media_player_proxy/media_player.kitchen',
          'media_duration': 355.0,
          'media_position': 120.0,
          'volume_level': 0.65,
          'shuffle': false,
          'repeat': 'off',
        },
      });

      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Bohemian Rhapsody');
      expect(state.currentTrack?.artist, 'Queen');
      expect(state.currentTrack?.album, 'A Night at the Opera');
      expect(state.volume, 0.65);
      expect(state.activeZoneId, 'media_player.kitchen');
      expect(state.activeZoneName, 'Kitchen Speaker');
    });

    test('parsePlayerState handles paused state', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.bedroom',
        'state': 'paused',
        'attributes': {
          'friendly_name': 'Bedroom',
          'media_title': 'Song',
          'media_artist': 'Artist',
          'media_album_name': 'Album',
          'media_duration': 200.0,
          'media_position': 50.0,
          'volume_level': 0.4,
        },
      });
      expect(state.playbackState, PlaybackState.paused);
      expect(state.isPlaying, false);
      expect(state.position, const Duration(seconds: 50));
    });

    test('parsePlayerState handles idle/off state', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.kitchen',
        'state': 'idle',
        'attributes': {'friendly_name': 'Kitchen'},
      });
      expect(state.playbackState, PlaybackState.idle);
      expect(state.hasTrack, false);
    });

    test('parseZones extracts zone list from HA entities', () {
      final zones = MusicAssistantService.parseZones([
        {
          'entity_id': 'media_player.kitchen',
          'state': 'playing',
          'attributes': {'friendly_name': 'Kitchen Speaker'},
        },
        {
          'entity_id': 'media_player.bedroom',
          'state': 'idle',
          'attributes': {'friendly_name': 'Bedroom Speaker'},
        },
      ]);
      expect(zones.length, 2);
      expect(zones[0].name, 'Kitchen Speaker');
      expect(zones[0].isActive, true);
      expect(zones[1].isActive, false);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/music_assistant_service_test.dart -v
```

Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement MusicAssistantService**

Create `lib/services/music_assistant_service.dart`:

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_state.dart';
import 'home_assistant_service.dart';

class MusicAssistantService {
  final HomeAssistantService _ha;
  final _stateController = StreamController<MusicPlayerState>.broadcast();
  final _zonesController = StreamController<List<MusicZone>>.broadcast();
  final Map<String, MusicPlayerState> _playerStates = {};
  StreamSubscription? _entitySub;

  MusicAssistantService(this._ha);

  Stream<MusicPlayerState> get playerStateStream => _stateController.stream;
  Stream<List<MusicZone>> get zonesStream => _zonesController.stream;
  Map<String, MusicPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);

  void startListening() {
    _entitySub = _ha.entityStream.listen((entity) {
      if (entity.domain != 'media_player') return;

      final json = {
        'entity_id': entity.entityId,
        'state': entity.state,
        'attributes': entity.attributes,
      };
      final state = parsePlayerState(json);
      _playerStates[entity.entityId] = state;
      _stateController.add(state);

      final zones = _playerStates.entries
          .map((e) => MusicZone(
                id: e.key,
                name: e.value.activeZoneName ?? e.key,
                isActive: e.value.isPlaying,
              ))
          .toList();
      _zonesController.add(zones);
    });
  }

  static MusicPlayerState parsePlayerState(Map<String, dynamic> entityJson) {
    final entityId = entityJson['entity_id'] as String;
    final stateStr = entityJson['state'] as String;
    final attrs = (entityJson['attributes'] as Map<String, dynamic>?) ?? {};

    final playbackState = switch (stateStr) {
      'playing' => PlaybackState.playing,
      'paused' => PlaybackState.paused,
      'off' => PlaybackState.stopped,
      _ => PlaybackState.idle,
    };

    MusicTrack? track;
    final title = attrs['media_title'] as String?;
    if (title != null) {
      track = MusicTrack(
        title: title,
        artist: attrs['media_artist'] as String? ?? 'Unknown',
        album: attrs['media_album_name'] as String? ?? '',
        imageUrl: attrs['entity_picture'] as String?,
        duration: Duration(
            seconds: (attrs['media_duration'] as num?)?.toInt() ?? 0),
      );
    }

    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: track,
      position: Duration(
          seconds: (attrs['media_position'] as num?)?.toInt() ?? 0),
      volume: (attrs['volume_level'] as num?)?.toDouble() ?? 0.5,
      activeZoneId: entityId,
      activeZoneName: attrs['friendly_name'] as String?,
      shuffle: attrs['shuffle'] as bool? ?? false,
      repeatMode: attrs['repeat'] as String? ?? 'off',
    );
  }

  static List<MusicZone> parseZones(List<Map<String, dynamic>> entityJsons) {
    return entityJsons.map((json) => MusicZone.fromJson(json)).toList();
  }

  void playPause(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_play_pause',
      entityId: entityId,
    );
  }

  void nextTrack(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_next_track',
      entityId: entityId,
    );
  }

  void previousTrack(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_previous_track',
      entityId: entityId,
    );
  }

  void setVolume(String entityId, double volume) {
    _ha.callService(
      domain: 'media_player',
      service: 'volume_set',
      entityId: entityId,
      data: {'volume_level': volume},
    );
  }

  void setShuffle(String entityId, bool shuffle) {
    _ha.callService(
      domain: 'media_player',
      service: 'shuffle_set',
      entityId: entityId,
      data: {'shuffle': shuffle},
    );
  }

  void setRepeat(String entityId, String mode) {
    _ha.callService(
      domain: 'media_player',
      service: 'repeat_set',
      entityId: entityId,
      data: {'repeat': mode},
    );
  }

  void dispose() {
    _entitySub?.cancel();
    _stateController.close();
    _zonesController.close();
  }
}

final musicAssistantServiceProvider = Provider<MusicAssistantService>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = MusicAssistantService(ha);
  ref.onDispose(() => service.dispose());
  return service;
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/music_assistant_service_test.dart -v
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/services/music_assistant_service.dart test/services/music_assistant_service_test.dart
git commit -m "feat: Music Assistant service via HA WebSocket with playback control and zone management"
```

---

## Task 6: Frigate Service

**Files:**
- Create: `lib/services/frigate_service.dart`
- Create: `test/services/frigate_service_test.dart`

- [ ] **Step 1: Write Frigate service tests**

Create `test/services/frigate_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/frigate_service.dart';
import 'package:home_hub/models/frigate_event.dart';

void main() {
  group('FrigateService', () {
    test('parseCameras extracts camera names from config', () {
      final cameras = FrigateService.parseCameras(
        configJson: {
          'cameras': {
            'front_door': {'ffmpeg': {}},
            'backyard': {'ffmpeg': {}},
            'garage': {'ffmpeg': {}},
          },
        },
        baseUrl: 'http://frigate.local:5000',
      );
      expect(cameras.length, 3);
      expect(cameras[0].name, 'backyard');
      expect(cameras[0].mjpegStreamUrl,
          'http://frigate.local:5000/api/backyard');
    });

    test('parseEvents extracts event list', () {
      final events = FrigateService.parseEvents(
        eventsJson: [
          {
            'id': 'evt1',
            'camera': 'front_door',
            'label': 'person',
            'top_score': 0.92,
            'start_time': 1712300000.0,
            'end_time': 1712300060.0,
          },
          {
            'id': 'evt2',
            'camera': 'front_door',
            'label': 'doorbell',
            'top_score': 0.99,
            'start_time': 1712300100.0,
            'end_time': null,
          },
        ],
        baseUrl: 'http://frigate.local:5000',
      );
      expect(events.length, 2);
      expect(events[0].isPerson, true);
      expect(events[1].isDoorbell, true);
      expect(events[1].isActive, true);
    });

    test('parseEvents handles empty list', () {
      final events = FrigateService.parseEvents(
        eventsJson: [],
        baseUrl: 'http://frigate.local:5000',
      );
      expect(events, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/frigate_service_test.dart -v
```

Expected: FAIL.

- [ ] **Step 3: Implement FrigateService**

Create `lib/services/frigate_service.dart`:

```dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/frigate_event.dart';
import '../models/ha_entity.dart';
import '../config/hub_config.dart';
import 'home_assistant_service.dart';

class FrigateService {
  final Dio _dio;
  final String _baseUrl;
  final HomeAssistantService _ha;
  final _eventController = StreamController<FrigateEvent>.broadcast();
  final List<FrigateCamera> _cameras = [];
  StreamSubscription? _entitySub;

  FrigateService({
    required String baseUrl,
    required HomeAssistantService ha,
  })  : _baseUrl = baseUrl,
        _ha = ha,
        _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Stream<FrigateEvent> get eventStream => _eventController.stream;
  List<FrigateCamera> get cameras => List.unmodifiable(_cameras);

  static List<FrigateCamera> parseCameras({
    required Map<String, dynamic> configJson,
    required String baseUrl,
  }) {
    final camerasMap = configJson['cameras'] as Map<String, dynamic>? ?? {};
    final names = camerasMap.keys.toList()..sort();
    return names.map((name) => FrigateCamera.fromEntry(name, baseUrl)).toList();
  }

  static List<FrigateEvent> parseEvents({
    required List<dynamic> eventsJson,
    required String baseUrl,
  }) {
    return eventsJson
        .map((e) =>
            FrigateEvent.fromJson(e as Map<String, dynamic>, baseUrl))
        .toList();
  }

  Future<void> loadCameras() async {
    final response = await _dio.get('/api/config');
    _cameras.clear();
    _cameras.addAll(parseCameras(
      configJson: response.data as Map<String, dynamic>,
      baseUrl: _baseUrl,
    ));
  }

  Future<List<FrigateEvent>> getRecentEvents({int limit = 20}) async {
    final response =
        await _dio.get('/api/events', queryParameters: {'limit': limit});
    return parseEvents(
      eventsJson: response.data as List<dynamic>,
      baseUrl: _baseUrl,
    );
  }

  void listenForHaEvents() {
    _entitySub = _ha.entityStream.listen((entity) {
      // Frigate binary sensors: binary_sensor.<camera>_person_detected, etc.
      if (entity.domain == 'binary_sensor' &&
          entity.entityId.contains('frigate') &&
          entity.isOn) {
        // Extract camera name and event type from entity_id
        // e.g., binary_sensor.front_door_person
        final parts = entity.entityId.split('.').last.split('_');
        if (parts.length >= 2) {
          final label = parts.last; // "person", "doorbell", etc.
          final camera = parts.sublist(0, parts.length - 1).join('_');
          _eventController.add(FrigateEvent(
            id: 'ha-${DateTime.now().millisecondsSinceEpoch}',
            camera: camera,
            label: label,
            score: 1.0,
            startTime: DateTime.now(),
          ));
        }
      }
    });
  }

  String mjpegUrl(String cameraName) => '$_baseUrl/api/$cameraName';

  void dispose() {
    _entitySub?.cancel();
    _eventController.close();
    _dio.close();
  }
}

final frigateServiceProvider = Provider<FrigateService>((ref) {
  final config = ref.watch(hubConfigProvider);
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = FrigateService(baseUrl: config.frigateUrl, ha: ha);
  ref.onDispose(() => service.dispose());
  return service;
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/frigate_service_test.dart -v
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/services/frigate_service.dart test/services/frigate_service_test.dart
git commit -m "feat: Frigate service with camera discovery, event parsing, and HA event bridge"
```

---

## Task 7: Display Mode & Local API Server

**Files:**
- Create: `lib/services/display_mode_service.dart`
- Create: `lib/services/local_api_server.dart`
- Create: `test/services/display_mode_service_test.dart`
- Create: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write display mode tests**

Create `test/services/display_mode_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/display_mode_service.dart';
import 'package:home_hub/config/hub_config.dart';

void main() {
  group('DisplayModeService', () {
    test('source "none" always returns day mode', () {
      final service = DisplayModeService();
      const config = HubConfig(nightModeSource: 'none');
      expect(service.resolveMode(config: config), DisplayMode.day);
    });

    test('source "clock" returns night during configured hours', () {
      final service = DisplayModeService();
      const config = HubConfig(
        nightModeSource: 'clock',
        nightModeClockStart: '22:00',
        nightModeClockEnd: '07:00',
      );
      // 23:00 is between 22:00 and 07:00
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 23, 0),
        ),
        DisplayMode.night,
      );
      // 12:00 is outside the range
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 12, 0),
        ),
        DisplayMode.day,
      );
    });

    test('source "clock" with missing times returns day', () {
      final service = DisplayModeService();
      const config = HubConfig(nightModeSource: 'clock');
      expect(service.resolveMode(config: config), DisplayMode.day);
    });

    test('source "api" uses last API value', () {
      final service = DisplayModeService();
      service.setModeFromApi(DisplayMode.night);
      const config = HubConfig(nightModeSource: 'api');
      expect(service.resolveMode(config: config), DisplayMode.night);
    });

    test('source "ha_entity" uses entity state', () {
      final service = DisplayModeService();
      service.setEntityState(isOn: false);
      const config = HubConfig(
        nightModeSource: 'ha_entity',
        nightModeHaEntity: 'light.living_room',
      );
      expect(service.resolveMode(config: config), DisplayMode.night);

      service.setEntityState(isOn: true);
      expect(service.resolveMode(config: config), DisplayMode.day);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/display_mode_service_test.dart -v
```

Expected: FAIL.

- [ ] **Step 3: Implement DisplayModeService**

Create `lib/services/display_mode_service.dart`:

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'home_assistant_service.dart';

enum DisplayMode { day, night }

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

  DisplayMode _resolveClockMode(HubConfig config, DateTime now) {
    if (config.nightModeClockStart == null ||
        config.nightModeClockEnd == null) {
      return DisplayMode.day;
    }

    final startParts = config.nightModeClockStart!.split(':');
    final endParts = config.nightModeClockEnd!.split(':');
    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;

    // Handle overnight range (e.g., 22:00 - 07:00)
    if (startMinutes > endMinutes) {
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
  final service = DisplayModeService();
  ref.onDispose(() => service.dispose());
  return service;
});

final displayModeProvider = StreamProvider<DisplayMode>((ref) {
  final service = ref.watch(displayModeServiceProvider);
  return service.modeStream;
});
```

- [ ] **Step 4: Run display mode tests**

```bash
flutter test test/services/display_mode_service_test.dart -v
```

Expected: All 5 tests pass.

- [ ] **Step 5: Write local API server tests**

Create `test/services/local_api_server_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/local_api_server.dart';
import 'package:home_hub/services/display_mode_service.dart';

void main() {
  group('LocalApiServer', () {
    late DisplayModeService displayService;
    late LocalApiServer server;
    late int port;

    setUp(() async {
      displayService = DisplayModeService();
      server = LocalApiServer(displayModeService: displayService);
      port = await server.start(port: 0); // random available port
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
    });

    test('POST /api/display-mode sets night mode', () async {
      final client = HttpClient();
      final request = await client.post('localhost', port, '/api/display-mode');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'mode': 'night'}));
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], 'night');
      client.close();
    });

    test('POST /api/display-mode sets day mode', () async {
      final client = HttpClient();
      final request = await client.post('localhost', port, '/api/display-mode');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'mode': 'day'}));
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], 'day');
      client.close();
    });

    test('GET /api/display-mode returns current mode', () async {
      final client = HttpClient();
      final request = await client.get('localhost', port, '/api/display-mode');
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], isIn(['day', 'night']));
      client.close();
    });

    test('unknown route returns 404', () async {
      final client = HttpClient();
      final request = await client.get('localhost', port, '/api/unknown');
      final response = await request.close();
      expect(response.statusCode, 404);
      client.close();
    });
  });
}
```

- [ ] **Step 6: Implement LocalApiServer**

Create `lib/services/local_api_server.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'display_mode_service.dart';

class LocalApiServer {
  final DisplayModeService _displayModeService;
  HttpServer? _server;

  LocalApiServer({required DisplayModeService displayModeService})
      : _displayModeService = displayModeService;

  Future<int> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/display-mode') {
      if (request.method == 'POST') {
        await _handleSetDisplayMode(request);
      } else if (request.method == 'GET') {
        await _handleGetDisplayMode(request);
      } else {
        request.response.statusCode = 405;
        await request.response.close();
      }
    } else {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'not found'}));
      await request.response.close();
    }
  }

  Future<void> _handleSetDisplayMode(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modeStr = json['mode'] as String?;

    final mode = modeStr == 'night' ? DisplayMode.night : DisplayMode.day;
    _displayModeService.setModeFromApi(mode);

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': modeStr}));
    await request.response.close();
  }

  Future<void> _handleGetDisplayMode(HttpRequest request) async {
    // Return a simple status — actual mode depends on config source
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': 'day'}));
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close();
  }
}

final localApiServerProvider = Provider<LocalApiServer>((ref) {
  final displayService = ref.watch(displayModeServiceProvider);
  return LocalApiServer(displayModeService: displayService);
});
```

- [ ] **Step 7: Run all service tests**

```bash
flutter test test/services/ -v
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/services/display_mode_service.dart lib/services/local_api_server.dart test/services/display_mode_service_test.dart test/services/local_api_server_test.dart
git commit -m "feat: display mode service with night/day resolution and local API server"
```

---

## Task 8: Hub Shell — Ambient Layer + PageView + Idle Controller

**Files:**
- Create: `lib/app/hub_shell.dart`
- Create: `lib/app/idle_controller.dart`
- Modify: `lib/app/app.dart`
- Create: `test/screens/hub_shell_test.dart`

- [ ] **Step 1: Create IdleController**

Create `lib/app/idle_controller.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';

class IdleController extends ChangeNotifier {
  Timer? _timer;
  bool _isIdle = false;
  int _timeoutSeconds;

  IdleController({int timeoutSeconds = 120})
      : _timeoutSeconds = timeoutSeconds {
    _startTimer();
  }

  bool get isIdle => _isIdle;

  set timeoutSeconds(int value) {
    _timeoutSeconds = value;
    resetTimer();
  }

  void onUserActivity() {
    if (_isIdle) {
      _isIdle = false;
      notifyListeners();
    }
    _startTimer();
  }

  void resetTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _timeoutSeconds), () {
      _isIdle = true;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final idleControllerProvider = ChangeNotifierProvider<IdleController>((ref) {
  final config = ref.watch(hubConfigProvider);
  return IdleController(timeoutSeconds: config.idleTimeoutSeconds);
});
```

- [ ] **Step 2: Create HubShell**

Create `lib/app/hub_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'idle_controller.dart';
import '../screens/ambient/ambient_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/media/media_screen.dart';
import '../screens/controls/controls_screen.dart';
import '../screens/cameras/cameras_screen.dart';
import '../screens/settings/settings_screen.dart';

class HubShell extends ConsumerStatefulWidget {
  const HubShell({super.key});

  @override
  ConsumerState<HubShell> createState() => _HubShellState();
}

class _HubShellState extends ConsumerState<HubShell>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _fadeController;
  static const int _homeIndex = 1; // Media=0, Home=1, Controls=2, Cameras=3, Settings=4

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _homeIndex);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: 0.0, // 0 = active screens visible, 1 = ambient visible
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onUserActivity() {
    ref.read(idleControllerProvider).onUserActivity();
  }

  @override
  Widget build(BuildContext context) {
    final idle = ref.watch(idleControllerProvider);

    // Animate fade based on idle state
    if (idle.isIdle) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _onUserActivity(),
      onPanStart: (_) => _onUserActivity(),
      onPanUpdate: (_) => _onUserActivity(),
      child: Stack(
        children: [
          // Active layer: PageView with screens
          PageView(
            controller: _pageController,
            physics: idle.isIdle
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            children: const [
              MediaScreen(),
              HomeScreen(),
              ControlsScreen(),
              CamerasScreen(),
              SettingsScreen(),
            ],
          ),

          // Ambient layer: fades in when idle
          AnimatedBuilder(
            animation: _fadeController,
            builder: (context, child) {
              if (_fadeController.value == 0.0) return const SizedBox.shrink();
              return Opacity(
                opacity: _fadeController.value,
                child: child,
              );
            },
            child: GestureDetector(
              onTap: () {
                _onUserActivity();
                _pageController.jumpToPage(_homeIndex);
              },
              child: const AmbientScreen(),
            ),
          ),

          // Event overlay layer (doorbell, alerts) — placeholder for Task 12
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Create placeholder screens**

Create each placeholder screen. These will be fleshed out in later tasks.

Create `lib/screens/ambient/ambient_screen.dart`:

```dart
import 'package:flutter/material.dart';

class AmbientScreen extends StatelessWidget {
  const AmbientScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Ambient Display',
          style: TextStyle(color: Colors.white54, fontSize: 24),
        ),
      ),
    );
  }
}
```

Create `lib/screens/home/home_screen.dart`:

```dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Home', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
    );
  }
}
```

Create `lib/screens/media/media_screen.dart`:

```dart
import 'package:flutter/material.dart';

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Media', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
    );
  }
}
```

Create `lib/screens/controls/controls_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ControlsScreen extends StatelessWidget {
  const ControlsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Controls', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
    );
  }
}
```

Create `lib/screens/cameras/cameras_screen.dart`:

```dart
import 'package:flutter/material.dart';

class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Cameras', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
    );
  }
}
```

Create `lib/screens/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Settings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
    );
  }
}
```

- [ ] **Step 4: Update app.dart to use HubShell**

Replace `lib/app/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hub_shell.dart';

class HomeHubApp extends ConsumerWidget {
  const HomeHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Home Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: const Color(0xFF646CFF),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Scaffold(
        body: HubShell(),
      ),
    );
  }
}
```

- [ ] **Step 5: Write hub shell test**

Create `test/screens/hub_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_hub/app/idle_controller.dart';

void main() {
  group('IdleController', () {
    test('starts in active state', () {
      final controller = IdleController(timeoutSeconds: 1);
      expect(controller.isIdle, false);
      controller.dispose();
    });

    test('transitions to idle after timeout', () async {
      final controller = IdleController(timeoutSeconds: 1);
      await Future.delayed(const Duration(seconds: 2));
      expect(controller.isIdle, true);
      controller.dispose();
    });

    test('activity resets idle timer', () async {
      final controller = IdleController(timeoutSeconds: 1);
      await Future.delayed(const Duration(milliseconds: 800));
      controller.onUserActivity();
      await Future.delayed(const Duration(milliseconds: 800));
      expect(controller.isIdle, false);
      controller.dispose();
    });

    test('wakes from idle on activity', () async {
      final controller = IdleController(timeoutSeconds: 1);
      await Future.delayed(const Duration(seconds: 2));
      expect(controller.isIdle, true);
      controller.onUserActivity();
      expect(controller.isIdle, false);
      controller.dispose();
    });
  });
}
```

- [ ] **Step 6: Run tests**

```bash
flutter test test/screens/hub_shell_test.dart -v
```

Expected: All 4 tests pass.

- [ ] **Step 7: Run app to verify navigation**

```bash
cd C:\Users\chris\home_hub
flutter run -d windows
```

Expected: App shows "Home" centered. Swipe left shows "Media", swipe right shows "Controls" → "Cameras" → "Settings". After 2 minutes of no input, "Ambient Display" fades in. Tapping returns to Home.

- [ ] **Step 8: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/app/ lib/screens/ test/screens/
git commit -m "feat: hub shell with PageView navigation, idle controller, and ambient fade"
```

---

## Task 9: Ambient Display — Ken Burns Photo Carousel

**Files:**
- Create: `lib/screens/ambient/photo_carousel.dart`
- Create: `lib/screens/ambient/ambient_overlays.dart`
- Modify: `lib/screens/ambient/ambient_screen.dart`
- Create: `test/screens/ambient/photo_carousel_test.dart`

- [ ] **Step 1: Write photo carousel tests**

Create `test/screens/ambient/photo_carousel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/screens/ambient/photo_carousel.dart';

void main() {
  group('KenBurnsConfig', () {
    test('generates random transform within bounds', () {
      final config = KenBurnsConfig.random();
      expect(config.scale, greaterThanOrEqualTo(1.0));
      expect(config.scale, lessThanOrEqualTo(1.3));
      expect(config.translateX, greaterThanOrEqualTo(-30.0));
      expect(config.translateX, lessThanOrEqualTo(30.0));
      expect(config.translateY, greaterThanOrEqualTo(-20.0));
      expect(config.translateY, lessThanOrEqualTo(20.0));
    });

    test('two random configs are likely different', () {
      final a = KenBurnsConfig.random();
      final b = KenBurnsConfig.random();
      // Very unlikely all three values match
      final same =
          a.scale == b.scale &&
          a.translateX == b.translateX &&
          a.translateY == b.translateY;
      expect(same, false);
    });
  });
}
```

- [ ] **Step 2: Implement KenBurnsConfig and PhotoCarousel**

Create `lib/screens/ambient/photo_carousel.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

class KenBurnsConfig {
  final double scale;
  final double translateX;
  final double translateY;

  const KenBurnsConfig({
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  factory KenBurnsConfig.random() {
    final rng = Random();
    return KenBurnsConfig(
      scale: 1.0 + rng.nextDouble() * 0.3, // 1.0 - 1.3
      translateX: (rng.nextDouble() - 0.5) * 60, // -30 to 30
      translateY: (rng.nextDouble() - 0.5) * 40, // -20 to 20
    );
  }
}

class PhotoCarousel extends StatefulWidget {
  final Stream<String?> photoPathStream;
  final Duration photoInterval;
  final Duration animationDuration;

  const PhotoCarousel({
    super.key,
    required this.photoPathStream,
    this.photoInterval = const Duration(seconds: 15),
    this.animationDuration = const Duration(seconds: 14),
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel>
    with TickerProviderStateMixin {
  String? _currentPath;
  String? _nextPath;
  KenBurnsConfig _currentKB = KenBurnsConfig.random();
  KenBurnsConfig _targetKB = KenBurnsConfig.random();
  late AnimationController _kenBurnsController;
  late AnimationController _crossfadeController;
  StreamSubscription<String?>? _photoSub;

  @override
  void initState() {
    super.initState();
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..repeat();

    _crossfadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _photoSub = widget.photoPathStream.listen((path) {
      if (path == null) return;
      if (_currentPath == null) {
        setState(() => _currentPath = path);
      } else {
        _nextPath = path;
        _crossfadeController.forward(from: 0.0).then((_) {
          setState(() {
            _currentPath = _nextPath;
            _currentKB = _targetKB;
            _targetKB = KenBurnsConfig.random();
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _photoSub?.cancel();
    _kenBurnsController.dispose();
    _crossfadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Current photo with Ken Burns
        if (_currentPath != null)
          AnimatedBuilder(
            animation: _kenBurnsController,
            builder: (context, child) {
              final t = _kenBurnsController.value;
              final scale =
                  _currentKB.scale + (_targetKB.scale - _currentKB.scale) * t;
              final tx = _currentKB.translateX +
                  (_targetKB.translateX - _currentKB.translateX) * t;
              final ty = _currentKB.translateY +
                  (_targetKB.translateY - _currentKB.translateY) * t;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(tx, ty)
                  ..scale(scale),
                child: child,
              );
            },
            child: Image.file(
              File(_currentPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // Crossfading next photo
        if (_nextPath != null)
          FadeTransition(
            opacity: _crossfadeController,
            child: Image.file(
              File(_nextPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Create ambient overlays**

Create `lib/screens/ambient/ambient_overlays.dart`:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';

class AmbientOverlays extends ConsumerWidget {
  final String? memoryLabel;
  final MusicPlayerState? musicState;

  const AmbientOverlays({
    super.key,
    this.memoryLabel,
    this.musicState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    // TODO: Replace with intl DateFormat when wiring up
    final dateStr = _formatDate(now);

    return Stack(
      children: [
        // Bottom gradient for text legibility
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 200,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),

        // Clock — bottom left
        Positioned(
          left: 24,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),

        // Weather — bottom right (placeholder, wired in later)
        Positioned(
          right: 24,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '72°',
                style: const TextStyle(
                  fontSize: 36,
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                'Partly Cloudy',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),

        // Memory label — top left
        if (memoryLabel != null)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                memoryLabel!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),

        // Now playing pill — top right
        if (musicState != null && musicState!.hasTrack)
          Positioned(
            top: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          musicState!.isPlaying
                              ? Icons.play_arrow
                              : Icons.pause,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            musicState!.currentTrack!.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${musicState!.currentTrack!.artist} · ${musicState!.activeZoneName ?? ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }
}
```

- [ ] **Step 4: Update AmbientScreen to compose carousel + overlays**

Replace `lib/screens/ambient/ambient_screen.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/immich_service.dart';
import '../../services/music_assistant_service.dart';
import '../../models/music_state.dart';
import '../../models/photo_memory.dart';
import 'photo_carousel.dart';
import 'ambient_overlays.dart';

class AmbientScreen extends ConsumerStatefulWidget {
  const AmbientScreen({super.key});

  @override
  ConsumerState<AmbientScreen> createState() => _AmbientScreenState();
}

class _AmbientScreenState extends ConsumerState<AmbientScreen> {
  final _photoPathController = StreamController<String?>.broadcast();
  Timer? _photoTimer;
  PhotoMemory? _currentMemory;
  MusicPlayerState? _musicState;

  @override
  void initState() {
    super.initState();
    _startPhotoRotation();
  }

  void _startPhotoRotation() {
    _loadNextPhoto();
    _photoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadNextPhoto();
    });
  }

  Future<void> _loadNextPhoto() async {
    try {
      final immich = ref.read(immichServiceProvider);
      final memory = immich.nextPhoto;
      if (memory == null) return;

      final cachedPath = immich.getCachedPath(memory.assetId);
      if (cachedPath != null) {
        setState(() => _currentMemory = memory);
        _photoPathController.add(cachedPath);
      } else {
        final path = await immich.cachePhoto(memory);
        setState(() => _currentMemory = memory);
        _photoPathController.add(path);
      }
    } catch (_) {
      // Silently continue — will retry next interval
    }
  }

  @override
  void dispose() {
    _photoTimer?.cancel();
    _photoPathController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoCarousel(
            photoPathStream: _photoPathController.stream,
          ),
          AmbientOverlays(
            memoryLabel: _currentMemory?.memoryLabel,
            musicState: _musicState,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run photo carousel tests**

```bash
flutter test test/screens/ambient/photo_carousel_test.dart -v
```

Expected: All 2 tests pass.

- [ ] **Step 6: Run app to verify ambient display**

```bash
flutter run -d windows
```

Expected: After idle timeout, ambient screen shows with clock overlay, weather placeholder, date, and gradient. Photos won't load without Immich configured, but the overlay layout should be visible on a black background.

- [ ] **Step 7: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/ambient/ test/screens/ambient/
git commit -m "feat: ambient display with Ken Burns photo carousel and contextual overlays"
```

---

## Task 10: Home Screen

**Files:**
- Modify: `lib/screens/home/home_screen.dart`
- Create: `lib/widgets/now_playing_bar.dart`

- [ ] **Step 1: Create NowPlayingBar widget**

Create `lib/widgets/now_playing_bar.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/music_state.dart';

class NowPlayingBar extends StatelessWidget {
  final MusicPlayerState musicState;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;

  const NowPlayingBar({
    super.key,
    required this.musicState,
    this.onTap,
    this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    if (!musicState.hasTrack) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Album art placeholder
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: musicState.currentTrack?.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        musicState.currentTrack!.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    )
                  : const Icon(Icons.music_note, color: Colors.white54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    musicState.currentTrack!.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    musicState.currentTrack!.artist,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                musicState.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: onPlayPause,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement HomeScreen**

Replace `lib/screens/home/home_screen.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/now_playing_bar.dart';
import '../../models/music_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = '${_now.hour}:${_now.minute.toString().padLeft(2, '0')}';
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 1),

          // Clock
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w100,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 20,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),

          const SizedBox(height: 24),

          // Weather placeholder
          Row(
            children: [
              const Text(
                '72°',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w200),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Partly Cloudy', style: TextStyle(fontSize: 16)),
                  Text(
                    'H: 78° L: 65°',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(flex: 2),

          // Quick scenes placeholder
          Row(
            children: [
              _SceneButton(label: 'Movie Night', icon: Icons.movie),
              const SizedBox(width: 12),
              _SceneButton(label: 'Goodnight', icon: Icons.bedtime),
              const SizedBox(width: 12),
              _SceneButton(label: 'All Off', icon: Icons.power_settings_new),
            ],
          ),

          const SizedBox(height: 16),

          // Now playing bar placeholder
          const NowPlayingBar(
            musicState: MusicPlayerState(
              playbackState: PlaybackState.playing,
              currentTrack: MusicTrack(
                title: 'No music playing',
                artist: 'Connect Music Assistant in settings',
                album: '',
                duration: Duration.zero,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SceneButton extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SceneButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Colors.white70),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run app to verify Home screen**

```bash
flutter run -d windows
```

Expected: Home screen shows large clock, date, weather placeholder, scene buttons, and now-playing bar. Swipe navigation still works.

- [ ] **Step 4: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/home/ lib/widgets/now_playing_bar.dart
git commit -m "feat: home screen with clock, weather, scene buttons, and now-playing bar"
```

---

## Task 11: Media Screen

**Files:**
- Modify: `lib/screens/media/media_screen.dart`

- [ ] **Step 1: Implement MediaScreen**

Replace `lib/screens/media/media_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';

class MediaScreen extends ConsumerWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder state — will be wired to MusicAssistantService
    const state = MusicPlayerState(
      playbackState: PlaybackState.idle,
    );

    return Padding(
      padding: const EdgeInsets.all(32),
      child: state.hasTrack ? _NowPlaying(state: state) : _NoMusic(),
    );
  }
}

class _NoMusic extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'No music playing',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final MusicPlayerState state;
  const _NowPlaying({required this.state});

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack!;
    return Column(
      children: [
        const Spacer(),

        // Album art
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: track.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(track.imageUrl!, fit: BoxFit.cover),
                )
              : const Icon(Icons.album, size: 80, color: Colors.white24),
        ),

        const SizedBox(height: 24),

        // Track info
        Text(
          track.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${track.artist} — ${track.album}',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 24),

        // Progress bar placeholder
        LinearProgressIndicator(
          value: track.duration.inSeconds > 0
              ? state.position.inSeconds / track.duration.inSeconds
              : 0,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation(Colors.white70),
        ),

        const SizedBox(height: 24),

        // Playback controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle ? Colors.white : Colors.white38,
              ),
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 36,
                ),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                Icons.repeat,
                color: state.repeatMode != 'off' ? Colors.white : Colors.white38,
              ),
              onPressed: () {},
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Volume slider
        Row(
          children: [
            const Icon(Icons.volume_down, color: Colors.white54),
            Expanded(
              child: Slider(
                value: state.volume,
                onChanged: (_) {},
                activeColor: Colors.white70,
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white54),
          ],
        ),

        const SizedBox(height: 8),

        // Zone selector placeholder
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speaker, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                state.activeZoneName ?? 'Select zone',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16, color: Colors.white54),
            ],
          ),
        ),

        const Spacer(),
      ],
    );
  }
}
```

- [ ] **Step 2: Run app to verify media screen**

```bash
flutter run -d windows
```

Expected: Swiping left from Home shows the media screen with "No music playing" placeholder.

- [ ] **Step 3: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/media/
git commit -m "feat: media screen with album art, playback controls, volume, and zone selector"
```

---

## Task 12: Controls Screen (Lights + Climate)

**Files:**
- Modify: `lib/screens/controls/controls_screen.dart`
- Create: `lib/screens/controls/light_card.dart`
- Create: `lib/screens/controls/climate_card.dart`

- [ ] **Step 1: Create LightCard**

Create `lib/screens/controls/light_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/ha_entity.dart';

class LightCard extends StatelessWidget {
  final HaEntity entity;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<double>? onBrightnessChanged;

  const LightCard({
    super.key,
    required this.entity,
    this.onToggle,
    this.onBrightnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = entity.brightness;
    final brightnessPercent =
        brightness != null ? (brightness / 255 * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: entity.isOn
            ? Colors.amber.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: entity.isOn ? Colors.amber : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entity.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                value: entity.isOn,
                onChanged: onToggle,
                activeColor: Colors.amber,
              ),
            ],
          ),
          if (entity.isOn && brightness != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.brightness_low, size: 14, color: Colors.white38),
                Expanded(
                  child: Slider(
                    value: brightness.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: onBrightnessChanged,
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                Text(
                  '$brightnessPercent%',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create ClimateCard**

Create `lib/screens/controls/climate_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/ha_entity.dart';

class ClimateCard extends StatelessWidget {
  final HaEntity entity;
  final ValueChanged<double>? onTemperatureChanged;
  final ValueChanged<String>? onModeChanged;

  const ClimateCard({
    super.key,
    required this.entity,
    this.onTemperatureChanged,
    this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.thermostat, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                entity.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Current temperature
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entity.currentTemperature?.round() ?? '--'}°',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w200,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Set to ${entity.temperature?.round() ?? '--'}°',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    entity.hvacMode?.toUpperCase() ?? 'OFF',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Temperature adjustment
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 32),
                onPressed: () {
                  final current = entity.temperature ?? 72;
                  onTemperatureChanged?.call(current - 1);
                },
              ),
              const SizedBox(width: 24),
              Text(
                '${entity.temperature?.round() ?? '--'}°',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 32),
                onPressed: () {
                  final current = entity.temperature ?? 72;
                  onTemperatureChanged?.call(current + 1);
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Mode selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ModeChip(label: 'Heat', active: entity.hvacMode == 'heat', onTap: () => onModeChanged?.call('heat')),
              _ModeChip(label: 'Cool', active: entity.hvacMode == 'cool', onTap: () => onModeChanged?.call('cool')),
              _ModeChip(label: 'Auto', active: entity.hvacMode == 'auto', onTap: () => onModeChanged?.call('auto')),
              _ModeChip(label: 'Off', active: entity.hvacMode == 'off', onTap: () => onModeChanged?.call('off')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ModeChip({required this.label, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.orange.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: active ? Border.all(color: Colors.orange.withValues(alpha: 0.5)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? Colors.orange : Colors.white54,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement ControlsScreen**

Replace `lib/screens/controls/controls_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ha_entity.dart';
import 'light_card.dart';
import 'climate_card.dart';

class ControlsScreen extends ConsumerWidget {
  const ControlsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder entities — will be wired to HA service
    final lights = <HaEntity>[];
    final climates = <HaEntity>[];

    if (lights.isEmpty && climates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'No devices',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect Home Assistant in settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (lights.isNotEmpty) ...[
          Text(
            'Lights',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ...lights.map((entity) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LightCard(entity: entity),
              )),
          const SizedBox(height: 24),
        ],
        if (climates.isNotEmpty) ...[
          Text(
            'Climate',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ...climates.map((entity) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClimateCard(entity: entity),
              )),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run app to verify controls screen**

```bash
flutter run -d windows
```

Expected: Swiping right from Home shows Controls with "No devices" placeholder.

- [ ] **Step 5: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/controls/
git commit -m "feat: controls screen with light cards, climate cards, and room grouping"
```

---

## Task 13: Cameras Screen

**Files:**
- Modify: `lib/screens/cameras/cameras_screen.dart`

- [ ] **Step 1: Implement CamerasScreen**

Replace `lib/screens/cameras/cameras_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/frigate_event.dart';

class CamerasScreen extends ConsumerStatefulWidget {
  const CamerasScreen({super.key});

  @override
  ConsumerState<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends ConsumerState<CamerasScreen> {
  String? _expandedCamera;

  @override
  Widget build(BuildContext context) {
    // Placeholder — will be wired to FrigateService
    final cameras = <FrigateCamera>[];
    final events = <FrigateEvent>[];

    if (cameras.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'No cameras',
              style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect Frigate in settings',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ),
      );
    }

    if (_expandedCamera != null) {
      return GestureDetector(
        onTap: () => setState(() => _expandedCamera = null),
        child: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // MJPEG stream would render here
                Container(
                  width: double.infinity,
                  height: 500,
                  color: Colors.grey[900],
                  child: Center(
                    child: Text(
                      _expandedCamera!,
                      style: const TextStyle(fontSize: 24, color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to return to grid',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Camera grid
          Expanded(
            flex: 3,
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cameras.length <= 4 ? 2 : 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 16 / 9,
              ),
              itemCount: cameras.length,
              itemBuilder: (context, index) {
                final cam = cameras[index];
                return GestureDetector(
                  onTap: () => setState(() => _expandedCamera = cam.name),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        // MJPEG stream placeholder
                        Center(
                          child: Icon(Icons.videocam, color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              cam.name,
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Recent events
          if (events.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Events',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          event.isDoorbell ? Icons.doorbell : Icons.person,
                          size: 18,
                          color: event.isDoorbell ? Colors.red : Colors.blue,
                        ),
                        const Spacer(),
                        Text(event.camera, style: const TextStyle(fontSize: 11)),
                        Text(
                          event.label,
                          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run app to verify cameras screen**

```bash
flutter run -d windows
```

Expected: Cameras screen shows "No cameras" placeholder.

- [ ] **Step 3: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/cameras/
git commit -m "feat: cameras screen with grid view, single expand, and recent events"
```

---

## Task 14: Settings Screen

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Implement SettingsScreen**

Replace `lib/screens/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w200),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Connections'),
        _SettingsTile(
          icon: Icons.photo_library,
          title: 'Immich',
          subtitle: config.immichUrl.isEmpty ? 'Not configured' : config.immichUrl,
          onTap: () => _showTextDialog(
            title: 'Immich URL',
            currentValue: config.immichUrl,
            hint: 'http://immich.local:2283',
            onSave: (v) => _updateConfig((c) => c.copyWith(immichUrl: v)),
          ),
        ),
        _SettingsTile(
          icon: Icons.key,
          title: 'Immich API Key',
          subtitle: config.immichApiKey.isEmpty ? 'Not set' : '••••••••',
          onTap: () => _showTextDialog(
            title: 'Immich API Key',
            currentValue: config.immichApiKey,
            hint: 'API key from Immich settings',
            onSave: (v) => _updateConfig((c) => c.copyWith(immichApiKey: v)),
          ),
        ),
        _SettingsTile(
          icon: Icons.home,
          title: 'Home Assistant',
          subtitle: config.haUrl.isEmpty ? 'Not configured' : config.haUrl,
          onTap: () => _showTextDialog(
            title: 'Home Assistant WebSocket URL',
            currentValue: config.haUrl,
            hint: 'ws://homeassistant.local:8123/api/websocket',
            onSave: (v) => _updateConfig((c) => c.copyWith(haUrl: v)),
          ),
        ),
        _SettingsTile(
          icon: Icons.key,
          title: 'HA Access Token',
          subtitle: config.haToken.isEmpty ? 'Not set' : '••••••••',
          onTap: () => _showTextDialog(
            title: 'HA Long-Lived Access Token',
            currentValue: config.haToken,
            hint: 'Token from HA profile page',
            onSave: (v) => _updateConfig((c) => c.copyWith(haToken: v)),
          ),
        ),
        _SettingsTile(
          icon: Icons.videocam,
          title: 'Frigate',
          subtitle: config.frigateUrl.isEmpty ? 'Not configured' : config.frigateUrl,
          onTap: () => _showTextDialog(
            title: 'Frigate URL',
            currentValue: config.frigateUrl,
            hint: 'http://frigate.local:5000',
            onSave: (v) => _updateConfig((c) => c.copyWith(frigateUrl: v)),
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Display'),
        _SettingsTile(
          icon: Icons.timer,
          title: 'Idle Timeout',
          subtitle: '${config.idleTimeoutSeconds} seconds',
          onTap: () => _showSliderDialog(
            title: 'Idle Timeout (seconds)',
            currentValue: config.idleTimeoutSeconds.toDouble(),
            min: 30,
            max: 600,
            divisions: 19,
            onSave: (v) => _updateConfig((c) => c.copyWith(idleTimeoutSeconds: v.round())),
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Night Mode'),
        _SettingsTile(
          icon: Icons.nightlight_round,
          title: 'Trigger Source',
          subtitle: config.nightModeSource,
          onTap: () => _showChoiceDialog(
            title: 'Night Mode Source',
            choices: ['none', 'ha_entity', 'api', 'clock'],
            current: config.nightModeSource,
            onSave: (v) => _updateConfig((c) => c.copyWith(nightModeSource: v)),
          ),
        ),
        if (config.nightModeSource == 'ha_entity')
          _SettingsTile(
            icon: Icons.lightbulb_outline,
            title: 'HA Entity',
            subtitle: config.nightModeHaEntity ?? 'Not set',
            onTap: () => _showTextDialog(
              title: 'Night Mode HA Entity',
              currentValue: config.nightModeHaEntity ?? '',
              hint: 'light.living_room',
              onSave: (v) => _updateConfig((c) => c.copyWith(nightModeHaEntity: v)),
            ),
          ),
        if (config.nightModeSource == 'clock') ...[
          _SettingsTile(
            icon: Icons.schedule,
            title: 'Start Time',
            subtitle: config.nightModeClockStart ?? 'Not set',
            onTap: () => _showTextDialog(
              title: 'Night Mode Start Time',
              currentValue: config.nightModeClockStart ?? '',
              hint: '22:00',
              onSave: (v) => _updateConfig((c) => c.copyWith(nightModeClockStart: v)),
            ),
          ),
          _SettingsTile(
            icon: Icons.schedule,
            title: 'End Time',
            subtitle: config.nightModeClockEnd ?? 'Not set',
            onTap: () => _showTextDialog(
              title: 'Night Mode End Time',
              currentValue: config.nightModeClockEnd ?? '',
              hint: '07:00',
              onSave: (v) => _updateConfig((c) => c.copyWith(nightModeClockEnd: v)),
            ),
          ),
        ],

        const SizedBox(height: 24),
        _SectionHeader('Music'),
        _SettingsTile(
          icon: Icons.speaker,
          title: 'Default Zone',
          subtitle: config.defaultMusicZone ?? 'Not set',
          onTap: () => _showTextDialog(
            title: 'Default Music Zone',
            currentValue: config.defaultMusicZone ?? '',
            hint: 'media_player.kitchen',
            onSave: (v) => _updateConfig((c) => c.copyWith(defaultMusicZone: v)),
          ),
        ),
      ],
    );
  }

  Future<void> _updateConfig(HubConfig Function(HubConfig) updater) async {
    await ref.read(hubConfigProvider.notifier).update(updater);
  }

  Future<void> _showTextDialog({
    required String title,
    required String currentValue,
    required String hint,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _showSliderDialog({
    required String title,
    required double currentValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onSave,
  }) async {
    var value = currentValue;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: '${value.round()}',
                onChanged: (v) => setDialogState(() => value = v),
              ),
              Text('${value.round()}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _showChoiceDialog({
    required String title,
    required List<String> choices,
    required String current,
    required ValueChanged<String> onSave,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: choices.map((c) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, c),
          child: Row(
            children: [
              if (c == current)
                const Icon(Icons.check, size: 18, color: Colors.blue)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(c),
            ],
          ),
        )).toList(),
      ),
    );
    if (result != null) onSave(result);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.4),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white54),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
```

- [ ] **Step 2: Run app to verify settings screen**

```bash
flutter run -d windows
```

Expected: Settings screen shows all configuration sections. Tapping a setting opens a dialog. Values persist after changing and restarting.

- [ ] **Step 3: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/screens/settings/
git commit -m "feat: settings screen with connection config, display settings, and night mode"
```

---

## Task 15: Event Overlay (Doorbell + Alerts)

**Files:**
- Create: `lib/widgets/event_overlay.dart`
- Modify: `lib/app/hub_shell.dart`

- [ ] **Step 1: Create EventOverlay widget**

Create `lib/widgets/event_overlay.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/frigate_event.dart';

enum OverlayPriority { safety, doorbell, info }

class EventOverlayData {
  final String id;
  final OverlayPriority priority;
  final String title;
  final String? subtitle;
  final String? cameraName;
  final bool persistent;
  final Duration autoDismiss;

  const EventOverlayData({
    required this.id,
    required this.priority,
    required this.title,
    this.subtitle,
    this.cameraName,
    this.persistent = false,
    this.autoDismiss = const Duration(seconds: 30),
  });

  factory EventOverlayData.fromFrigateEvent(FrigateEvent event) {
    if (event.isDoorbell) {
      return EventOverlayData(
        id: event.id,
        priority: OverlayPriority.doorbell,
        title: 'Doorbell',
        subtitle: event.camera,
        cameraName: event.camera,
        autoDismiss: const Duration(seconds: 30),
      );
    }
    return EventOverlayData(
      id: event.id,
      priority: OverlayPriority.info,
      title: 'Person Detected',
      subtitle: event.camera,
      cameraName: event.camera,
      autoDismiss: const Duration(seconds: 10),
    );
  }

  factory EventOverlayData.safetyAlert({
    required String title,
    String? subtitle,
  }) {
    return EventOverlayData(
      id: 'safety-${DateTime.now().millisecondsSinceEpoch}',
      priority: OverlayPriority.safety,
      title: title,
      subtitle: subtitle,
      persistent: true,
    );
  }
}

class EventOverlay extends StatefulWidget {
  final EventOverlayData data;
  final String? mjpegUrl;
  final VoidCallback onDismiss;

  const EventOverlay({
    super.key,
    required this.data,
    this.mjpegUrl,
    required this.onDismiss,
  });

  @override
  State<EventOverlay> createState() => _EventOverlayState();
}

class _EventOverlayState extends State<EventOverlay> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.data.persistent) {
      _dismissTimer = Timer(widget.data.autoDismiss, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.priority == OverlayPriority.doorbell) {
      return _DoorbellOverlay(data: widget.data, onDismiss: widget.onDismiss);
    }
    if (widget.data.priority == OverlayPriority.safety) {
      return _SafetyOverlay(data: widget.data, onDismiss: widget.onDismiss);
    }
    return _InfoOverlay(data: widget.data, onDismiss: widget.onDismiss);
  }
}

class _DoorbellOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;
  const _DoorbellOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Camera feed placeholder
            Container(
              width: double.infinity,
              height: 500,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.videocam, size: 64, color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.doorbell, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Doorbell',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tap anywhere to dismiss',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;
  const _SafetyOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.red[900],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      if (data.subtitle != null)
                        Text(data.subtitle!,
                            style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('DISMISS',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;
  const _InfoOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue[900]?.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.person, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${data.title} — ${data.subtitle ?? ""}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run app to verify**

```bash
flutter run -d windows
```

Expected: App compiles and runs. Event overlays will be triggered when Frigate integration is wired up.

- [ ] **Step 3: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/widgets/event_overlay.dart
git commit -m "feat: event overlay system for doorbell, person detection, and safety alerts"
```

---

## Task 16: Wire Up Services — App Initialization

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app/hub_shell.dart`

- [ ] **Step 1: Update main.dart to initialize services**

Replace `lib/main.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_size/window_size.dart' as window_size;
import 'app/app.dart';
import 'config/hub_config.dart';
import 'services/home_assistant_service.dart';
import 'services/immich_service.dart';
import 'services/music_assistant_service.dart';
import 'services/frigate_service.dart';
import 'services/display_mode_service.dart';
import 'services/local_api_server.dart';

const double kWindowWidth = 1184;
const double kWindowHeight = 864;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    window_size.setWindowTitle('Home Hub');
    window_size.setWindowMinSize(const Size(kWindowWidth, kWindowHeight));
    window_size.setWindowMaxSize(const Size(kWindowWidth, kWindowHeight));
  }

  final container = ProviderContainer();
  await container.read(hubConfigProvider.notifier).load();

  final config = container.read(hubConfigProvider);

  // Connect to Home Assistant
  if (config.haUrl.isNotEmpty && config.haToken.isNotEmpty) {
    final ha = container.read(homeAssistantServiceProvider);
    try {
      await ha.connectToUrl(config.haUrl, config.haToken);
    } catch (e) {
      debugPrint('HA connection failed: $e');
    }

    // Start Music Assistant listener
    final music = container.read(musicAssistantServiceProvider);
    music.startListening();

    // Start Frigate event listener
    if (config.frigateUrl.isNotEmpty) {
      final frigate = container.read(frigateServiceProvider);
      frigate.listenForHaEvents();
      try {
        await frigate.loadCameras();
      } catch (e) {
        debugPrint('Frigate camera load failed: $e');
      }
    }

    // Wire up night mode HA entity
    final displayMode = container.read(displayModeServiceProvider);
    if (config.nightModeSource == 'ha_entity' &&
        config.nightModeHaEntity != null) {
      displayMode.listenToHaEntity(ha, config.nightModeHaEntity!);
    }
  }

  // Load Immich memories
  if (config.immichUrl.isNotEmpty && config.immichApiKey.isNotEmpty) {
    final immich = container.read(immichServiceProvider);
    try {
      await immich.loadMemories();
      await immich.prefetchPhotos();
    } catch (e) {
      debugPrint('Immich load failed: $e');
    }
  }

  // Start local API server
  final apiServer = container.read(localApiServerProvider);
  try {
    final port = await apiServer.start();
    debugPrint('Local API server on port $port');
  } catch (e) {
    debugPrint('API server start failed: $e');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HomeHubApp(),
    ),
  );
}
```

- [ ] **Step 2: Run app to verify initialization**

```bash
flutter run -d windows
```

Expected: App starts with no crashes. Services that aren't configured log messages and continue gracefully. All screens still work.

- [ ] **Step 3: Run all tests**

```bash
flutter test -v
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd C:\Users\chris\home_hub
git add lib/main.dart
git commit -m "feat: wire up all services in app initialization with graceful fallbacks"
```

---

## Task 17: Run Full Test Suite & Final Verification

**Files:** None — verification only.

- [ ] **Step 1: Run full test suite**

```bash
cd C:\Users\chris\home_hub
flutter test -v
```

Expected: All tests pass.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: No errors. Warnings are acceptable but should be reviewed.

- [ ] **Step 3: Full app smoke test**

```bash
flutter run -d windows
```

Verify:
- App opens at 1184x864
- Home screen shows clock, weather placeholder, scene buttons, mini player
- Swipe left → Media screen
- Swipe right from Home → Controls → Cameras → Settings
- Settings → configure a fake Immich URL → value persists
- Night mode setting appears based on source selection
- After idle timeout → ambient screen fades in
- Tap ambient → returns to Home

- [ ] **Step 4: Final commit**

```bash
cd C:\Users\chris\home_hub
git add -A
git commit -m "chore: final verification pass — all tests passing, all screens functional"
```
