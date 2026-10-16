import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/display_orientation.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/display/display_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/services/display_rotation_service.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

/// A Pi launched at [applied] degrees (null: started without the launcher).
/// Records restart attempts instead of running sudo.
DisplayRotationService _piService(int? applied, List<List<String>> calls) =>
    DisplayRotationService(
      environment: {if (applied != null) kAppliedRotationEnv: '$applied'},
      isLinux: true,
      runProcess: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, 0, '', '');
      },
    );

void main() {
  group('DisplayPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = DisplayPlugin();
      expect(p.id, 'hearth.display');
      expect(p.name, 'Display');
      expect(p.category, PluginCategory.device);
      expect(p.order, 20);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = DisplayPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
      expect(
        p.statusFor(const HubConfig(
          idleTimeoutSeconds: 300,
          nightModeSource: 'clock',
          use24HourClock: true,
        )),
        PluginConfigStatus.configured,
      );
    });

    test('pageScreen is null', () {
      final p = DisplayPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml renders all major fields', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, contains('data-config-path="use24HourClock"'));
      expect(html, contains('data-config-path="timezone"'));
      expect(html, contains('data-config-path="idleTimeoutSeconds"'));
      expect(html, contains('UI Scale'));
      // UI Scale is now an editable slider on web (Enabler A typed writes).
      expect(html, contains('data-config-path="uiScale"'));
      expect(html, contains('data-config-path="theme"'));
      expect(html, contains('data-config-path="screenBackground"'));
      expect(html, contains('data-config-path="onScreenKeyboardMode"'));
      expect(html, contains('data-config-path="nightModeSource"'));
      expect(html, contains('data-config-path="nightModeHaEntity"'));
      expect(html, contains('data-config-path="nightModeClockStart"'));
      expect(html, contains('data-config-path="nightModeClockEnd"'));
      expect(html, contains('data-config-path="topSwipeAction"'));
      expect(html, contains('data-config-path="bottomSwipeAction"'));
    });

    test('buildSettingsHtml renders timezone as a searchable datalist picker',
        () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // The field is a text input bound to the datalist (searchable), not a
      // bare text input — this is the soft parity gap the drift-guard can't see.
      expect(html, contains('data-config-path="timezone"'));
      expect(html, contains('list="timezone-zones"'));
      expect(html, contains('<datalist id="timezone-zones">'));
      // The datalist is populated with IANA zone options sourced from
      // TimezoneService (same list the on-device picker uses).
      expect(html, contains('<option value="America/New_York">'));
      expect(html, contains('<option value="UTC">'));
    });

    test('buildSettingsHtml omits display profile editor (on-device only)', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, isNot(contains('data-config-path="displayProfile"')));
      expect(html, contains('Configure display profile'));
    });

    test('buildSettingsHtml night mode source select has all four options', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, contains('value="none"'));
      expect(html, contains('value="clock"'));
      expect(html, contains('value="ha_entity"'));
      expect(html, contains('value="api"'));
    });

    test('buildSettingsHtml night mode entity renders as an HA entity picker',
        () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(nightModeHaEntity: 'binary_sensor.dusk'),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // Bound free-text input keeps the parity-ledger marker + current value.
      expect(html, contains('data-config-path="nightModeHaEntity"'));
      expect(html, contains('value="binary_sensor.dusk"'));
      // Picker scaffold (search box + option list) is present.
      expect(html, contains('id="haep-nightModeHaEntity-input"'));
      expect(html, contains('id="haep-nightModeHaEntity-search"'));
      expect(html, contains('id="haep-nightModeHaEntity-list"'));
      // Reaches the HA plugin's shared route by absolute path, unfiltered
      // (night mode accepts any entity), since the Display panel's own prefix
      // can't see that route.
      expect(html, contains("fetch('/api/plugin/hearth.ha/entities'"));
      expect(html, isNot(contains('hearth.ha/entities?domains')));
    });

    test('buildSettingsHtml swipe selects have all five actions', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // The string assertions are loose because each value appears for both
      // top and bottom dropdowns.
      expect(html, contains('value="menu1"'));
      expect(html, contains('value="menu2"'));
      expect(html, contains('value="settings"'));
      expect(html, contains('value="nextScreen"'));
      expect(html, contains('value="previousScreen"'));
    });

    test('buildSettingsHtml reflects current config values', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(
          use24HourClock: true,
          timezone: 'America/Denver',
          nightModeSource: 'clock',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // use24HourClock=true -> checkbox checked
      expect(
        RegExp(r'data-config-path="use24HourClock"[^>]*\bchecked\b')
            .hasMatch(html),
        isTrue,
      );
      // timezone shows up in the value attribute
      expect(html, contains('America/Denver'));
      // nightModeSource=clock -> 'clock' option selected
      expect(
        RegExp(r'value="clock"\s+selected').hasMatch(html),
        isTrue,
      );
    });
  });
  group('DisplayPlugin screen orientation', () {
    test('web renders the orientation select with all five values', () {
      final html = DisplayPlugin().buildSettingsHtml(const WebContext(
        config: HubConfig(displayOrientation: 'portrait'),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, contains('data-config-path="displayOrientation"'));
      for (final o in DisplayOrientation.values) {
        expect(html, contains('value="${o.wire}"'));
      }
      expect(RegExp(r'value="portrait"\s+selected').hasMatch(html), isTrue);
      // Status + restart are driven by the plugin's own routes.
      expect(html, contains("hearth.action('rotation')"));
      expect(html, contains("hearth.action('restart', {})"));
      expect(html, contains('Restart to apply'));
    });

    Future<void> pumpPanel(
      WidgetTester tester, {
      required String orientation,
      required DisplayRotationService service,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier(
              HubConfig(displayOrientation: orientation))),
          displayRotationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) =>
                    DisplayPlugin().buildSettingsWidget(ref),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('on-device shows the orientation select', (tester) async {
      await pumpPanel(tester,
          orientation: 'portrait', service: _piService(90, []));
      expect(find.text('Screen Orientation'), findsOneWidget);
      expect(find.text('Portrait'), findsOneWidget);
      expect(find.text('Restart to apply'), findsNothing);
    });

    testWidgets('on-device offers a restart when the Pi runs another rotation',
        (tester) async {
      final calls = <List<String>>[];
      await pumpPanel(tester,
          orientation: 'portrait', service: _piService(0, calls));

      final button = find.text('Restart to apply');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(calls, [
        ['sudo', '-n', 'systemctl', 'restart', 'hearth.service']
      ]);
    });

    testWidgets('on-device explains a missing launcher instead of a restart',
        (tester) async {
      await pumpPanel(tester,
          orientation: 'portrait', service: _piService(null, []));
      expect(find.text('Restart to apply'), findsNothing);
      expect(find.textContaining('next update'), findsOneWidget);
    });

    testWidgets('on-device shows nothing extra off the Pi', (tester) async {
      await pumpPanel(
        tester,
        orientation: 'portrait',
        service: DisplayRotationService(environment: const {}, isLinux: false),
      );
      expect(find.text('Restart to apply'), findsNothing);
      expect(find.textContaining('next update'), findsNothing);
    });
  });
}
