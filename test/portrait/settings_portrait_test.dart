import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/scale/hearth_scale.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/models/immich_album.dart';
import 'package:hearth/models/immich_person.dart';
import 'package:hearth/modules/alarm_clock/alarm_models.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';
import 'package:hearth/modules/webview/custom_url_editor.dart';
import 'package:hearth/plugins/framework/plugin_panel.dart';
import 'package:hearth/plugins/framework/plugin_sidebar.dart';
import 'package:hearth/plugins/network/network_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';
import 'package:hearth/screens/settings/settings_screen.dart';
import 'package:hearth/screens/settings/update_settings.dart';
import 'package:hearth/services/display_rotation_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/immich_service.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/mqtt_service.dart';
import 'package:hearth/services/timezone_service.dart';
import 'package:hearth/services/update_service.dart';
import 'package:hearth/services/voice_satellite_bridge.dart';
import 'package:hearth/services/wifi_service.dart';
import 'package:hearth/widgets/entity_picker_dialog.dart';
import 'package:hearth/widgets/timezone_picker_dialog.dart';

import 'portrait_harness.dart';

const _longUrl =
    'https://a-rather-long-hostname.internal.example-home-network.org:8443/some/base/path';
const _longToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhYmNkZWYwMTIzNDU2Nzg5In0.c2lnbmF0dXJl';

/// Every integration filled in, with values long enough to stress a row.
final _config = HubConfig.fromJson({
  ...const HubConfig().toJson(),
  'apiKey': 'k',
  'setupComplete': true,
  'immichUrl': _longUrl,
  'immichApiKey': _longToken,
  'haUrl': _longUrl,
  'haToken': _longToken,
  'musicAssistantUrl': _longUrl,
  'musicAssistantToken': _longToken,
  'frigateUrl': _longUrl,
  'frigateUsername': 'a-long-frigate-username@example.org',
  'frigatePassword': _longToken,
  'unifiProtectUrl': _longUrl,
  'unifiProtectApiKey': _longToken,
  'mealieUrl': _longUrl,
  'mealieToken': _longToken,
  'mqttBrokerUrl': 'mqtt://a-rather-long-hostname.internal.example.org:1883',
  'mqttUsername': 'a-long-mqtt-username',
  'mqttPassword': _longToken,
  'weatherEntityId': 'weather.a_very_long_weather_entity_name_for_the_house',
  'voiceAssistantEntityId':
      'assist_satellite.a_very_long_satellite_name_in_the_kitchen',
  'defaultMusicZone': 'media_player.kitchen_and_dining_room_speaker_group',
  'pinnedEntityIds': [
    for (var i = 0; i < 8; i++) 'light.a_long_pinned_light_entity_name_$i',
  ],
  'sendspinEnabled': true,
  'sendspinPlayerName': 'Kitchen Hearth with a long player name',
  'sendspinServerUrl': 'ws://a-rather-long-hostname.internal.example.org:8927',
  'dlnaEnabled': true,
  'plexEnabled': true,
  'plexPlayerName': 'Kitchen Hearth with a long player name',
  'nightModeSource': 'clock',
  'nightModeClockStart': '22:00',
  'nightModeClockEnd': '07:00',
  'timezone': 'America/Argentina/ComodRivadavia',
  'displayOrientation': 'portrait',
  'captureToolsEnabled': true,
  'devBundleEnabled': true,
  'devBundleUrl': '$_longUrl/hearth-bundle-dev.tar.gz',
  'updateSource': 'gitea',
  'giteaApiToken': _longToken,
  'moduleOrder': ['media', 'controls', 'cameras'],
  'modulePlacements': {
    'media': ['swipe', 'menu1'],
    'controls': ['swipe', 'menu2'],
    'cameras': ['swipe'],
    'alarm_clock': ['menu1'],
    'mealie': ['swipe', 'menu1', 'menu2'],
  },
  'photoSources': const PhotoSourcesConfig(
    memoriesEnabled: true,
    albumEnabled: true,
    albumId: 'album-2',
    peopleEnabled: true,
    personIds: ['p0', 'p1', 'p2', 'p3', 'p4'],
    smartSearchEnabled: true,
    smartSearchQuery: 'golden hour on the beach with the whole family',
  ).toJson(),
  'webviews': [
    for (var i = 0; i < 4; i++)
      WebviewConfig(
        id: 'webview:custom:$i',
        url: '$_longUrl/dashboard-number-$i?kiosk=true&theme=dark',
        name: 'A webview with a long display name $i',
        iconCodePoint: Icons.web.codePoint,
        source: i.isEven ? WebviewSource.customUrl : WebviewSource.haDashboard,
        order: i,
      ).toJson(),
  ],
});

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

class _FakeHa extends HomeAssistantService {
  @override
  Map<String, HaEntity> get entities => {
        for (final domain in ['light', 'switch', 'assist_satellite', 'weather'])
          for (var i = 0; i < 12; i++)
            '$domain.a_long_entity_identifier_for_room_$i': HaEntity(
              entityId: '$domain.a_long_entity_identifier_for_room_$i',
              state: 'on',
              attributes: {
                'friendly_name': 'A long friendly name for the device in room $i',
              },
              lastChanged: DateTime(2026),
            ),
      };
}

class _FakeImmich extends ImmichService {
  _FakeImmich() : super(baseUrl: '', apiKey: '');

  @override
  Future<List<ImmichAlbum>> listAlbums() async => [
        for (var i = 0; i < 6; i++)
          ImmichAlbum(
            id: 'album-$i',
            name: 'An album with quite a long descriptive name $i',
            assetCount: 1000 + i,
          ),
      ];

  @override
  Future<List<ImmichPerson>> listNamedPeople() async => [
        for (var i = 0; i < 14; i++)
          ImmichPerson(
            id: 'p$i',
            name: 'Person With A Long Name $i',
            numberOfAssets: 100 + i,
          ),
      ];
}

class _FakeWifi extends WifiService {
  @override
  Future<List<WifiNetwork>> scan() async => [
        for (var i = 0; i < 12; i++)
          WifiNetwork(
            ssid: 'A neighbouring network with a long SSID $i',
            signalStrength: 90 - i * 6,
            security: i.isEven ? 'WPA2 WPA3' : '',
          ),
      ];
  @override
  Future<bool> connect(String ssid, String password) async => false;
  @override
  Future<bool> connectOpen(String ssid) async => false;
  @override
  Future<String?> activeConnection() async =>
      'A neighbouring network with a long SSID 0';
}

class _FakeTimezones extends TimezoneService {
  @override
  Future<List<String>> listTimezones() async => [
        ...TimezoneService.commonTimezones,
        ...TimezoneService.fallbackTimezones,
      ];
  @override
  Future<bool> applyTimezone(String timezone) async => true;
}

AlarmService _alarms() {
  final service = AlarmService();
  for (var i = 0; i < 5; i++) {
    service.addAlarm(Alarm(
      id: 'a$i',
      time: '0${5 + i}:30',
      label: 'An alarm with a long label for weekday mornings $i',
      days: const [1, 2, 3, 4, 5, 6, 7],
      sunriseLights: const ['light.bedroom_ceiling', 'light.bedside_lamp'],
    ));
  }
  return service;
}

List<Override> _overrides({HubConfig? config}) => [
      hubConfigProvider
          .overrideWith((ref) => _MemoryConfigNotifier(config ?? _config)),
      homeAssistantServiceProvider.overrideWith((ref) => _FakeHa()),
      immichServiceProvider.overrideWith((ref) => _FakeImmich()),
      wifiServiceProvider.overrideWithValue(_FakeWifi()),
      timezoneServiceProvider.overrideWithValue(_FakeTimezones()),
      // No config listener: the real provider would dial the broker.
      mqttServiceProvider.overrideWith((ref) => MqttService(ref)),
      alarmServiceProvider.overrideWith((ref) => _alarms()),
      deviceIpProvider.overrideWith((ref) async => '192.168.100.250'),
      webPinProvider.overrideWithValue('1234'),
      installedVersionProvider.overrideWithValue('1.42.17-a-long-dev-suffix'),
      latestUpdateProvider.overrideWith((ref) async => const UpdateInfo(
            version: '1.43.0',
            bundleUrl: '$_longUrl/hearth-bundle-1.43.0.tar.gz',
            tagName: 'v1.43.0',
          )),
      // A Pi running landscape while portrait is configured: the Display panel
      // shows its restart row.
      displayRotationServiceProvider.overrideWithValue(DisplayRotationService(
        environment: const {kAppliedRotationEnv: '0'},
        isLinux: true,
        runProcess: (_, _) async => ProcessResult(0, 0, '', ''),
      )),
    ];

/// Lets futures the panels kicked off in initState resolve and their
/// follow-up frames paint.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Walks the panel's scroll view to its end one viewport at a time, so every
/// row is laid out and painted at least once.
Future<void> _scrollPanelToEnd(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byType(PluginPanel),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  while (position.pixels < position.maxScrollExtent) {
    position.jumpTo((position.pixels + position.viewportDimension)
        .clamp(0.0, position.maxScrollExtent));
    await tester.pump();
  }
}

/// Selects every visible sidebar entry in turn and scrolls its panel to the
/// end. Returns one line per framework error, naming the panel and the widget
/// that raised it, so a single run lists every broken panel rather than
/// stopping at the first.
Future<List<String>> _walkPanels(WidgetTester tester) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
  final sidebarScroll = find
      .descendant(
        of: find.byType(PluginSidebar),
        matching: find.byType(Scrollable),
      )
      .first;
  final problems = <String>[];
  var current = '';
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final where = RegExp(r'\w+:file://\S+/(lib/\S+)')
        .firstMatch(details.toString())
        ?.group(1);
    problems.add(
        '$current: ${details.exceptionAsString().split('\n').first}'
        '${where == null ? '' : ' ($where)'}');
  };
  try {
    for (final plugin in container.read(visiblePluginsProvider)) {
      current = plugin.id;
      final row = find.descendant(
        of: find.byType(PluginSidebar),
        matching: find.text(plugin.name),
      );
      await tester.scrollUntilVisible(row, 120, scrollable: sidebarScroll);
      await tester.tap(row);
      await _settle(tester);
      expect(tester.widget<PluginPanel>(find.byType(PluginPanel)).plugin.id,
          plugin.id);
      await _scrollPanelToEnd(tester);
    }
  } finally {
    FlutterError.onError = previousHandler;
  }
  return problems;
}

void main() {
  testLayouts('settings screen: every sidebar entry, scrolled to its end',
      (tester, canvas) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: hostScreen(const SettingsScreen()),
    ));
    await _settle(tester);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    expect(container.read(visiblePluginsProvider).length,
        firstPartyPlugins.length,
        reason: 'the populated config should make every plugin visible');

    expect(await _walkPanels(tester), isEmpty);

    // The panel, not the sidebar, gets most of the width.
    final sidebar = tester.getSize(find.byType(PluginSidebar)).width;
    expect(sidebar, lessThan(canvas.width * 0.4));
  });

  testLayouts('settings screen: unconfigured install', (tester, canvas) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(config: const HubConfig(apiKey: 'k')),
      child: hostScreen(const SettingsScreen()),
    ));
    await _settle(tester);
    expect(await _walkPanels(tester), isEmpty);
  });

  // The Voice panel's satellite group only exists on an Android kiosk, so the
  // walks above never lay it out.
  testLayouts('voice panel with the Android satellite group',
      (tester, canvas) async {
    debugVoiceSatelliteSupportedOverride = true;
    addTearDown(() => debugVoiceSatelliteSupportedOverride = null);

    const methods = MethodChannel('com.hearth/voice');
    const events = 'com.hearth/voice/events';
    const codec = StandardMethodCodec();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        methods,
        (call) async => call.method == 'listWakeWords'
            ? [
                for (var i = 0; i < 9; i++)
                  {
                    'id': 'wake_word_$i',
                    'name': 'A wake word with a long display name $i',
                  },
              ]
            : null);
    messenger.setMockMessageHandler(
        events, (_) async => codec.encodeSuccessEnvelope(null));
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMessageHandler(events, null);
    });

    final config = _config.copyWith(
      voiceSatelliteEnabled: true,
      voiceSatelliteName: 'Kitchen Hearth with a long satellite name',
      voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
      voiceWakeWords: ['wake_word_3', 'wake_word_7'],
    );
    final bridge = VoiceSatelliteBridge(_MemoryConfigNotifier(config));
    await bridge.attach();
    addTearDown(bridge.dispose);
    await messenger.handlePlatformMessage(
        events,
        codec.encodeSuccessEnvelope({
          'event': 'health',
          'code': 'micOpenFailed',
          'message': 'Foreground service start refused: the app was not in a '
              'state that allows starting a microphone foreground service',
        }),
        (_) {});

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides(config: config),
        voiceSatelliteBridgeProvider.overrideWithValue(bridge),
      ],
      child: hostScreen(const SettingsScreen()),
    ));
    await _settle(tester);

    final row = find.descendant(
      of: find.byType(PluginSidebar),
      matching: find.text('Voice'),
    );
    await tester.scrollUntilVisible(
        row,
        120,
        scrollable: find
            .descendant(
              of: find.byType(PluginSidebar),
              matching: find.byType(Scrollable),
            )
            .first);
    await tester.tap(row);
    await _settle(tester);
    expect(tester.widget<PluginPanel>(find.byType(PluginPanel)).plugin.id,
        'hearth.voice');
    await _scrollPanelToEnd(tester);

    expect(find.text('Satellite MAC'), findsOneWidget);
    expect(find.textContaining('Microphone could not be opened'),
        findsOneWidget);
  });

  // HearthScaleScope divides the canvas by uiScale, so the largest scale on a
  // portrait panel is the tightest layout Settings ever sees (576x789).
  for (final entry in {
    'portrait 864x1184': kPortraitCanvas,
    'portrait 800x1280': kNarrowPortraitCanvas,
  }.entries) {
    testWidgets('settings screen at uiScale 1.5 — ${entry.key}',
        (tester) async {
      await useCanvas(tester, entry.value);
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(config: _config.copyWith(uiScale: 1.5)),
        child: hostScreen(const HearthScaleScope(child: SettingsScreen())),
      ));
      await _settle(tester);
      expect(await _walkPanels(tester), isEmpty);
      final sidebar = tester.getSize(find.byType(PluginSidebar)).width;
      expect(sidebar, lessThan(entry.value.width / 1.5 * 0.4));
    });
  }

  group('settings dialogs', () {
    Future<void> open(
      WidgetTester tester,
      Widget dialog, {
      List<Override>? overrides,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overrides ?? _overrides(),
        child: hostScreen(Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        )),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testLayouts('timezone picker', (tester, canvas) async {
      await open(
        tester,
        const TimezonePickerDialog(
          timezones: [
            ...TimezoneService.commonTimezones,
            ...TimezoneService.fallbackTimezones,
          ],
          currentTimezone: 'America/Argentina/ComodRivadavia',
        ),
      );
      expect(find.byType(TimezonePickerDialog), findsOneWidget);
    });

    testLayouts('entity picker', (tester, canvas) async {
      await open(tester, const EntityPickerDialog());
      expect(find.byType(EntityPickerDialog), findsOneWidget);
    });

    testLayouts('custom URL editor, add and edit', (tester, canvas) async {
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(),
        child: hostScreen(
            const SingleChildScrollView(child: CustomUrlList())),
      ));
      await _settle(tester);
      expectNoLayoutErrors(tester, 'custom URL list at $canvas');

      await tester.tap(find.byIcon(Icons.add).first);
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expectNoLayoutErrors(tester, 'add URL dialog at $canvas');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.edit).first);
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
    });
  });
  // Opened the way a user does: from the real panel, at the panel's width.
  group('dialogs opened from a panel', () {
    Future<void> openFrom(
      WidgetTester tester, {
      required String plugin,
      required String tap,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(),
        child: hostScreen(const SettingsScreen()),
      ));
      await _settle(tester);
      final row = find.descendant(
        of: find.byType(PluginSidebar),
        matching: find.text(plugin),
      );
      await tester.scrollUntilVisible(
        row,
        120,
        scrollable: find
            .descendant(
              of: find.byType(PluginSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(row);
      await _settle(tester);
      final target = find.descendant(
        of: find.byType(PluginPanel),
        matching: find.text(tap),
      );
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find
            .descendant(
              of: find.byType(PluginPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(target);
      await _settle(tester);
    }

    testLayouts('Wi-Fi picker and its password prompt', (tester, canvas) async {
      await openFrom(tester, plugin: 'Network', tap: 'Wi-Fi');
      expect(find.text('Wi-Fi Networks'), findsOneWidget);
      expectNoLayoutErrors(tester, 'Wi-Fi picker at $canvas');

      await tester.tap(find.text('A neighbouring network with a long SSID 2'));
      await _settle(tester);
      expect(find.text('Password'), findsOneWidget);
    });

    testLayouts('display profile picker', (tester, canvas) async {
      await openFrom(tester, plugin: 'Display', tap: 'Display Profile');
      expect(find.byType(SimpleDialog), findsOneWidget);
    });

    testLayouts('timezone picker', (tester, canvas) async {
      await openFrom(tester, plugin: 'Display', tap: 'Timezone');
      expect(find.byType(TimezonePickerDialog), findsOneWidget);
    });

    testLayouts('night mode clock prompt', (tester, canvas) async {
      await openFrom(tester, plugin: 'Display', tap: 'Night Mode Start');
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testLayouts('pinned entity picker', (tester, canvas) async {
      await openFrom(tester, plugin: 'Home Assistant', tap: 'Edit');
      expect(find.byType(EntityPickerDialog), findsOneWidget);
    });

    testLayouts('Gitea token prompt', (tester, canvas) async {
      await openFrom(tester, plugin: 'System', tap: 'Gitea API Token');
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
