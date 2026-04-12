import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';

// dart:io and path_provider compile to stubs on web — guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Sentinel value for copyWith to distinguish "not provided" from "set to null".
const _undefined = Object();

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
  final bool sendspinEnabled;
  final String sendspinPlayerName;
  final int sendspinBufferSeconds;
  final String sendspinClientId;
  final String sendspinServerUrl;
  final String displayProfile; // "auto" | "amoled-11" | "rpi-7" | "hdmi"
  final int displayWidth;      // 0 = use profile default
  final int displayHeight;     // 0 = use profile default
  final List<String> enabledModules;
  final Map<String, List<String>> modulePlacements;
  final String mealieUrl;
  final String mealieToken;
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
    this.sendspinEnabled = false,
    this.sendspinPlayerName = '',
    this.sendspinBufferSeconds = 5,
    this.sendspinClientId = '',
    this.sendspinServerUrl = '',
    this.displayProfile = 'auto',
    this.displayWidth = 0,
    this.displayHeight = 0,
    this.enabledModules = const ['media', 'controls', 'cameras'],
    this.modulePlacements = const {},
    this.mealieUrl = '',
    this.mealieToken = '',
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
    bool? sendspinEnabled,
    String? sendspinPlayerName,
    int? sendspinBufferSeconds,
    String? sendspinClientId,
    String? sendspinServerUrl,
    String? displayProfile,
    int? displayWidth,
    int? displayHeight,
    List<String>? enabledModules,
    Map<String, List<String>>? modulePlacements,
    String? mealieUrl,
    String? mealieToken,
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
      sendspinEnabled: sendspinEnabled ?? this.sendspinEnabled,
      sendspinPlayerName: sendspinPlayerName ?? this.sendspinPlayerName,
      sendspinBufferSeconds: sendspinBufferSeconds ?? this.sendspinBufferSeconds,
      sendspinClientId: sendspinClientId ?? this.sendspinClientId,
      sendspinServerUrl: sendspinServerUrl ?? this.sendspinServerUrl,
      displayProfile: displayProfile ?? this.displayProfile,
      displayWidth: displayWidth ?? this.displayWidth,
      displayHeight: displayHeight ?? this.displayHeight,
      enabledModules: enabledModules ?? this.enabledModules,
      modulePlacements: modulePlacements ?? this.modulePlacements,
      mealieUrl: mealieUrl ?? this.mealieUrl,
      mealieToken: mealieToken ?? this.mealieToken,
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
        'sendspinEnabled': sendspinEnabled,
        'sendspinPlayerName': sendspinPlayerName,
        'sendspinBufferSeconds': sendspinBufferSeconds,
        'sendspinClientId': sendspinClientId,
        'sendspinServerUrl': sendspinServerUrl,
        'displayProfile': displayProfile,
        'displayWidth': displayWidth,
        'displayHeight': displayHeight,
        'enabledModules': enabledModules,
        'modulePlacements': modulePlacements.map((k, v) => MapEntry(k, v)),
        'mealieUrl': mealieUrl,
        'mealieToken': mealieToken,
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
        sendspinEnabled: json['sendspinEnabled'] as bool? ?? false,
        sendspinPlayerName: json['sendspinPlayerName'] as String? ?? '',
        sendspinBufferSeconds: json['sendspinBufferSeconds'] as int? ?? 5,
        sendspinClientId: json['sendspinClientId'] as String? ?? '',
        sendspinServerUrl: json['sendspinServerUrl'] as String? ?? '',
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
}

final hubConfigProvider =
    StateNotifierProvider<HubConfigNotifier, HubConfig>((ref) {
  return HubConfigNotifier();
});
