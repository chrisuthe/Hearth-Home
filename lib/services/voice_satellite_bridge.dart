import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import '../utils/logger.dart';

/// Stands in for the platform check in tests.
@visibleForTesting
bool? debugVoiceSatelliteSupportedOverride;

/// Whether this build can host the in-app voice satellite. Everything the
/// satellite adds is gated on this, so the Pi and desktop paths are untouched.
///
/// `dart:io`, not `defaultTargetPlatform`: the latter reports Android under
/// `flutter test`, which would send every widget test to the channel.
bool get voiceSatelliteSupported =>
    debugVoiceSatelliteSupportedOverride ?? (!kIsWeb && Platform.isAndroid);

/// `voiceWakeSensitivity` values, most conservative first.
const kVoiceWakeSensitivities = <String, String>{
  'slightly': 'Slightly sensitive',
  'moderately': 'Moderately sensitive',
  'very': 'Very sensitive',
};

/// `voiceAudioSource` values, as Android's `MediaRecorder.AudioSource`.
const kVoiceAudioSources = <String, String>{
  'voiceRecognition': 'Voice recognition',
  'mic': 'Microphone',
  'voiceCommunication': 'Voice communication',
  'unprocessed': 'Unprocessed',
};

/// The port Home Assistant expects an ESPHome device on.
const kVoiceSatellitePort = 6053;

/// A wake-word model bundled in the APK.
class VoiceWakeWord {
  final String id;
  final String name;
  const VoiceWakeWord(this.id, this.name);
}

/// A problem the service reported: `permissionMissing`, `portInUse`,
/// `micOpenFailed` or `modelLoadFailed`.
class VoiceSatelliteHealth {
  final String code;
  final String message;
  final DateTime at;
  const VoiceSatelliteHealth(this.code, this.message, this.at);

  String get label => switch (code) {
        'permissionMissing' => 'Microphone permission missing',
        'portInUse' => 'Port $kVoiceSatellitePort unavailable',
        'micOpenFailed' => 'Microphone could not be opened',
        'modelLoadFailed' => 'Wake word model failed to load',
        _ => code,
      };
}

/// What the Android service last reported. Diagnostics only: the voice pill
/// still follows the Home Assistant entity.
class VoiceSatelliteStatus {
  /// The service has been asked to run.
  final bool running;

  /// `idle`, `listening`, `processing`, `responding` or `error`.
  final String state;

  /// Home Assistant holds a connection to the satellite.
  final bool connected;

  final VoiceSatelliteHealth? health;

  const VoiceSatelliteStatus({
    this.running = false,
    this.state = 'idle',
    this.connected = false,
    this.health,
  });

  VoiceSatelliteStatus copyWith({
    bool? running,
    String? state,
    bool? connected,
    VoiceSatelliteHealth? health,
  }) =>
      VoiceSatelliteStatus(
        running: running ?? this.running,
        state: state ?? this.state,
        connected: connected ?? this.connected,
        health: health ?? this.health,
      );

  String get connectionLabel {
    if (!running) return 'Stopped';
    if (state == 'error') return 'Error';
    return connected ? 'Connected' : 'Waiting for Home Assistant';
  }
}

/// Owns the `com.hearth/voice` channel to `HearthAudioService`.
///
/// The service persists nothing, so this is where the satellite's settings
/// meet `hub_config.json`: [sync] starts, restarts or stops the service to
/// match the config, and `settingChanged` events (a change made from Home
/// Assistant) are written back. Off Android every method returns at once.
///
/// Later phases add to the same channel: `startTimerRing` / `stopTimerRing`
/// and the `timer`, `duck` and `ringStopped` events.
class VoiceSatelliteBridge {
  static const _tag = 'VoiceSatellite';
  static const _methods = MethodChannel('com.hearth/voice');
  // A MethodChannel and an EventChannel cannot share a name.
  static const _events = EventChannel('com.hearth/voice/events');

  final HubConfigNotifier _config;
  final bool _supported;
  final String Function() _hostname;
  final Random _random;

  StreamSubscription<dynamic>? _eventSub;
  Timer? _debounce;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// The `start` payload the service is running with; null when stopped.
  Map<String, Object>? _applied;
  bool? _appliedMuted;

  VoiceSatelliteStatus _status = const VoiceSatelliteStatus();
  final _statusController = StreamController<VoiceSatelliteStatus>.broadcast();
  List<VoiceWakeWord> _wakeWords = const [];

  VoiceSatelliteBridge(
    this._config, {
    bool? supported,
    String Function()? hostname,
    Random? random,
  })  : _supported = supported ?? voiceSatelliteSupported,
        _hostname = hostname ?? (() => Platform.localHostname),
        _random = random ?? Random.secure();

  VoiceSatelliteStatus get status => _status;
  Stream<VoiceSatelliteStatus> get statusStream => _statusController.stream;

  /// Wake words bundled in the APK; empty until [attach] has asked for them.
  List<VoiceWakeWord> get wakeWords => _wakeWords;

  /// Starts listening to the service and loads the wake-word list.
  Future<void> attach() async {
    if (!_supported) return;
    _eventSub = _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object e) => Log.w(_tag, 'event stream error: $e'),
        );
    await _loadWakeWords();
  }

  Future<void> _loadWakeWords() async {
    try {
      final raw = await _methods.invokeListMethod<Map>('listWakeWords') ?? [];
      _wakeWords = [
        for (final w in raw)
          VoiceWakeWord(w['id'] as String, w['name'] as String? ?? ''),
      ]..sort((a, b) => a.name.compareTo(b.name));
      _emit(_status);
    } catch (e) {
      Log.w(_tag, 'listWakeWords failed: $e');
    }
  }

  /// Brings the service in line with [config]. Calls are queued so a start
  /// never overlaps the stop before it.
  Future<void> sync(HubConfig config) {
    if (!_supported || _disposed) return Future.value();
    return _queue = _queue.then((_) => _sync(config)).catchError((Object e) {
      Log.e(_tag, 'sync failed: $e');
    });
  }

  /// [sync] after a short pause, so typing a name restarts the service once.
  void scheduleSync(HubConfig config) {
    if (!_supported || _disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => sync(config));
  }

  Future<void> _sync(HubConfig config) async {
    if (!config.voiceSatelliteEnabled) {
      if (_applied != null) {
        await _methods.invokeMethod<void>('stop');
        _applied = null;
        _appliedMuted = null;
      }
      _emit(const VoiceSatelliteStatus());
      return;
    }

    var mac = config.voiceSatelliteMac;
    if (mac.isEmpty) {
      mac = generateMac(_random);
      await _config.update((c) => c.copyWith(voiceSatelliteMac: mac));
    }

    if (_appliedMuted != config.micMuted) {
      await _methods.invokeMethod<void>('setMuted', config.micMuted);
      _appliedMuted = config.micMuted;
    }

    final args = <String, Object>{
      'name': _nameFor(config),
      'mac': mac,
      'port': kVoiceSatellitePort,
      'wakeWords': config.voiceWakeWords,
      'sensitivity': config.voiceWakeSensitivity,
      'audioSource': config.voiceAudioSource,
      'wakeSound': config.voiceWakeSound,
    };
    if (_sameArgs(_applied, args)) return;

    // A start while running rebuilds the device with the new settings.
    final started = await _methods.invokeMethod<bool>('start', args) ?? false;
    // Recorded either way: a refused start (permission denied) is retried on
    // the next settings change or launch, not on every unrelated config write.
    _applied = args;
    _emit(_status.copyWith(running: started));
  }

  String _nameFor(HubConfig config) {
    final name = config.voiceSatelliteName.trim();
    if (name.isNotEmpty) return name;
    final host = _hostname().trim();
    // Android reports "localhost" for its own hostname.
    return host.isEmpty || host == 'localhost' ? 'Hearth' : host;
  }

  static bool _sameArgs(Map<String, Object>? a, Map<String, Object> b) {
    if (a == null) return false;
    for (final key in b.keys) {
      final x = a[key], y = b[key];
      if (x is List && y is List ? !listEquals(x, y) : x != y) return false;
    }
    return true;
  }

  /// Starts a conversation as if the wake word had fired.
  Future<void> wake() async {
    if (!_supported) return;
    await _methods.invokeMethod<void>('wake');
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'state':
        _emit(_status.copyWith(
          state: event['state'] as String? ?? 'idle',
          connected: event['connected'] as bool? ?? false,
        ));
      case 'health':
        final health = VoiceSatelliteHealth(
          event['code'] as String? ?? '',
          event['message'] as String? ?? '',
          DateTime.now(),
        );
        Log.w(_tag, 'health: ${health.code} ${health.message}');
        _emit(_status.copyWith(health: health));
      case 'settingChanged':
        unawaited(_onSettingChanged(event['setting'], event['value']));
    }
  }

  /// Home Assistant changed a setting on the running satellite. Record it as
  /// applied before saving, so the save is not mistaken for a user edit and
  /// answered with a restart.
  Future<void> _onSettingChanged(dynamic setting, dynamic value) async {
    switch (setting) {
      case 'mute' when value is bool:
        _appliedMuted = value;
        await _config.update((c) => c.copyWith(micMuted: value));
      case 'wakeSound' when value is bool:
        _applied?['wakeSound'] = value;
        await _config.update((c) => c.copyWith(voiceWakeSound: value));
      case 'wakeWords' when value is List:
        final words = value.whereType<String>().take(2).toList();
        if (words.isEmpty) return;
        _applied?['wakeWords'] = words;
        await _config.update((c) => c.copyWith(voiceWakeWords: words));
    }
  }

  void _emit(VoiceSatelliteStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Six random bytes as a colon-separated MAC, marked locally administered
  /// and unicast so it cannot collide with a vendor-assigned address.
  static String generateMac([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(6, (_) => r.nextInt(256));
    bytes[0] = (bytes[0] | 0x02) & 0xfe;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _eventSub?.cancel();
    _statusController.close();
  }
}

final voiceSatelliteBridgeProvider = Provider<VoiceSatelliteBridge>((ref) {
  final bridge = VoiceSatelliteBridge(ref.read(hubConfigProvider.notifier));
  unawaited(bridge.attach());
  unawaited(bridge.sync(ref.read(hubConfigProvider)));
  ref.listen<HubConfig>(hubConfigProvider, (_, c) => bridge.scheduleSync(c));
  ref.onDispose(bridge.dispose);
  return bridge;
});

final voiceSatelliteStatusProvider =
    StreamProvider<VoiceSatelliteStatus>((ref) {
  return ref.watch(voiceSatelliteBridgeProvider).statusStream;
});
