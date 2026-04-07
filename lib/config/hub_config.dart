import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// dart:io and path_provider compile to stubs on web — guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Central configuration for a single Home Hub device.
///
/// Each hub stores its own config locally — there's no shared backend.
/// On native platforms, values persist as JSON in the app support directory.
/// On web, config lives only in memory (session-only "try before you buy").
class HubConfig {
  final String apiKey;
  final String immichUrl;
  final String immichApiKey;
  final String haUrl;
  final String haToken;
  final String musicAssistantUrl;
  final String musicAssistantToken;
  final String frigateUrl;
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
  final String displayProfile; // "auto" | "amoled-11" | "rpi-7" | "hdmi"
  final int displayWidth;      // 0 = use profile default
  final int displayHeight;     // 0 = use profile default
  final bool autoUpdate;
  final String currentVersion;

  const HubConfig({
    this.apiKey = '',
    this.immichUrl = '',
    this.immichApiKey = '',
    this.haUrl = '',
    this.haToken = '',
    this.musicAssistantUrl = '',
    this.musicAssistantToken = '',
    this.frigateUrl = '',
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
    this.displayProfile = 'auto',
    this.displayWidth = 0,
    this.displayHeight = 0,
    this.autoUpdate = true,
    this.currentVersion = '',
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
    int? idleTimeoutSeconds,
    String? nightModeSource,
    String? nightModeHaEntity,
    String? nightModeClockStart,
    String? nightModeClockEnd,
    String? defaultMusicZone,
    bool? use24HourClock,
    List<String>? pinnedEntityIds,
    String? weatherEntityId,
    bool? sendspinEnabled,
    String? sendspinPlayerName,
    int? sendspinBufferSeconds,
    String? sendspinClientId,
    String? displayProfile,
    int? displayWidth,
    int? displayHeight,
    bool? autoUpdate,
    String? currentVersion,
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
      idleTimeoutSeconds: idleTimeoutSeconds ?? this.idleTimeoutSeconds,
      nightModeSource: nightModeSource ?? this.nightModeSource,
      nightModeHaEntity: nightModeHaEntity ?? this.nightModeHaEntity,
      nightModeClockStart: nightModeClockStart ?? this.nightModeClockStart,
      nightModeClockEnd: nightModeClockEnd ?? this.nightModeClockEnd,
      defaultMusicZone: defaultMusicZone ?? this.defaultMusicZone,
      use24HourClock: use24HourClock ?? this.use24HourClock,
      pinnedEntityIds: pinnedEntityIds ?? this.pinnedEntityIds,
      weatherEntityId: weatherEntityId ?? this.weatherEntityId,
      sendspinEnabled: sendspinEnabled ?? this.sendspinEnabled,
      sendspinPlayerName: sendspinPlayerName ?? this.sendspinPlayerName,
      sendspinBufferSeconds: sendspinBufferSeconds ?? this.sendspinBufferSeconds,
      sendspinClientId: sendspinClientId ?? this.sendspinClientId,
      displayProfile: displayProfile ?? this.displayProfile,
      displayWidth: displayWidth ?? this.displayWidth,
      displayHeight: displayHeight ?? this.displayHeight,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      currentVersion: currentVersion ?? this.currentVersion,
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
        'displayProfile': displayProfile,
        'displayWidth': displayWidth,
        'displayHeight': displayHeight,
        'autoUpdate': autoUpdate,
        'currentVersion': currentVersion,
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
        displayProfile: json['displayProfile'] as String? ?? 'auto',
        displayWidth: json['displayWidth'] as int? ?? 0,
        displayHeight: json['displayHeight'] as int? ?? 0,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        currentVersion: json['currentVersion'] as String? ?? '',
      );
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
