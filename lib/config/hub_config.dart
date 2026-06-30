import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'webview_config.dart';

// dart:io and path_provider compile to stubs on web — guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Sentinel value for copyWith to distinguish "not provided" from "set to null".
const _undefined = Object();

enum TouchIndicatorStyle { ripple, solid, trail }

/// Configuration for the on-screen touch indicator overlay.
///
/// Not persisted separately — lives as a nested object inside [HubConfig].
/// Intended for marketing captures; defaults are "off" so production kiosks
/// are unaffected.
class TouchIndicatorConfig {
  final bool enabled;
  final int colorArgb;
  final double radius;
  final int fadeMs;
  final TouchIndicatorStyle style;

  const TouchIndicatorConfig({
    this.enabled = false,
    this.colorArgb = 0x80FFFFFF,
    this.radius = 40.0,
    this.fadeMs = 600,
    this.style = TouchIndicatorStyle.ripple,
  });

  TouchIndicatorConfig copyWith({
    bool? enabled,
    int? colorArgb,
    double? radius,
    int? fadeMs,
    TouchIndicatorStyle? style,
  }) {
    return TouchIndicatorConfig(
      enabled: enabled ?? this.enabled,
      colorArgb: colorArgb ?? this.colorArgb,
      radius: radius ?? this.radius,
      fadeMs: fadeMs ?? this.fadeMs,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'colorArgb': colorArgb,
        'radius': radius,
        'fadeMs': fadeMs,
        'style': style.name,
      };

  factory TouchIndicatorConfig.fromJson(Map<String, dynamic> json) {
    final styleName = json['style'] as String?;
    final style = TouchIndicatorStyle.values.firstWhere(
      (s) => s.name == styleName,
      orElse: () => TouchIndicatorStyle.ripple,
    );
    return TouchIndicatorConfig(
      enabled: json['enabled'] as bool? ?? false,
      colorArgb: json['colorArgb'] as int? ?? 0x80FFFFFF,
      radius: (json['radius'] as num?)?.toDouble() ?? 40.0,
      fadeMs: json['fadeMs'] as int? ?? 600,
      style: style,
    );
  }
}

/// Configuration for which Immich photo sources feed the ambient carousel.
///
/// Sources are stackable: each enabled source contributes up to 50 photos,
/// and the union is shuffled into the rotation. Unconfigured-but-enabled
/// sources (e.g. albumEnabled true but albumId empty) contribute zero.
///
/// Default state matches the pre-multi-source behavior: Memories only.
class PhotoSourcesConfig {
  final bool memoriesEnabled;
  final bool albumEnabled;
  final String albumId;
  final bool peopleEnabled;
  final List<String> personIds;
  final bool smartSearchEnabled;
  final String smartSearchQuery;

  const PhotoSourcesConfig({
    this.memoriesEnabled = true,
    this.albumEnabled = false,
    this.albumId = '',
    this.peopleEnabled = false,
    this.personIds = const [],
    this.smartSearchEnabled = false,
    this.smartSearchQuery = '',
  });

  PhotoSourcesConfig copyWith({
    bool? memoriesEnabled,
    bool? albumEnabled,
    String? albumId,
    bool? peopleEnabled,
    List<String>? personIds,
    bool? smartSearchEnabled,
    String? smartSearchQuery,
  }) {
    return PhotoSourcesConfig(
      memoriesEnabled: memoriesEnabled ?? this.memoriesEnabled,
      albumEnabled: albumEnabled ?? this.albumEnabled,
      albumId: albumId ?? this.albumId,
      peopleEnabled: peopleEnabled ?? this.peopleEnabled,
      personIds: personIds ?? this.personIds,
      smartSearchEnabled: smartSearchEnabled ?? this.smartSearchEnabled,
      smartSearchQuery: smartSearchQuery ?? this.smartSearchQuery,
    );
  }

  Map<String, dynamic> toJson() => {
        'memoriesEnabled': memoriesEnabled,
        'albumEnabled': albumEnabled,
        'albumId': albumId,
        'peopleEnabled': peopleEnabled,
        'personIds': personIds,
        'smartSearchEnabled': smartSearchEnabled,
        'smartSearchQuery': smartSearchQuery,
      };

  factory PhotoSourcesConfig.fromJson(Map<String, dynamic> json) =>
      PhotoSourcesConfig(
        memoriesEnabled: json['memoriesEnabled'] as bool? ?? true,
        albumEnabled: json['albumEnabled'] as bool? ?? false,
        albumId: json['albumId'] as String? ?? '',
        peopleEnabled: json['peopleEnabled'] as bool? ?? false,
        personIds: (json['personIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        smartSearchEnabled: json['smartSearchEnabled'] as bool? ?? false,
        smartSearchQuery: json['smartSearchQuery'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoSourcesConfig &&
          memoriesEnabled == other.memoriesEnabled &&
          albumEnabled == other.albumEnabled &&
          albumId == other.albumId &&
          peopleEnabled == other.peopleEnabled &&
          listEquals(personIds, other.personIds) &&
          smartSearchEnabled == other.smartSearchEnabled &&
          smartSearchQuery == other.smartSearchQuery;

  @override
  int get hashCode => Object.hash(
        memoriesEnabled,
        albumEnabled,
        albumId,
        peopleEnabled,
        Object.hashAll(personIds),
        smartSearchEnabled,
        smartSearchQuery,
      );
}

/// Central configuration for a single Home Hub device.
///
/// Each hub stores its own config locally — there's no shared backend.
/// On native platforms, values persist as JSON in the app support directory.
/// On web, config lives only in memory (session-only "try before you buy").
///
/// Note: All configuration including API keys and tokens is stored as
/// plaintext JSON in the app support directory. On the Pi, restrict
/// file permissions: `chmod 600 hub_config.json`.
/// See https://registry.home.chrisuthe.com/chris/Hearth/issues/47
class HubConfig {
  final String apiKey;
  final String immichUrl;
  final String immichApiKey;
  final String haUrl;
  final String haToken;
  final String musicAssistantUrl;
  final String musicAssistantToken;
  final String frigateUrl;
  final String frigateUsername;
  final String frigatePassword;
  final int idleTimeoutSeconds;
  final String nightModeSource; // "ha_entity" | "api" | "clock" | "none"
  final String? nightModeHaEntity;
  final String? nightModeClockStart;
  final String? nightModeClockEnd;
  final String? defaultMusicZone;
  final bool use24HourClock;
  final List<String> pinnedEntityIds;
  final String weatherEntityId;
  /// HA assist_satellite entity ID to lock onto for the voice pill UI.
  /// Empty string means "auto-pick the first available" (legacy behavior,
  /// fine for single-Hearth setups). When multiple voice satellites exist
  /// on the same HA — multiple Hearth kiosks, a Voice PE, additional LVA
  /// devices — set this explicitly so each kiosk only reflects its own
  /// satellite's state instead of grabbing whichever entity loads first.
  final String voiceAssistantEntityId;
  final bool sendspinEnabled;
  final String sendspinPlayerName;
  final int sendspinBufferSeconds;
  final String sendspinClientId;
  final String sendspinServerUrl;
  final int sendspinStaticDelayMs;
  /// Wire value for [OnScreenKeyboardMode]: 'auto', 'always', or 'never'.
  final String onScreenKeyboardMode;
  final String displayProfile; // "auto" | "amoled-11" | "rpi-7" | "hdmi"
  final int displayWidth;      // 0 = use profile default
  final int displayHeight;     // 0 = use profile default
  final List<String> enabledModules;
  final Map<String, List<String>> modulePlacements;
  final String mealieUrl;
  final String mealieToken;
  // MQTT discovery: exposes Hearth as a Home Assistant device. Empty broker
  // URL means the integration is off (MqttService is a complete no-op).
  final String mqttBrokerUrl;
  final String mqttUsername;
  final String mqttPassword;
  final String mqttDiscoveryPrefix;
  final bool setupComplete;
  final bool autoUpdate;
  final String updateSource; // 'github' or 'gitea'
  final String giteaApiToken;
  final String currentVersion;
  final List<String> moduleOrder;  // custom screen order (module IDs); empty = use defaultOrder
  final String timezone;           // IANA timezone (e.g. "America/New_York"); empty = system default
  final String topSwipeAction;    // "menu1" | "menu2" | "settings" | "nextScreen" | "previousScreen"
  final String bottomSwipeAction; // "menu1" | "menu2" | "settings" | "nextScreen" | "previousScreen"
  final bool showVoiceFeedback;
  final bool micMuted;
  final TouchIndicatorConfig touchIndicator;
  /// Master toggle for developer capture tools (screenshots, recording, touch
  /// indicators). Gates the Capture plugin: when false it's hidden from the
  /// sidebar on both surfaces and its `/api/plugin/hearth.capture/*` routes
  /// return 404. The toggle itself lives in the System plugin.
  final bool captureToolsEnabled;

  final PhotoSourcesConfig photoSources;

  /// Global UI scale multiplier. 1.0 = no change. Range [0.75, 1.5],
  /// clamped on load. The HearthScaleScope at the app root reads this
  /// to drive a uniform Transform.scale + MediaQuery.size override.
  final double uiScale;

  /// User-configured webview screens (HA dashboards + custom URLs) that appear
  /// as additional pages in HubShell's PageView via the webview module.
  final List<WebviewConfig> webviews;

  const HubConfig({
    this.apiKey = '',
    this.immichUrl = '',
    this.immichApiKey = '',
    this.haUrl = '',
    this.haToken = '',
    this.musicAssistantUrl = '',
    this.musicAssistantToken = '',
    this.frigateUrl = '',
    this.frigateUsername = '',
    this.frigatePassword = '',
    this.idleTimeoutSeconds = 120,
    this.nightModeSource = 'none',
    this.nightModeHaEntity,
    this.nightModeClockStart,
    this.nightModeClockEnd,
    this.defaultMusicZone,
    this.use24HourClock = false,
    this.pinnedEntityIds = const [],
    this.weatherEntityId = '',
    this.voiceAssistantEntityId = '',
    this.sendspinEnabled = false,
    this.sendspinPlayerName = '',
    this.sendspinBufferSeconds = 5,
    this.sendspinClientId = '',
    this.sendspinServerUrl = '',
    this.sendspinStaticDelayMs = 0,
    this.onScreenKeyboardMode = 'auto',
    this.displayProfile = 'auto',
    this.displayWidth = 0,
    this.displayHeight = 0,
    this.enabledModules = const ['media', 'controls', 'cameras'],
    this.modulePlacements = const {},
    this.mealieUrl = '',
    this.mealieToken = '',
    this.mqttBrokerUrl = '',
    this.mqttUsername = '',
    this.mqttPassword = '',
    this.mqttDiscoveryPrefix = 'homeassistant',
    this.setupComplete = false,
    this.autoUpdate = true,
    this.updateSource = 'github',
    this.giteaApiToken = '',
    this.currentVersion = '',
    this.moduleOrder = const [],
    this.timezone = '',
    this.topSwipeAction = 'menu2',
    this.bottomSwipeAction = 'menu1',
    this.showVoiceFeedback = true,
    this.micMuted = false,
    this.touchIndicator = const TouchIndicatorConfig(),
    this.captureToolsEnabled = false,
    this.photoSources = const PhotoSourcesConfig(),
    this.uiScale = 1.0,
    this.webviews = const [],
  });

  static String generateApiKey() {
    final rng = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  HubConfig copyWith({
    String? apiKey,
    String? immichUrl,
    String? immichApiKey,
    String? haUrl,
    String? haToken,
    String? musicAssistantUrl,
    String? musicAssistantToken,
    String? frigateUrl,
    String? frigateUsername,
    String? frigatePassword,
    int? idleTimeoutSeconds,
    String? nightModeSource,
    Object? nightModeHaEntity = _undefined,
    Object? nightModeClockStart = _undefined,
    Object? nightModeClockEnd = _undefined,
    Object? defaultMusicZone = _undefined,
    bool? use24HourClock,
    List<String>? pinnedEntityIds,
    String? weatherEntityId,
    String? voiceAssistantEntityId,
    bool? sendspinEnabled,
    String? sendspinPlayerName,
    int? sendspinBufferSeconds,
    String? sendspinClientId,
    String? sendspinServerUrl,
    int? sendspinStaticDelayMs,
    String? onScreenKeyboardMode,
    String? displayProfile,
    int? displayWidth,
    int? displayHeight,
    List<String>? enabledModules,
    Map<String, List<String>>? modulePlacements,
    String? mealieUrl,
    String? mealieToken,
    String? mqttBrokerUrl,
    String? mqttUsername,
    String? mqttPassword,
    String? mqttDiscoveryPrefix,
    bool? setupComplete,
    bool? autoUpdate,
    String? updateSource,
    String? giteaApiToken,
    String? currentVersion,
    List<String>? moduleOrder,
    String? timezone,
    String? topSwipeAction,
    String? bottomSwipeAction,
    bool? showVoiceFeedback,
    bool? micMuted,
    TouchIndicatorConfig? touchIndicator,
    bool? captureToolsEnabled,
    PhotoSourcesConfig? photoSources,
    double? uiScale,
    List<WebviewConfig>? webviews,
  }) {
    return HubConfig(
      apiKey: apiKey ?? this.apiKey,
      immichUrl: immichUrl ?? this.immichUrl,
      immichApiKey: immichApiKey ?? this.immichApiKey,
      haUrl: haUrl ?? this.haUrl,
      haToken: haToken ?? this.haToken,
      musicAssistantUrl: musicAssistantUrl ?? this.musicAssistantUrl,
      musicAssistantToken: musicAssistantToken ?? this.musicAssistantToken,
      frigateUrl: frigateUrl ?? this.frigateUrl,
      frigateUsername: frigateUsername ?? this.frigateUsername,
      frigatePassword: frigatePassword ?? this.frigatePassword,
      idleTimeoutSeconds: idleTimeoutSeconds ?? this.idleTimeoutSeconds,
      nightModeSource: nightModeSource ?? this.nightModeSource,
      nightModeHaEntity: nightModeHaEntity == _undefined ? this.nightModeHaEntity : nightModeHaEntity as String?,
      nightModeClockStart: nightModeClockStart == _undefined ? this.nightModeClockStart : nightModeClockStart as String?,
      nightModeClockEnd: nightModeClockEnd == _undefined ? this.nightModeClockEnd : nightModeClockEnd as String?,
      defaultMusicZone: defaultMusicZone == _undefined ? this.defaultMusicZone : defaultMusicZone as String?,
      use24HourClock: use24HourClock ?? this.use24HourClock,
      pinnedEntityIds: pinnedEntityIds ?? this.pinnedEntityIds,
      weatherEntityId: weatherEntityId ?? this.weatherEntityId,
      voiceAssistantEntityId:
          voiceAssistantEntityId ?? this.voiceAssistantEntityId,
      sendspinEnabled: sendspinEnabled ?? this.sendspinEnabled,
      sendspinPlayerName: sendspinPlayerName ?? this.sendspinPlayerName,
      sendspinBufferSeconds: sendspinBufferSeconds ?? this.sendspinBufferSeconds,
      sendspinClientId: sendspinClientId ?? this.sendspinClientId,
      sendspinServerUrl: sendspinServerUrl ?? this.sendspinServerUrl,
      sendspinStaticDelayMs: sendspinStaticDelayMs ?? this.sendspinStaticDelayMs,
      onScreenKeyboardMode:
          onScreenKeyboardMode ?? this.onScreenKeyboardMode,
      displayProfile: displayProfile ?? this.displayProfile,
      displayWidth: displayWidth ?? this.displayWidth,
      displayHeight: displayHeight ?? this.displayHeight,
      enabledModules: enabledModules ?? this.enabledModules,
      modulePlacements: modulePlacements ?? this.modulePlacements,
      mealieUrl: mealieUrl ?? this.mealieUrl,
      mealieToken: mealieToken ?? this.mealieToken,
      mqttBrokerUrl: mqttBrokerUrl ?? this.mqttBrokerUrl,
      mqttUsername: mqttUsername ?? this.mqttUsername,
      mqttPassword: mqttPassword ?? this.mqttPassword,
      mqttDiscoveryPrefix: mqttDiscoveryPrefix ?? this.mqttDiscoveryPrefix,
      setupComplete: setupComplete ?? this.setupComplete,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateSource: updateSource ?? this.updateSource,
      giteaApiToken: giteaApiToken ?? this.giteaApiToken,
      currentVersion: currentVersion ?? this.currentVersion,
      moduleOrder: moduleOrder ?? this.moduleOrder,
      timezone: timezone ?? this.timezone,
      topSwipeAction: topSwipeAction ?? this.topSwipeAction,
      bottomSwipeAction: bottomSwipeAction ?? this.bottomSwipeAction,
      showVoiceFeedback: showVoiceFeedback ?? this.showVoiceFeedback,
      micMuted: micMuted ?? this.micMuted,
      touchIndicator: touchIndicator ?? this.touchIndicator,
      captureToolsEnabled: captureToolsEnabled ?? this.captureToolsEnabled,
      photoSources: photoSources ?? this.photoSources,
      uiScale: uiScale ?? this.uiScale,
      webviews: webviews ?? this.webviews,
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'immichUrl': immichUrl,
        'immichApiKey': immichApiKey,
        'haUrl': haUrl,
        'haToken': haToken,
        'musicAssistantUrl': musicAssistantUrl,
        'musicAssistantToken': musicAssistantToken,
        'frigateUrl': frigateUrl,
        'frigateUsername': frigateUsername,
        'frigatePassword': frigatePassword,
        'idleTimeoutSeconds': idleTimeoutSeconds,
        'nightModeSource': nightModeSource,
        'nightModeHaEntity': nightModeHaEntity,
        'nightModeClockStart': nightModeClockStart,
        'nightModeClockEnd': nightModeClockEnd,
        'defaultMusicZone': defaultMusicZone,
        'use24HourClock': use24HourClock,
        'pinnedEntityIds': pinnedEntityIds,
        'weatherEntityId': weatherEntityId,
        'voiceAssistantEntityId': voiceAssistantEntityId,
        'sendspinEnabled': sendspinEnabled,
        'sendspinPlayerName': sendspinPlayerName,
        'sendspinBufferSeconds': sendspinBufferSeconds,
        'sendspinClientId': sendspinClientId,
        'sendspinServerUrl': sendspinServerUrl,
        'sendspinStaticDelayMs': sendspinStaticDelayMs,
        'onScreenKeyboardMode': onScreenKeyboardMode,
        'displayProfile': displayProfile,
        'displayWidth': displayWidth,
        'displayHeight': displayHeight,
        'enabledModules': enabledModules,
        'modulePlacements': modulePlacements.map((k, v) => MapEntry(k, v)),
        'mealieUrl': mealieUrl,
        'mealieToken': mealieToken,
        'mqttBrokerUrl': mqttBrokerUrl,
        'mqttUsername': mqttUsername,
        'mqttPassword': mqttPassword,
        'mqttDiscoveryPrefix': mqttDiscoveryPrefix,
        'setupComplete': setupComplete,
        'autoUpdate': autoUpdate,
        'updateSource': updateSource,
        'giteaApiToken': giteaApiToken,
        'currentVersion': currentVersion,
        'moduleOrder': moduleOrder,
        'timezone': timezone,
        'topSwipeAction': topSwipeAction,
        'bottomSwipeAction': bottomSwipeAction,
        'showVoiceFeedback': showVoiceFeedback,
        'micMuted': micMuted,
        'touchIndicator': touchIndicator.toJson(),
        'captureToolsEnabled': captureToolsEnabled,
        'photoSources': photoSources.toJson(),
        'uiScale': uiScale,
        'webviews': webviews.map((w) => w.toJson()).toList(),
      };

  factory HubConfig.fromJson(Map<String, dynamic> json) => HubConfig(
        apiKey: json['apiKey'] as String? ?? '',
        immichUrl: json['immichUrl'] as String? ?? '',
        immichApiKey: json['immichApiKey'] as String? ?? '',
        haUrl: json['haUrl'] as String? ?? '',
        haToken: json['haToken'] as String? ?? '',
        musicAssistantUrl: json['musicAssistantUrl'] as String? ?? '',
        musicAssistantToken: json['musicAssistantToken'] as String? ?? '',
        frigateUrl: json['frigateUrl'] as String? ?? '',
        frigateUsername: json['frigateUsername'] as String? ?? '',
        frigatePassword: json['frigatePassword'] as String? ?? '',
        idleTimeoutSeconds: json['idleTimeoutSeconds'] as int? ?? 120,
        nightModeSource: json['nightModeSource'] as String? ?? 'none',
        nightModeHaEntity: json['nightModeHaEntity'] as String?,
        nightModeClockStart: json['nightModeClockStart'] as String?,
        nightModeClockEnd: json['nightModeClockEnd'] as String?,
        defaultMusicZone: json['defaultMusicZone'] as String?,
        use24HourClock: json['use24HourClock'] as bool? ?? false,
        pinnedEntityIds: (json['pinnedEntityIds'] as List<dynamic>?)?.cast<String>() ?? const [],
        weatherEntityId: json['weatherEntityId'] as String? ?? '',
        voiceAssistantEntityId:
            json['voiceAssistantEntityId'] as String? ?? '',
        sendspinEnabled: json['sendspinEnabled'] as bool? ?? false,
        sendspinPlayerName: json['sendspinPlayerName'] as String? ?? '',
        sendspinBufferSeconds: json['sendspinBufferSeconds'] as int? ?? 5,
        sendspinClientId: json['sendspinClientId'] as String? ?? '',
        sendspinServerUrl: json['sendspinServerUrl'] as String? ?? '',
        sendspinStaticDelayMs: json['sendspinStaticDelayMs'] as int? ?? 0,
        onScreenKeyboardMode:
            json['onScreenKeyboardMode'] as String? ?? 'auto',
        displayProfile: json['displayProfile'] as String? ?? 'auto',
        displayWidth: json['displayWidth'] as int? ?? 0,
        displayHeight: json['displayHeight'] as int? ?? 0,
        enabledModules: (json['enabledModules'] as List<dynamic>?)?.cast<String>() ?? const ['media', 'controls', 'cameras'],
        modulePlacements: json.containsKey('modulePlacements')
            ? (json['modulePlacements'] as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()))
            : _migrateEnabledModules(json),
        mealieUrl: json['mealieUrl'] as String? ?? '',
        mealieToken: json['mealieToken'] as String? ?? '',
        mqttBrokerUrl: json['mqttBrokerUrl'] as String? ?? '',
        mqttUsername: json['mqttUsername'] as String? ?? '',
        mqttPassword: json['mqttPassword'] as String? ?? '',
        mqttDiscoveryPrefix:
            json['mqttDiscoveryPrefix'] as String? ?? 'homeassistant',
        setupComplete: json['setupComplete'] as bool? ?? false,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        updateSource: json['updateSource'] as String? ?? 'github',
        giteaApiToken: json['giteaApiToken'] as String? ?? '',
        currentVersion: json['currentVersion'] as String? ?? '',
        moduleOrder: (json['moduleOrder'] as List<dynamic>?)?.cast<String>() ?? const [],
        timezone: json['timezone'] as String? ?? '',
        topSwipeAction: json['topSwipeAction'] as String? ?? 'menu2',
        bottomSwipeAction: json['bottomSwipeAction'] as String? ?? 'menu1',
        showVoiceFeedback: json['showVoiceFeedback'] as bool? ?? true,
        micMuted: json['micMuted'] as bool? ?? false,
        touchIndicator: json['touchIndicator'] is Map
            ? TouchIndicatorConfig.fromJson(
                (json['touchIndicator'] as Map).cast<String, dynamic>())
            : const TouchIndicatorConfig(),
        captureToolsEnabled: json['captureToolsEnabled'] as bool? ?? false,
        photoSources: json['photoSources'] is Map
            ? PhotoSourcesConfig.fromJson(
                (json['photoSources'] as Map).cast<String, dynamic>())
            : const PhotoSourcesConfig(),
        uiScale: ((json['uiScale'] as num?)?.toDouble() ?? 1.0)
            .clamp(0.75, 1.5)
            .toDouble(),
        webviews: (json['webviews'] as List<dynamic>?)
                ?.map((j) =>
                    WebviewConfig.fromJson(j as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  static Map<String, List<String>> _migrateEnabledModules(Map<String, dynamic> json) {
    final enabled = (json['enabledModules'] as List<dynamic>?)?.cast<String>()
        ?? const ['media', 'controls', 'cameras'];
    return {for (final id in enabled) id: ['swipe']};
  }
}

/// Manages config state and persists changes to disk automatically.
///
/// On native, loaded once at app startup via [load], then updated through
/// [update] which writes back to JSON immediately.
/// On web, config is in-memory only — no persistence across sessions.
class HubConfigNotifier extends StateNotifier<HubConfig> {
  HubConfigNotifier() : super(const HubConfig());

  HubConfig get current => state;

  Future<void> load() async {
    if (kIsWeb) return;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/hub_config.json');
    if (await file.exists()) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = HubConfig.fromJson(json);
      } catch (e) {
        Log.e('Config', 'Failed to parse hub_config.json, resetting to defaults: $e');
        state = const HubConfig();
      }
    }
    if (state.apiKey.isEmpty) {
      await update((c) => c.copyWith(apiKey: HubConfig.generateApiKey()));
    }
  }

  Future<void> update(HubConfig Function(HubConfig) updater) async {
    final updated = updater(state);
    if (!kIsWeb) {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/hub_config.json');
      await file.writeAsString(jsonEncode(updated.toJson()));
    }
    state = updated;
  }

  /// Set the global UI scale, clamped to [0.75, 1.5] before persisting.
  Future<void> setUiScale(double scale) async {
    final clamped = scale.clamp(0.75, 1.5).toDouble();
    await update((c) => c.copyWith(uiScale: clamped));
  }
}

final hubConfigProvider =
    StateNotifierProvider<HubConfigNotifier, HubConfig>((ref) {
  return HubConfigNotifier();
});
