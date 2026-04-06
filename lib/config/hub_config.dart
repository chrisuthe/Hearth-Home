import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Central configuration for a single Home Hub device.
///
/// Each hub stores its own config locally — there's no shared backend.
/// Values persist as JSON in the app support directory so they survive
/// restarts without needing a database.
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
  final bool use24HourClock;

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
    this.use24HourClock = false,
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
    bool? use24HourClock,
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
      use24HourClock: use24HourClock ?? this.use24HourClock,
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
        'use24HourClock': use24HourClock,
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
        use24HourClock: json['use24HourClock'] as bool? ?? false,
      );
}

/// Manages config state and persists changes to disk automatically.
///
/// Loaded once at app startup via [load], then updated through [update]
/// which writes back to JSON immediately. This keeps the settings screen
/// responsive — no "save" button needed.
class HubConfigNotifier extends StateNotifier<HubConfig> {
  HubConfigNotifier() : super(const HubConfig());

  /// Public read access for non-widget code (e.g. the HTTP config server).
  HubConfig get current => state;

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
