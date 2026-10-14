import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/ics_calendar_source.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/plugins/calendar/calendar_plugin.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';
import 'package:hearth/services/home_assistant_service.dart';

const _family = CalendarSource(
  id: 'ha:calendar.family',
  kind: CalendarSourceKind.ha,
  entityId: 'calendar.family',
  name: 'Family',
  color: 0xFF646CFF,
);

const _school = CalendarSource(
  id: 'ics:0011223344556677',
  kind: CalendarSourceKind.ics,
  url: 'https://example.com/private/secret-token/basic.ics',
  name: 'School',
  color: 0xFFE57373,
);

String _html(HubConfig config) => CalendarPlugin().buildSettingsHtml(
      WebContext(
        config: config,
        apiBearerToken: 'test',
        pluginActionPrefix: '/api/plugin/hearth.calendar',
      ),
    );

void main() {
  group('CalendarPlugin', () {
    test('identity and registration', () {
      final p = CalendarPlugin();
      expect(p.id, 'hearth.calendar');
      expect(p.name, 'Calendar');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
      expect(p.isVisible(const HubConfig()), isTrue);
      expect(firstPartyPlugins.whereType<CalendarPlugin>(), hasLength(1));
    });

    test('statusFor needs an enabled source', () {
      final p = CalendarPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.needsSetup);
      expect(
          p.statusFor(
              HubConfig(calendarSources: [_family.copyWith(enabled: false)])),
          PluginConfigStatus.needsSetup);
      expect(p.statusFor(const HubConfig(calendarSources: [_family])),
          PluginConfigStatus.configured);
    });
  });

  group('buildSettingsHtml', () {
    test('renders the source list and the three settings', () {
      final html = _html(const HubConfig(
        calendarIcsPollMinutes: 360,
        calendarAmbientGlance: false,
        calendarDefaultView: 'month',
      ));
      expect(html, contains('data-config-path="calendarSources"'));
      expect(html, contains('id="calendar-panel"'));
      expect(html, contains('+ Home Assistant calendar'));
      expect(html, contains('+ ICS URL'));
      expect(html, contains('data-config-path="calendarIcsPollMinutes"'));
      expect(html, contains('<option value="360" selected>6 hours</option>'));
      expect(html, contains('data-config-path="calendarAmbientGlance"'));
      expect(html, contains('data-config-path="calendarDefaultView"'));
      expect(html, contains('<option value="month" selected>Month</option>'));
    });

    test('the ICS URL is a password field and never rendered', () {
      final html = _html(const HubConfig(calendarSources: [_school]));
      expect(html, contains('<input type="password" id="cal-ics-url"'));
      expect(html, isNot(contains('secret-token')));
    });

    test('the HA form reuses the entity picker, filtered to calendars and '
        'not auto-saved', () {
      final html = _html(const HubConfig());
      expect(html, contains('id="haep-calendar-entity-input"'));
      expect(html, contains('/api/plugin/hearth.ha/entities?domains=calendar'));
      final input = RegExp(r'<input[^>]*id="haep-calendar-entity-input"[^>]*>')
          .firstMatch(html)!
          .group(0)!;
      expect(input, contains('data-no-auto-save'));
      expect(input, isNot(contains('data-config-path')));
    });

    test('the script reaches each route', () {
      final html = _html(const HubConfig());
      expect(html, contains("call('GET', 'sources')"));
      expect(html, contains("call('POST', 'sources'"));
      expect(html, contains("call('PUT', 'sources/'"));
      expect(html, contains("call('DELETE', 'sources/'"));
      expect(html, contains("call('POST', 'test'"));
    });
  });

  group('device panel', () {
    late _MemoryHubConfigNotifier notifier;
    late List<String> probed;

    Future<void> pumpPanel(
      WidgetTester tester,
      HubConfig config, {
      List<HaEntity> entities = const [],
      IcsProbe? probe,
    }) async {
      notifier = _MemoryHubConfigNotifier(config);
      probed = [];
      await tester.binding.setSurfaceSize(const Size(1184, 864));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((_) => notifier),
          homeAssistantServiceProvider
              .overrideWithValue(_FakeHomeAssistant(entities)),
          calendarSourceEventsProvider.overrideWith((ref, id) => Stream.value(
              SourceEvents(
                  status: SourceStatus.ok,
                  lastOk: DateTime(2026, 10, 14, 10, 42)))),
          calendarHaDefaultsProvider.overrideWithValue(
              (id) async => (name: null, color: 0xFF00AA00)),
          calendarIcsProbeProvider.overrideWithValue((url) async {
            probed.add(url);
            if (probe == null) {
              throw const IcsProbeException('Calendar not found at this URL');
            }
            return probe;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (_, ref, _) => SingleChildScrollView(
                  child: CalendarPlugin().buildSettingsWidget(ref)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists sources with kind and live status', (tester) async {
      await pumpPanel(tester,
          HubConfig(calendarSources: [_family, _school.copyWith(enabled: false)]));
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Home Assistant · Updated 10:42 AM'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
      expect(find.text('ICS feed · Off'), findsOneWidget);
    });

    testWidgets('adds an HA calendar with the registry colour',
        (tester) async {
      await pumpPanel(tester, const HubConfig(), entities: [
        HaEntity(
          entityId: 'calendar.family',
          state: 'off',
          attributes: const {'friendly_name': 'Family'},
          lastChanged: DateTime(2026),
        ),
        HaEntity(
          entityId: 'light.kitchen',
          state: 'on',
          lastChanged: DateTime(2026),
        ),
      ]);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home Assistant calendar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-entity')));
      await tester.pumpAndSettle();
      expect(find.textContaining('light.kitchen'), findsNothing);
      await tester.tap(find.text('Family (calendar.family)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      final added = notifier.state.calendarSources.single;
      expect(added.id, 'ha:calendar.family');
      expect(added.kind, CalendarSourceKind.ha);
      expect(added.entityId, 'calendar.family');
      expect(added.name, 'Family');
      expect(added.color, 0xFF00AA00);
    });

    testWidgets('adds an ICS URL after one test fetch, prefilled from the feed',
        (tester) async {
      await pumpPanel(tester, const HubConfig(calendarSources: [_family]),
          probe: const IcsProbe(
              name: 'School', color: '#1BADF8FF', eventCount: 12));

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ICS URL'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('calendar-url')),
          'webcal://example.com/school.ics');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Test'));
      await tester.pumpAndSettle();

      expect(probed, ['webcal://example.com/school.ics']);
      expect(find.text('“School” · 12 events'), findsOneWidget);
      expect(notifier.state.calendarSources, [_family]);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(probed, hasLength(1));
      final added = notifier.state.calendarSources.last;
      expect(added.kind, CalendarSourceKind.ics);
      expect(added.url, 'webcal://example.com/school.ics');
      expect(added.name, 'School');
      expect(added.color, 0xFF1BADF8);
    });

    testWidgets('an ICS test failure is shown before saving', (tester) async {
      await pumpPanel(tester, const HubConfig());
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ICS URL'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('calendar-url')),
          'ftp://example.com/a.ics');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Test'));
      await tester.pumpAndSettle();
      expect(find.text('Use an http, https or webcal URL'), findsOneWidget);
      expect(probed, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('calendar-url')),
          'https://example.com/missing.ics');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Test'));
      await tester.pumpAndSettle();
      expect(find.text('Calendar not found at this URL'), findsOneWidget);
      expect(notifier.state.calendarSources, isEmpty);
      // Still savable: a feed that is down now may be back later.
      expect(find.widgetWithText(ElevatedButton, 'Add'), findsOneWidget);
    });

    testWidgets('edits name, colour and enabled', (tester) async {
      await pumpPanel(tester, const HubConfig(calendarSources: [_family]));
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('Home Assistant · calendar.family'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('calendar-name')), 'Us');
      await tester.tap(find.byKey(
          ValueKey('swatch-${calendarColorHex(calendarPalette[2])}')));
      await tester.tap(find.byKey(const ValueKey('calendar-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final edited = notifier.state.calendarSources.single;
      expect(edited.name, 'Us');
      expect(edited.color, calendarPalette[2]);
      expect(edited.enabled, isFalse);
      expect(edited.entityId, 'calendar.family');
    });

    testWidgets('deletes a source', (tester) async {
      await pumpPanel(
          tester, const HubConfig(calendarSources: [_family, _school]));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(notifier.state.calendarSources, [_school]);
    });

    testWidgets('sets the interval, glance and default view', (tester) async {
      await pumpPanel(tester, const HubConfig());

      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 hours').last);
      await tester.pumpAndSettle();
      expect(notifier.state.calendarIcsPollMinutes, 360);

      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Show upcoming events when idle'));
      await tester.pumpAndSettle();
      expect(notifier.state.calendarAmbientGlance, isFalse);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month').last);
      await tester.pumpAndSettle();
      expect(notifier.state.calendarDefaultView, 'month');
    });
  });
}

class _FakeHomeAssistant extends HomeAssistantService {
  _FakeHomeAssistant(List<HaEntity> entities)
      : _fixed = {for (final e in entities) e.entityId: e};
  final Map<String, HaEntity> _fixed;

  @override
  Map<String, HaEntity> get entities => _fixed;
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  _MemoryHubConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
