import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../app/current_screen_provider.dart';
import '../config/hub_config.dart';
import '../models/hearth_notification.dart';
import '../models/music_state.dart';
import '../modules/alarm_clock/alarm_models.dart';
import '../modules/alarm_clock/alarm_service.dart';
import '../utils/alsa_utils.dart';
import '../utils/logger.dart';
import 'music_assistant_service.dart';
import 'notification_service.dart';
import 'timer_service.dart';

/// Connection lifecycle of [MqttService], surfaced to the settings panel.
enum MqttStatus { disconnected, connecting, connected }

/// One Home Assistant MQTT discovery config message: the retained topic and
/// the JSON payload describing a single entity.
@immutable
class MqttDiscoveryEntry {
  final String topic;
  final Map<String, dynamic> config;
  const MqttDiscoveryEntry(this.topic, this.config);
}

/// Exposes Hearth to Home Assistant as a single MQTT device via the
/// [HA MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
/// protocol.
///
/// Lifecycle mirrors [MusicAssistantService]: it watches the `mqtt*` config
/// fields, connects when a broker URL is set, disconnects when it is cleared,
/// and reconnects with exponential backoff on an unexpected drop. When no
/// broker is configured it is a complete no-op.
///
/// On connect it publishes retained discovery payloads (one shared Hearth
/// device-identity block across every entity), publishes current state for
/// each read entity, and subscribes to the command topics that drive Hearth
/// from HA (volume, timers, alarms). State is republished whenever the
/// underlying service reports a change.
class MqttService extends ChangeNotifier {
  MqttService(this._ref);

  final Ref _ref;

  MqttServerClient? _client;
  MqttStatus _status = MqttStatus.disconnected;
  MqttStatus get status => _status;
  bool get isConnected => _status == MqttStatus.connected;

  // Applied config snapshot — compared on updateConfig to decide whether to
  // reconnect, republish discovery, or do nothing.
  String _brokerUrl = '';
  String _username = '';
  String _password = '';
  String _discoveryPrefix = 'homeassistant';
  String _swVersion = '';

  late final String _clientId = computeClientId();

  Timer? _reconnectTimer;
  int _reconnectDelay = 1;
  static const int _maxReconnectDelay = 30;
  bool _disposed = false;

  StreamSubscription<MusicPlayerState>? _playerSub;

  // Last-published change signatures, used to suppress republishing when the
  // source notifies (e.g. the 200ms timer ticker) without a meaningful change.
  String? _lastTimerSig;
  String? _lastAlarmSig;

  // Serializes inbound volume commands so concurrent amixer subprocesses can't
  // interleave and leave ALSA / the published state at the wrong value.
  Future<void> _volumeChain = Future.value();

  // --- Config-driven lifecycle ---------------------------------------------

  /// React to a config change: connect, disconnect, reconnect, or republish
  /// discovery as appropriate. Called with `fireImmediately` on creation.
  void updateConfig(HubConfig config) {
    if (kIsWeb) return; // The MQTT client is native-only.
    _swVersion = readInstalledVersion(fallback: config.currentVersion);
    final url = config.mqttBrokerUrl.trim();
    final user = config.mqttUsername;
    final pass = config.mqttPassword;
    final prefix = config.mqttDiscoveryPrefix.isEmpty
        ? 'homeassistant'
        : config.mqttDiscoveryPrefix;

    if (url.isEmpty) {
      // Integration turned off — tear down and stay quiet.
      _brokerUrl = '';
      if (_client != null || _status != MqttStatus.disconnected) {
        _disconnect();
      }
      return;
    }

    final connectionChanged =
        url != _brokerUrl || user != _username || pass != _password;
    final prefixChanged = prefix != _discoveryPrefix;

    _brokerUrl = url;
    _username = user;
    _password = pass;
    _discoveryPrefix = prefix;

    if (connectionChanged) {
      _reconnectDelay = 1;
      _connect();
    } else if (prefixChanged && isConnected) {
      // Discovery topics are keyed by prefix — republish under the new one.
      _publishDiscovery();
      _publishAllState();
    }
  }

  /// (Re)subscribe to the Music Assistant player stream. Called whenever the
  /// MA service instance is (re)created so now-playing keeps flowing.
  void attachMusicAssistant(MusicAssistantService ma) {
    _playerSub?.cancel();
    _playerSub = ma.playerStateStream.listen((_) => onNowPlayingChanged());
  }

  Future<void> _connect() async {
    if (_disposed || kIsWeb || _brokerUrl.isEmpty) return;
    await _teardownClient();
    _reconnectTimer?.cancel();

    final broker = parseBroker(_brokerUrl);
    _setStatus(MqttStatus.connecting);

    final client =
        MqttServerClient.withPort(broker.host, _clientId, broker.port)
          ..secure = broker.secure
          ..keepAlivePeriod = 30
          ..autoReconnect = false
          ..setProtocolV311()
          ..logging(on: false)
          ..onDisconnected = _onDisconnected
          ..connectionMessage = MqttConnectMessage()
              .withClientIdentifier(_clientId)
              .startClean();
    if (broker.secure) {
      // LAN brokers commonly use self-signed certs.
      client.onBadCertificate = (Object cert) => true;
    }
    _client = client;

    try {
      await client.connect(
        _username.isEmpty ? null : _username,
        _password.isEmpty ? null : _password,
      );
    } catch (e) {
      Log.w('MQTT', 'Connect failed: $e');
      _abandonClient(client);
      // Only drive reconnect if a newer _connect() hasn't superseded us.
      if (_client == client) {
        _client = null;
        _setStatus(MqttStatus.disconnected);
        _scheduleReconnect();
      }
      return;
    }

    // A concurrent _connect() (e.g. another config change) took over while we
    // awaited — abandon this attempt and let the newer one own the lifecycle.
    if (_client != client) {
      _abandonClient(client);
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      Log.w('MQTT', 'Connect incomplete: ${client.connectionStatus}');
      _abandonClient(client);
      _client = null;
      _setStatus(MqttStatus.disconnected);
      _scheduleReconnect();
      return;
    }

    _reconnectDelay = 1;
    _setStatus(MqttStatus.connected);
    Log.i('MQTT', 'Connected to ${broker.host}:${broker.port} as $_clientId');

    client.updates?.listen(_onMessage);
    _publishDiscovery();
    _subscribeCommands();
    await _publishAllState();
  }

  void _onDisconnected() {
    if (_disposed) return;
    Log.w('MQTT', 'Disconnected');
    _setStatus(MqttStatus.disconnected);
    if (_brokerUrl.isNotEmpty) _scheduleReconnect();
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownClient();
    _setStatus(MqttStatus.disconnected);
  }

  /// Drop the current client without scheduling a reconnect (its
  /// `onDisconnected` is detached first so the drop is silent).
  Future<void> _teardownClient() async {
    final c = _client;
    _client = null;
    if (c != null) _abandonClient(c);
  }

  /// Detach the disconnect handler and close a specific client. Used for the
  /// shared `_client` (via [_teardownClient]) and for abandoning a superseded
  /// connect attempt without touching `_client`.
  void _abandonClient(MqttServerClient client) {
    client.onDisconnected = null;
    try {
      client.disconnect();
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_disposed || _brokerUrl.isEmpty) return;
    _reconnectTimer?.cancel();
    Log.w('MQTT', 'Reconnecting in ${_reconnectDelay}s...');
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 2).clamp(1, _maxReconnectDelay);
      _connect();
    });
  }

  void _setStatus(MqttStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  // --- Topics ---------------------------------------------------------------

  String get _baseTopic => 'hearth/$_clientId';
  String _stateTopic(String entity) => '$_baseTopic/$entity/state';
  String _attrTopic(String entity) => '$_baseTopic/$entity/attributes';

  String get _volumeCmdTopic => '$_baseTopic/volume/set';
  String get _timerStartTopic => '$_baseTopic/timer/start';
  String get _timerCancelTopic => '$_baseTopic/timer/cancel';
  String get _alarmCreateTopic => '$_baseTopic/alarm/create';
  String get _alarmDeleteTopic => '$_baseTopic/alarm/delete';
  String get _alarmSnoozeTopic => '$_baseTopic/alarm/snooze';
  String get _alarmDismissTopic => '$_baseTopic/alarm/dismiss';
  String get _notifyTopic => '$_baseTopic/notify';

  String get _configurationUrl {
    var host = 'hearth';
    if (!kIsWeb) {
      try {
        host = Platform.localHostname;
      } catch (_) {}
    }
    return 'http://$host:8090';
  }

  // --- Discovery ------------------------------------------------------------

  void _publishDiscovery() {
    final entries = buildDiscoveryEntries(
      clientId: _clientId,
      discoveryPrefix: _discoveryPrefix,
      swVersion: _swVersion,
      configurationUrl: _configurationUrl,
    );
    for (final e in entries) {
      _publish(e.topic, jsonEncode(e.config));
    }
  }

  // --- State publishing -----------------------------------------------------

  Future<void> _publishAllState() async {
    _lastTimerSig = null;
    _lastAlarmSig = null;
    onCurrentScreenChanged(_ref.read(currentScreenProvider));
    onNowPlayingChanged();
    onTimerChanged();
    onAlarmChanged();
    await publishVolume();
  }

  void onCurrentScreenChanged(CurrentScreen screen) {
    _publish(_stateTopic('current_screen'), screen.id);
    _publish(_attrTopic('current_screen'),
        jsonEncode({'screen_index': screen.index}));
  }

  void onNowPlayingChanged() {
    final players = _ref.read(musicAssistantServiceProvider).playerStates;
    final np = _computeNowPlaying(players);
    _publish(_stateTopic('now_playing'), np.state);
    _publish(_attrTopic('now_playing'), jsonEncode(np.attrs));
  }

  ({String state, Map<String, dynamic> attrs}) _computeNowPlaying(
      Map<String, MusicPlayerState> players) {
    MusicPlayerState? chosen;
    for (final p in players.values) {
      if (p.isPlaying && p.currentTrack != null) {
        chosen = p;
        break;
      }
    }
    if (chosen == null) {
      for (final p in players.values) {
        if (p.currentTrack != null) {
          chosen = p;
          break;
        }
      }
    }
    final track = chosen?.currentTrack;
    if (track == null) {
      return (
        state: 'idle',
        attrs: {
          'artist': null,
          'album': null,
          'player_id': null,
          'playback_state': 'idle',
        },
      );
    }
    return (
      state: track.title,
      attrs: {
        'artist': track.artist,
        'album': track.album,
        'player_id': chosen!.activeZoneId,
        'playback_state': chosen.playbackState.name,
      },
    );
  }

  void onTimerChanged() {
    final ts = _ref.read(timerServiceProvider);
    final active = ts.timers;
    HubTimer? soonest;
    for (final t in active) {
      if (soonest == null || t.remaining < soonest.remaining) soonest = t;
    }
    final remaining = soonest?.remaining.inSeconds;
    // The 200ms ticker notifies far too often to forward raw. Bucket the
    // soonest remaining by 30s so a counting-down timer republishes at most
    // ~once per 30s — fresh enough for HA automations, without flooding.
    final sig = '${active.length}|${ts.hasActiveTimers}|${ts.firedTimers.length}'
        '|${remaining == null ? '' : remaining ~/ 30}';
    if (sig == _lastTimerSig) return;
    _lastTimerSig = sig;

    final state = ts.hasActiveTimers
        ? 'active'
        : (ts.firedTimers.isNotEmpty ? 'fired' : 'idle');
    _publish(_stateTopic('timer'), state);
    _publish(
      _attrTopic('timer'),
      jsonEncode({
        'count': active.length,
        'fired': ts.firedTimers.length,
        'remaining_seconds': remaining,
        'remaining': soonest?.remainingLabel,
      }),
    );
  }

  void onAlarmChanged() {
    final as = _ref.read(alarmServiceProvider);
    final na = as.nextAlarm;
    final sig =
        na == null ? 'none' : '${na.$1.id}|${na.$2.toIso8601String()}';
    if (sig == _lastAlarmSig) return;
    _lastAlarmSig = sig;

    if (na == null) {
      _publish(_stateTopic('next_alarm'), 'none');
      _publish(
        _attrTopic('next_alarm'),
        jsonEncode(
            {'label': null, 'days_summary': null, 'sunrise_enabled': false}),
      );
      return;
    }
    final (alarm, fireTime) = na;
    _publish(_stateTopic('next_alarm'), fireTime.toIso8601String());
    _publish(
      _attrTopic('next_alarm'),
      jsonEncode({
        'label': alarm.label,
        'days_summary': alarm.daySummary,
        'sunrise_enabled': alarm.sunriseDuration > 0,
      }),
    );
  }

  /// Read the live ALSA Master volume and publish it as the number state.
  Future<void> publishVolume() async {
    final v = await getMasterVolume();
    if (v == null) return;
    _publish(_stateTopic('volume'), v.toString());
  }

  void _publish(String topic, String payload, {bool retain = true}) {
    final c = _client;
    if (c == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    c.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
        retain: retain);
  }

  // --- Inbound commands -----------------------------------------------------

  void _subscribeCommands() {
    final c = _client;
    if (c == null) return;
    for (final topic in [
      _volumeCmdTopic,
      _timerStartTopic,
      _timerCancelTopic,
      _alarmCreateTopic,
      _alarmDeleteTopic,
      _alarmSnoozeTopic,
      _alarmDismissTopic,
      _notifyTopic,
    ]) {
      c.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> events) {
    for (final event in events) {
      final pub = event.payload;
      if (pub is! MqttPublishMessage) continue;
      final payload =
          MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      handleCommand(event.topic, payload);
    }
  }

  /// Dispatch one inbound command to the relevant Hearth service. Split out
  /// (and `@visibleForTesting`) so command handling can be exercised against
  /// real TimerService/AlarmService instances without a live broker.
  @visibleForTesting
  Future<void> handleCommand(String topic, String payload) async {
    try {
      if (topic == _volumeCmdTopic) {
        await _handleVolumeCommand(payload);
      } else if (topic == _timerStartTopic) {
        _handleTimerStart(payload);
      } else if (topic == _timerCancelTopic) {
        _handleTimerCancel(payload);
      } else if (topic == _alarmCreateTopic) {
        _handleAlarmCreate(payload);
      } else if (topic == _alarmDeleteTopic) {
        _handleAlarmDelete(payload);
      } else if (topic == _alarmSnoozeTopic) {
        _ref.read(alarmServiceProvider).snooze();
      } else if (topic == _alarmDismissTopic) {
        _ref.read(alarmServiceProvider).dismiss();
      } else if (topic == _notifyTopic) {
        _handleNotify(payload);
      } else {
        Log.w('MQTT', 'Unhandled command topic: $topic');
      }
    } catch (e) {
      Log.w('MQTT', 'Command handling failed ($topic): $e');
    }
  }

  Future<void> _handleVolumeCommand(String payload) {
    final v = int.tryParse(payload.trim());
    if (v == null) {
      Log.w('MQTT', 'Bad volume payload: $payload');
      return Future.value();
    }
    // Chain onto any in-flight volume write so they apply in arrival order;
    // the catchError keeps the chain alive if a write ever throws.
    _volumeChain = _volumeChain.then((_) async {
      await setMasterVolume(v);
      await publishVolume();
    }).catchError((Object e) {
      Log.w('MQTT', 'Volume command failed: $e');
    });
    return _volumeChain;
  }

  void _handleTimerStart(String payload) {
    final data = _decodeJson(payload);
    final seconds = (data['duration'] as num?)?.round();
    if (seconds == null || seconds <= 0) {
      Log.w('MQTT', 'Bad timer duration: $payload');
      return;
    }
    _ref.read(timerServiceProvider).startTimer(Duration(seconds: seconds));
  }

  void _handleTimerCancel(String payload) {
    final ts = _ref.read(timerServiceProvider);
    final data = _decodeJson(payload);
    final id = (data['timer_id'] as num?)?.toInt();
    if (id != null) {
      final exists = ts.timers.any((t) => t.id == id) ||
          ts.firedTimers.any((t) => t.id == id);
      if (exists) ts.dismissTimer(id);
      return;
    }
    // No id — dismiss the most-recently-started active timer, else clear fired.
    final active = [...ts.timers]..sort((a, b) => b.id.compareTo(a.id));
    if (active.isNotEmpty) {
      ts.dismissTimer(active.first.id);
    } else if (ts.firedTimers.isNotEmpty) {
      ts.dismissAllFired();
    }
  }

  void _handleAlarmCreate(String payload) {
    final data = _decodeJson(payload);
    final time = data['time'] as String?;
    if (time == null || time.isEmpty) {
      Log.w('MQTT', 'Alarm create missing time: $payload');
      return;
    }
    final days = (data['days'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const <int>[];
    // Reuse Alarm.fromJson so the id is generated and defaults are applied.
    final alarm = Alarm.fromJson({
      'time': time,
      'label': data['label'],
      'days': days,
      if (data['sunrise_duration'] != null)
        'sunriseDuration': (data['sunrise_duration'] as num).toInt(),
    });
    _ref.read(alarmServiceProvider).addAlarm(alarm);
  }

  /// Normalize an inbound notification payload and surface it as a deck card.
  /// HA publishes to `hearth/<clientId>/notify` via the built-in `notify.mqtt`
  /// integration; a `command_template` shapes the JSON (see below). Shares the
  /// normalize path (`HearthNotification.fromIngest`) with `POST /api/notify`.
  ///
  /// Payload schema (all optional except one of title/message):
  /// ```json
  /// {"title": "...", "message": "...", "priority": "alert"|"info",
  ///  "sticky": true|false, "source": "...", "source_label": "...",
  ///  "muted": true|false}
  /// ```
  ///
  /// Example HA `notify.mqtt` config:
  /// ```yaml
  /// notify:
  ///   - platform: mqtt
  ///     name: hearth
  ///     command_topic: "hearth/<clientId>/notify"
  ///     command_template: >-
  ///       {"title": {{ title | to_json }}, "message": {{ message | to_json }},
  ///        "priority": "{{ data.priority | default('info') }}",
  ///        "sticky": {{ data.sticky | default(false) | to_json }}}
  /// ```
  void _handleNotify(String payload) {
    final notification = HearthNotification.fromIngest(_decodeJson(payload));
    if (notification == null) {
      Log.w('MQTT', 'Notify payload has no title/message: $payload');
      return;
    }
    _ref.read(notificationServiceProvider).ingest(notification);
  }

  void _handleAlarmDelete(String payload) {
    final data = _decodeJson(payload);
    final id = data['alarm_id'] as String?;
    if (id == null || id.isEmpty) {
      Log.w('MQTT', 'Alarm delete missing alarm_id: $payload');
      return;
    }
    _ref.read(alarmServiceProvider).deleteAlarm(id);
  }

  Map<String, dynamic> _decodeJson(String payload) {
    if (payload.trim().isEmpty) return const {};
    try {
      final v = jsonDecode(payload);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _playerSub?.cancel();
    _teardownClient();
    super.dispose();
  }

  // --- Pure, testable helpers ----------------------------------------------

  /// Build the HA discovery config entries for every entity this integration
  /// exposes. All entries share one device-identity block so HA groups them
  /// under a single "Hearth" device.
  @visibleForTesting
  static List<MqttDiscoveryEntry> buildDiscoveryEntries({
    required String clientId,
    required String discoveryPrefix,
    required String swVersion,
    required String configurationUrl,
  }) {
    final base = 'hearth/$clientId';
    final device = <String, dynamic>{
      'identifiers': ['hearth_$clientId'],
      'name': 'Hearth',
      'model': 'Hearth Kiosk',
      'manufacturer': 'Hearth',
      'sw_version': swVersion.isEmpty ? 'unknown' : swVersion,
      'configuration_url': configurationUrl,
    };

    String topic(String component, String entity) =>
        '$discoveryPrefix/$component/hearth_$clientId/$entity/config';
    String uid(String entity) => 'hearth_${clientId}_$entity';

    MqttDiscoveryEntry sensor(
      String entity,
      String name,
      String icon,
    ) =>
        MqttDiscoveryEntry(topic('sensor', entity), {
          'name': name,
          'unique_id': uid(entity),
          'state_topic': '$base/$entity/state',
          'json_attributes_topic': '$base/$entity/attributes',
          'icon': icon,
          'device': device,
        });

    return [
      sensor('current_screen', 'Current Screen', 'mdi:monitor-dashboard'),
      sensor('now_playing', 'Now Playing', 'mdi:music'),
      sensor('timer', 'Timer', 'mdi:timer-outline'),
      sensor('next_alarm', 'Next Alarm', 'mdi:alarm'),
      MqttDiscoveryEntry(topic('number', 'volume'), {
        'name': 'Volume',
        'unique_id': uid('volume'),
        'state_topic': '$base/volume/state',
        'command_topic': '$base/volume/set',
        'min': 0,
        'max': 100,
        'step': 1,
        'mode': 'slider',
        'unit_of_measurement': '%',
        'icon': 'mdi:volume-high',
        'device': device,
      }),
    ];
  }

  /// Parse a broker URL into host/port/secure. Accepts bare `host`,
  /// `host:port`, and scheme-prefixed forms (`mqtt://`, `mqtts://`,
  /// `tcp://`, `ssl://`). Defaults to port 1883 (8883 when secure).
  @visibleForTesting
  static ({String host, int port, bool secure}) parseBroker(String url) {
    var u = url.trim();
    var secure = false;
    final scheme = RegExp(r'^([a-zA-Z]+)://').firstMatch(u);
    if (scheme != null) {
      final s = scheme.group(1)!.toLowerCase();
      secure = s == 'mqtts' || s == 'ssl' || s == 'tls' || s == 'wss';
      u = u.substring(scheme.end);
    }
    u = u.split('/').first; // strip any trailing path
    var host = u;
    var port = secure ? 8883 : 1883;
    final colon = u.lastIndexOf(':');
    if (colon > 0) {
      final maybePort = int.tryParse(u.substring(colon + 1));
      if (maybePort != null) {
        host = u.substring(0, colon);
        port = maybePort;
      }
    }
    if (host.isEmpty) host = 'localhost';
    return (host: host, port: port, secure: secure);
  }

  /// The running Hearth version, reported to HA as the device firmware
  /// (`sw_version`). Reads `/etc/hearth-version` — the file the installer and
  /// OTA updater maintain, and the same source Settings → Updates displays —
  /// so the HA "firmware" stays in lockstep with the installed bundle. Returns
  /// [fallback] when the file is absent (Windows dev) or unreadable.
  @visibleForTesting
  static String readInstalledVersion({String fallback = ''}) {
    if (kIsWeb) return fallback;
    try {
      final v = File('/etc/hearth-version').readAsStringSync().trim();
      if (v.isNotEmpty) return v;
    } catch (_) {}
    return fallback;
  }

  /// A stable client identifier derived from the device hostname, sanitized
  /// to `[a-z0-9_]`. Used both as the MQTT client id and the HA device id.
  @visibleForTesting
  static String computeClientId() {
    var h = 'hearth';
    if (!kIsWeb) {
      try {
        h = Platform.localHostname;
      } catch (_) {}
    }
    h = h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (h.isEmpty || h == '_') h = 'hearth';
    return h;
  }
}

/// MqttService is created once and pushed config/state changes; it is never
/// recreated by Riverpod (nothing is `watch`ed here), so the live connection
/// survives unrelated config edits.
final mqttServiceProvider = ChangeNotifierProvider<MqttService>((ref) {
  // ChangeNotifierProvider disposes the notifier automatically (which cancels
  // the reconnect timer, MA subscription, and client) — no explicit onDispose.
  final service = MqttService(ref);

  // Connect/disconnect/reconnect on config changes.
  ref.listen<HubConfig>(
    hubConfigProvider,
    (_, next) => service.updateConfig(next),
    fireImmediately: true,
  );

  // Current-screen sensor: publish on page change.
  ref.listen<CurrentScreen>(
    currentScreenProvider,
    (_, next) => service.onCurrentScreenChanged(next),
  );

  // Timer + alarm sensors: read the stable notifier and listen directly
  // (watching a ChangeNotifierProvider here would recreate the service on
  // every notify).
  final timer = ref.read(timerServiceProvider);
  timer.addListener(service.onTimerChanged);
  ref.onDispose(() => timer.removeListener(service.onTimerChanged));

  final alarm = ref.read(alarmServiceProvider);
  alarm.addListener(service.onAlarmChanged);
  ref.onDispose(() => alarm.removeListener(service.onAlarmChanged));

  // Now-playing sensor: re-attach the MA stream whenever the MA service is
  // (re)created so it keeps flowing across MA reconnects.
  ref.listen<MusicAssistantService>(
    musicAssistantServiceProvider,
    (_, next) => service.attachMusicAssistant(next),
    fireImmediately: true,
  );

  return service;
});
