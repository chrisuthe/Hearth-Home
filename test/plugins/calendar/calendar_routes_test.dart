import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/ics_calendar_source.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/plugins/calendar/calendar_plugin.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

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

void main() {
  late ProviderContainer container;
  late _MemoryHubConfigNotifier configNotifier;
  late LocalApiServer server;
  late int port;
  late List<String> probed;
  late List<String> defaultsAsked;
  const auth = 'Bearer test-api-key-12345';

  Future<(int, Map<String, dynamic>)> send(String method, String path,
      [Object? body]) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.open(
        method, 'localhost', port, '/api/plugin/hearth.calendar/$path');
    request.headers.add('Authorization', auth);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  Future<void> startWith(HubConfig config) async {
    probed = [];
    defaultsAsked = [];
    container = ProviderContainer(overrides: [
      calendarIcsProbeProvider.overrideWithValue((url) async {
        probed.add(url);
        if (url.contains('missing')) {
          throw const IcsProbeException('Calendar not found at this URL');
        }
        return const IcsProbe(name: 'School', color: '#1badf8', eventCount: 12);
      }),
      calendarHaDefaultsProvider.overrideWithValue((entityId) async {
        defaultsAsked.add(entityId);
        return (name: 'Family Calendar', color: 0xFF00AA00);
      }),
      calendarSourceEventsProvider.overrideWith((ref, id) => Stream.value(
          const SourceEvents(
              status: SourceStatus.error,
              error: 'Calendar not found at this URL'))),
    ]);
    configNotifier = _MemoryHubConfigNotifier()
      ..state = config.copyWith(apiKey: 'test-api-key-12345');
    server = LocalApiServer(
      displayModeService: DisplayModeService(),
      configNotifier: configNotifier,
      readProvider: container.read,
      plugins: [CalendarPlugin()],
    );
    port = await server.start(port: 0);
    addTearDown(() async {
      await server.stop();
      container.dispose();
    });
  }

  List<CalendarSource> sources() => configNotifier.state.calendarSources;

  group('GET sources', () {
    test('lists sources with status and without their URLs', () async {
      await startWith(const HubConfig(calendarSources: [_family, _school]));
      // Let the overridden stream deliver.
      container.read(calendarSourceEventsProvider(_family.id));
      await Future<void>.delayed(Duration.zero);

      final (status, body) = await send('GET', 'sources');
      expect(status, 200);
      expect(body['palette'], hasLength(8));
      final list = body['sources'] as List;
      expect(list.map((s) => s['id']), [_family.id, _school.id]);
      expect(list.first['color'], '#646cff');
      expect(list.first['kindLabel'], 'Home Assistant');
      expect(list.first['state'], 'error');
      expect(list.first['status'], 'Calendar not found at this URL');
      expect(jsonEncode(body), isNot(contains('secret-token')));
    });

    test('a disabled source reports off', () async {
      await startWith(HubConfig(
          calendarSources: [_family.copyWith(enabled: false)]));
      final (_, body) = await send('GET', 'sources');
      expect((body['sources'] as List).single['state'], 'off');
      expect((body['sources'] as List).single['status'], 'Off');
    });
  });

  group('POST sources', () {
    test('adds an HA calendar with name and colour from HA', () async {
      await startWith(const HubConfig());
      final (status, body) = await send(
          'POST', 'sources', {'kind': 'ha', 'entityId': 'calendar.family'});
      expect(status, 200);
      expect(body['source']['id'], 'ha:calendar.family');
      expect(sources().single.name, 'Family Calendar');
      expect(sources().single.color, 0xFF00AA00);
      expect(defaultsAsked, ['calendar.family']);
    });

    test('an HA calendar keeps a given name and colour', () async {
      await startWith(const HubConfig());
      await send('POST', 'sources', {
        'kind': 'ha',
        'entityId': 'calendar.family',
        'name': 'Us',
        'color': '#123456',
      });
      expect(sources().single.name, 'Us');
      expect(sources().single.color, 0xFF123456);
      expect(defaultsAsked, isEmpty);
    });

    test('adds an ICS URL without fetching it again', () async {
      await startWith(const HubConfig(calendarSources: [_family]));
      final (status, _) = await send('POST', 'sources', {
        'kind': 'ics',
        'url': 'webcal://example.com/a.ics',
        'name': 'School',
      });
      expect(status, 200);
      final added = sources().last;
      expect(added.kind, CalendarSourceKind.ics);
      expect(added.id, startsWith('ics:'));
      expect(added.url, 'webcal://example.com/a.ics');
      expect(added.color, calendarPalette[1]);
      expect(probed, isEmpty);
    });

    test('rejects bad kinds, schemes, entity ids, colours and duplicates',
        () async {
      await startWith(const HubConfig(calendarSources: [_family]));
      final cases = <Map<String, Object?>, int>{
        {'kind': 'caldav', 'url': 'https://example.com'}: 400,
        {}: 400,
        {'kind': 'ics', 'url': 'ftp://example.com/a.ics'}: 400,
        {'kind': 'ics', 'url': 'file:///etc/passwd'}: 400,
        {'kind': 'ics'}: 400,
        {'kind': 'ha', 'entityId': 'light.kitchen'}: 400,
        {'kind': 'ha', 'entityId': 42}: 400,
        {'kind': 'ha', 'entityId': 'calendar.work', 'color': 'blue'}: 400,
        {'kind': 'ha', 'entityId': 'calendar.work', 'enabled': 'yes'}: 400,
        {'kind': 'ha', 'entityId': 'calendar.family'}: 409,
      };
      for (final entry in cases.entries) {
        final (status, body) = await send('POST', 'sources', entry.key);
        expect(status, entry.value, reason: '${entry.key}');
        expect(body['error'], isA<String>());
      }
      expect(sources(), [_family]);
    });
  });

  group('PUT sources/<id>', () {
    test('changes name, colour and enabled', () async {
      await startWith(const HubConfig(calendarSources: [_family, _school]));
      final (status, _) = await send('PUT', 'sources/ics%3A0011223344556677',
          {'name': ' Kids ', 'color': '#00ff00', 'enabled': false});
      expect(status, 200);
      expect(sources().last.name, 'Kids');
      expect(sources().last.color, 0xFF00FF00);
      expect(sources().last.enabled, isFalse);
      expect(sources().last.url, _school.url);
      expect(sources().first, _family);
    });

    test('refuses to change the kind, entity or URL', () async {
      await startWith(const HubConfig(calendarSources: [_family, _school]));
      for (final body in [
        {'kind': 'ics'},
        {'entityId': 'calendar.work'},
        {'url': 'https://example.com/other.ics'},
      ]) {
        final (status, _) =
            await send('PUT', 'sources/ha%3Acalendar.family', body);
        expect(status, 400, reason: '$body');
      }
      // Echoing the fixed values back is fine.
      final (status, _) = await send('PUT', 'sources/ha%3Acalendar.family',
          {'kind': 'ha', 'entityId': 'calendar.family', 'name': 'Home'});
      expect(status, 200);
      expect(sources().first.name, 'Home');
    });

    test('rejects an empty name and a bad colour; 404 for no source',
        () async {
      await startWith(const HubConfig(calendarSources: [_family]));
      expect((await send('PUT', 'sources/ha%3Acalendar.family', {'name': ' '})).$1,
          400);
      expect(
          (await send('PUT', 'sources/ha%3Acalendar.family', {'color': 7.5})).$1,
          400);
      expect((await send('PUT', 'sources/ha%3Acalendar.nope', {'name': 'x'})).$1,
          404);
      expect(sources(), [_family]);
    });
  });

  group('DELETE sources/<id>', () {
    test('removes the source', () async {
      await startWith(const HubConfig(calendarSources: [_family, _school]));
      final (status, _) = await send('DELETE', 'sources/ha%3Acalendar.family');
      expect(status, 200);
      expect(sources(), [_school]);
    });

    test('404 for an unknown id', () async {
      await startWith(const HubConfig(calendarSources: [_family]));
      expect((await send('DELETE', 'sources/ics%3Anope')).$1, 404);
      expect(sources(), [_family]);
    });
  });

  group('POST test', () {
    test('reports the name, colour and event count', () async {
      await startWith(const HubConfig());
      final (status, body) =
          await send('POST', 'test', {'url': 'webcal://example.com/a.ics'});
      expect(status, 200);
      expect(body, {
        'ok': true,
        'name': 'School',
        'color': '#1badf8',
        'eventCount': 12,
      });
      expect(probed, ['webcal://example.com/a.ics']);
      expect(sources(), isEmpty);
    });

    test('reports a fetch failure as ok: false', () async {
      await startWith(const HubConfig());
      final (status, body) =
          await send('POST', 'test', {'url': 'https://example.com/missing'});
      expect(status, 200);
      expect(body, {'ok': false, 'error': 'Calendar not found at this URL'});
    });

    test('rejects a bad scheme without fetching', () async {
      await startWith(const HubConfig());
      expect((await send('POST', 'test', {'url': 'file:///etc/hosts'})).$1, 400);
      expect((await send('POST', 'test', {})).$1, 400);
      expect(probed, isEmpty);
    });
  });
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
