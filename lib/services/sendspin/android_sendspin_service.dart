import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

import '../../utils/logger.dart';
import 'sendspin_service.dart';

/// Stands in for the platform check in tests.
@visibleForTesting
bool? debugSendspinNativeOverride;

/// Whether Sendspin plays through the native player in `HearthAudioService`
/// rather than the Dart client. True on Android only.
///
/// `dart:io`, not `defaultTargetPlatform`: the latter reports Android under
/// `flutter test`.
bool get sendspinNative =>
    debugSendspinNativeOverride ?? (!kIsWeb && Platform.isAndroid);

/// A problem the native player reported: `listenerFailed`,
/// `advertiseFailed`, `serverLacksEncryption`, `dialledUnsupported` or
/// `secretsUnreadable`.
class SendspinHealth {
  final String code;
  final String message;
  final DateTime at;
  const SendspinHealth(this.code, this.message, this.at);

  String get label => switch (code) {
        'listenerFailed' => 'Could not listen for servers',
        'advertiseFailed' => 'Servers cannot discover this player',
        'serverLacksEncryption' => 'A server without encryption tried to connect',
        'dialledUnsupported' => 'Server URL is not supported on Android yet',
        'secretsUnreadable' => 'Pairing keys are unreadable',
        _ => code,
      };
}

/// The Android backend: SendspinDroid's player in `HearthAudioService`,
/// driven over `com.hearth/sendspin`.
///
/// The native side persists only the pairing secrets, so this is where its
/// settings meet `hub_config.json`: [configure] hands them over, and the
/// `outputDelay` and `lastPlaybackServer` events are written back through
/// the same callbacks the Dart client uses on the Pi. No Dart client, audio
/// sink, FLAC library or mDNS plugin is constructed here.
class AndroidSendspinService implements SendspinService {
  static const _tag = 'Sendspin';
  static const _defaultMethods = MethodChannel('com.hearth/sendspin');
  // A MethodChannel and an EventChannel cannot share a name.
  static const _defaultEvents = EventChannel('com.hearth/sendspin/events');

  /// One stream for every instance: the provider replaces the service on a
  /// settings change, and the old one's cancel must not race the new
  /// one's listen on the native side.
  static final Stream<dynamic> _sharedEvents =
      _defaultEvents.receiveBroadcastStream();

  final MethodChannel _methods;
  late final StreamSubscription<dynamic> _eventSub;

  AndroidSendspinService({MethodChannel? methods, Stream<dynamic>? events})
      : _methods = methods ?? _defaultMethods {
    _eventSub = (events ?? _sharedEvents).listen(_onEvent,
        onError: (Object e) => Log.e(_tag, 'Event stream error: $e'));
  }

  final _stateController = StreamController<SendspinPlayerState>.broadcast();
  SendspinPlayerState _state = const SendspinPlayerState();
  bool _enabled = false;

  void Function(int delayMs)? _onOutputDelayPersist;
  void Function(String serverId)? _onLastPlaybackServer;

  @override
  SendspinPlayerState get state => _state;

  @override
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  @override
  final ValueNotifier<SendspinPairingInfo?> pairingInfo = ValueNotifier(null);

  /// The last problem the native player reported since [configure].
  final ValueNotifier<SendspinHealth?> health = ValueNotifier(null);

  /// The device's media volume (`STREAM_MUSIC`), 0.0–1.0. Works whether or
  /// not Sendspin is running.
  static Future<double?> readMediaVolume({MethodChannel? methods}) async {
    try {
      return await (methods ?? _defaultMethods).invokeMethod<double>('getVolume');
    } catch (e) {
      Log.e(_tag, 'getVolume failed: $e');
      return null;
    }
  }

  /// Sets the media volume and, if a server is playing, tells it.
  static Future<void> setMediaVolume(double volume,
      {MethodChannel? methods}) async {
    try {
      await (methods ?? _defaultMethods).invokeMethod('setVolume', volume);
    } catch (e) {
      Log.e(_tag, 'setVolume failed: $e');
    }
  }

  @override
  void setVolume(double volume) {
    setMediaVolume(volume, methods: _methods);
  }

  /// Ignored: the audio coordinator mutes the engine natively at the wake
  /// word, one Home Assistant round trip before the ducker would.
  @override
  void setLocalDuckFactor(double factor) {}

  /// `bufferSeconds` and the stores are the Dart client's: the native engine
  /// has no buffer-length setting and keeps its own secrets.
  @override
  Future<void> configure({
    required bool enabled,
    required String playerName,
    required int bufferSeconds,
    required String serverUrl,
    bool unpairedAccess = true,
    int initialOutputDelayMs = 0,
    void Function(int delayMs)? onOutputDelayPersist,
    String lastPlaybackServerId = '',
    void Function(String serverId)? onLastPlaybackServer,
    SendspinIdentityStore? identityStore,
    SendspinPairingStore? pairingStore,
  }) async {
    _onOutputDelayPersist = onOutputDelayPersist;
    _onLastPlaybackServer = onLastPlaybackServer;
    _enabled = enabled && playerName.isNotEmpty;
    health.value = null;
    if (!_enabled) _updateState(const SendspinPlayerState());
    try {
      // Sent when disabled too: the native side stops the engine, and the
      // service if voice is off.
      await _methods.invokeMethod('configure', {
        'enabled': _enabled,
        'playerName': playerName,
        'serverUrl': serverUrl,
        'unpairedAccess': unpairedAccess,
        'outputDelayMs': initialOutputDelayMs,
        'lastPlaybackServerId': lastPlaybackServerId,
      });
    } catch (e) {
      Log.e(_tag, 'configure failed: $e');
      return;
    }
    if (_enabled) await _loadPairingInfo();
  }

  Future<void> _loadPairingInfo() async {
    try {
      final info =
          await _methods.invokeMapMethod<String, Object?>('pairingInfo');
      if (info == null) return;
      pairingInfo.value = SendspinPairingInfo(
        clientId: info['clientId'] as String? ?? '',
        pairingToken: info['pairingToken'] as String? ?? '',
        pairedServers: info['pairedServers'] as int? ?? 0,
      );
    } catch (e) {
      Log.e(_tag, 'pairingInfo failed: $e');
    }
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['event']) {
      case 'state':
        // The native side's last word on a player that has since been
        // switched off, replayed to a new listener.
        if (!_enabled) return;
        _updateState(stateFromEvent(raw));
        final paired = raw['pairedServers'];
        final info = pairingInfo.value;
        if (paired is int && info != null && paired != info.pairedServers) {
          _loadPairingInfo();
        }
      case 'outputDelay':
        final ms = raw['ms'];
        if (ms is int) _onOutputDelayPersist?.call(ms);
      case 'lastPlaybackServer':
        final id = raw['serverId'];
        if (id is String && id.isNotEmpty) _onLastPlaybackServer?.call(id);
      case 'health':
        final code = raw['code'];
        if (code is! String) return;
        final message = raw['message'] as String? ?? '';
        Log.w(_tag, 'Health: $code $message');
        health.value = SendspinHealth(code, message, DateTime.now());
    }
  }

  /// The `state` event as the type the Media screen and the slider read.
  @visibleForTesting
  static SendspinPlayerState stateFromEvent(Map<dynamic, dynamic> event) {
    final name = event['state'];
    final connection = SendspinConnectionState.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SendspinConnectionState.disconnected,
    );
    final meta = event['metadata'];
    final group = event['group'];
    return SendspinPlayerState(
      connectionState: connection,
      volume: (event['volume'] as num?)?.toDouble() ?? 1.0,
      muted: event['muted'] as bool? ?? false,
      codec: event['codec'] as String?,
      sampleRate: event['sampleRate'] as int?,
      channels: event['channels'] as int?,
      serverName: event['serverName'] as String?,
      bufferDepthMs: event['bufferDepthMs'] as int? ?? 0,
      clockOffsetMs: event['clockOffsetMs'] as int? ?? 0,
      outputDelayMs: event['outputDelayMs'] as int? ?? 0,
      metadata: meta is Map ? _metadata(meta) : null,
      groupState: group is Map
          ? SendspinGroupState(
              playbackState: group['playbackState'] is String
                  ? SendspinGroupPlaybackState.fromWire(
                      group['playbackState'] as String)
                  : null,
              groupId: group['id'] as String?,
              groupName: group['name'] as String?,
            )
          : const SendspinGroupState(),
    );
  }

  static SendspinMetadata _metadata(Map<dynamic, dynamic> meta) {
    final duration = meta['durationMs'], position = meta['positionMs'];
    return SendspinMetadata(
      title: meta['title'] as String?,
      artist: meta['artist'] as String?,
      album: meta['album'] as String?,
      artworkUrl: meta['artworkUrl'] as String?,
      progress: duration is int && duration > 0
          ? SendspinMetadataProgress(
              trackProgress: position is int ? position : 0,
              trackDuration: duration,
              playbackSpeed: meta['playbackSpeed'] as int? ?? 1000,
            )
          : null,
    );
  }

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// Leaves the native player as it is: the provider's replacement
  /// configures it next.
  @override
  Future<void> dispose() async {
    await _eventSub.cancel();
    await _stateController.close();
  }
}
