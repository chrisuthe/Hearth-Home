import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';
import 'package:hearth/plugins/people/people_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/local_api_server.dart';

const _sam = Person(
  id: 'person:0011223344556677',
  name: 'Sam',
  color: 0xFF646CFF,
  haPersonEntityId: 'person.sam',
);

const _alex = Person(
  id: 'person:8899aabbccddeeff',
  name: 'Alex',
  color: 0xFFE57373,
);

HaEntity _person(String id, String name, String state, {String? picture}) =>
    HaEntity(
      entityId: id,
      state: state,
      attributes: {
        'friendly_name': name,
        'entity_picture': ?picture,
      },
      lastChanged: DateTime(2026),
    );

void main() {
  late ProviderContainer container;
  late _MemoryHubConfigNotifier configNotifier;
  late LocalApiServer server;
  late int port;
  late _FakeHa ha;
  const auth = 'Bearer test-api-key-12345';

  Future<(int, Map<String, dynamic>)> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.open(
        method, 'localhost', port, '/api/plugin/hearth.people/$path');
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

  Future<void> startWith(HubConfig config, {bool connected = true}) async {
    ha = _FakeHa({
      'person.sam': _person('person.sam', 'Sam Smith', 'home',
          picture: '/api/image/serve/0123456789abcdef0123456789abcdef/512x512'),
      'person.alex': _person('person.alex', 'Alex Jones', 'not_home'),
      'person.jo': _person('person.jo', 'Jo', 'Work',
          picture: 'https://example.com/jo.png'),
      'todo.groceries': _person('todo.groceries', 'Groceries', '3'),
    }, connected: connected);
    container = ProviderContainer(
        overrides: [homeAssistantServiceProvider.overrideWithValue(ha)]);
    configNotifier = _MemoryHubConfigNotifier()
      ..state = config.copyWith(
        apiKey: 'test-api-key-12345',
        haUrl: 'http://ha.local:8123',
        haToken: 't',
      );
    server = LocalApiServer(
      displayModeService: DisplayModeService(),
      configNotifier: configNotifier,
      readProvider: container.read,
      plugins: [PeoplePlugin()],
    );
    port = await server.start(port: 0);
    addTearDown(() async {
      await server.stop();
      container.dispose();
    });
  }

  List<Person> people() => configNotifier.state.people;

  group('GET people', () {
    test('each with a resolved avatar and presence', () async {
      await startWith(const HubConfig(people: [_sam, _alex]));
      final (status, body) = await send('GET', 'people');
      expect(status, 200);
      expect(body['palette'], hasLength(8));
      final rows = body['people'] as List;
      expect(rows.first, {
        'id': _sam.id,
        'name': 'Sam',
        'color': '#646cff',
        'initial': 'S',
        'haPersonEntityId': 'person.sam',
        'avatarUrl': 'http://ha.local:8123/api/image/serve/'
            '0123456789abcdef0123456789abcdef/512x512',
        'presence': 'Home',
        'status': 'person.sam · Home',
      });
      expect(rows.last['avatarUrl'], isNull);
      expect(rows.last['presence'], isNull);
      expect(rows.last['status'], 'Not linked to Home Assistant');
    });

    test('HA disconnected: no presence, no avatar, no error', () async {
      await startWith(const HubConfig(people: [_sam]), connected: false);
      final (status, body) = await send('GET', 'people');
      expect(status, 200);
      final row = (body['people'] as List).single;
      expect(row['presence'], isNull);
      expect(row['avatarUrl'], isNull);
      expect(row['status'], "person.sam · Can't reach Home Assistant");
    });
  });

  group('POST people', () {
    test('adds a named person with the next free colour', () async {
      await startWith(const HubConfig(people: [_sam]));
      final (status, body) = await send('POST', 'people', {'name': ' Pat '});
      expect(status, 200);
      final added = people().last;
      expect(added.name, 'Pat');
      expect(added.color, calendarPalette[1]);
      expect(added.isLinked, isFalse);
      expect(added.id, matches(RegExp(r'^person:[0-9a-f]{16}$')));
      expect(body['person']['id'], added.id);
    });

    test('a linked person is named from HA when no name is given', () async {
      await startWith(const HubConfig());
      await send('POST', 'people',
          {'haPersonEntityId': 'person.jo', 'color': '#123456'});
      expect(people().single.name, 'Jo');
      expect(people().single.color, 0xFF123456);
      expect(people().single.haPersonEntityId, 'person.jo');
    });

    test('validation: 400 for bad fields, 409 for a duplicate link', () async {
      await startWith(const HubConfig(people: [_sam]));
      final cases = <Map<String, Object?>, int>{
        {}: 400,
        {'name': ' '}: 400,
        {'name': 3}: 400,
        {'name': 'Pat', 'color': 'blue'}: 400,
        {'name': 'Pat', 'color': '#12345'}: 400,
        {'name': 'Pat', 'haPersonEntityId': 'todo.groceries'}: 400,
        {'name': 'Pat', 'haPersonEntityId': 7}: 400,
        {'name': 'Pat', 'haPersonEntityId': 'person.sam'}: 409,
      };
      for (final entry in cases.entries) {
        final (status, body) = await send('POST', 'people', entry.key);
        expect(status, entry.value, reason: '${entry.key}');
        expect(body['error'], isA<String>());
      }
      expect(people(), [_sam]);
    });
  });

  group('PUT people/<id>', () {
    test('changes name, colour and link; blank unlinks', () async {
      await startWith(const HubConfig(people: [_sam, _alex]));
      final (status, _) = await send('PUT', 'people/${_alex.id}', {
        'name': ' Lex ',
        'color': '#00ff00',
        'haPersonEntityId': 'person.alex',
      });
      expect(status, 200);
      expect(people().last,
          _alex.copyWith(name: 'Lex', color: 0xFF00FF00,
              haPersonEntityId: 'person.alex'));
      await send('PUT', 'people/${_sam.id}', {'haPersonEntityId': ''});
      expect(people().first.isLinked, isFalse);
      expect(people().first.name, 'Sam');
    });

    test('keeping its own link is fine; taking another\'s is 409', () async {
      await startWith(const HubConfig(people: [_sam, _alex]));
      expect(
          (await send('PUT', 'people/${_sam.id}',
                  {'haPersonEntityId': 'person.sam'}))
              .$1,
          200);
      expect(
          (await send('PUT', 'people/${_alex.id}',
                  {'haPersonEntityId': 'person.sam'}))
              .$1,
          409);
    });

    test('unknown id is 404; bad fields are 400', () async {
      await startWith(const HubConfig(people: [_sam]));
      expect((await send('PUT', 'people/person:nope', {'name': 'x'})).$1, 404);
      for (final body in [
        {'name': ''},
        {'color': 'red'},
        {'color': 7.5},
        {'haPersonEntityId': 'light.kitchen'},
      ]) {
        expect((await send('PUT', 'people/${_sam.id}', body)).$1, 400,
            reason: '$body');
      }
      expect(people(), [_sam]);
    });
  });

  group('DELETE people/<id>', () {
    test('removes them and clears their lists and calendars', () async {
      await startWith(HubConfig(
        people: const [_sam, _alex],
        todoLists: [
          TodoListConfig(entityId: 'todo.sam', personId: _sam.id),
          TodoListConfig(entityId: 'todo.sam2', personId: _sam.id),
          TodoListConfig(entityId: 'todo.alex', personId: _alex.id),
        ],
        calendarSources: [
          CalendarSource(
              id: 'ha:calendar.sam',
              kind: CalendarSourceKind.ha,
              personId: _sam.id),
        ],
      ));
      final (status, body) = await send('DELETE', 'people/${_sam.id}');
      expect(status, 200);
      expect(body['deleted'], _sam.id);
      expect(people(), [_alex]);
      final config = configNotifier.state;
      expect(config.todoLists.map((l) => l.personId), ['', '', _alex.id]);
      expect(config.calendarSources.single.personId, '');
    });

    test('404 for an unknown id', () async {
      await startWith(const HubConfig(people: [_sam]));
      expect((await send('DELETE', 'people/person:nope')).$1, 404);
      expect(people(), [_sam]);
    });
  });

  group('POST import', () {
    test('one person per unlinked person.* entity; never duplicates',
        () async {
      await startWith(const HubConfig(people: [_sam, _alex]));
      final (status, body) = await send('POST', 'import');
      expect(status, 200);
      final added = body['added'] as List;
      expect(added.map((p) => p['haPersonEntityId']),
          ['person.alex', 'person.jo']);
      expect(people().map((p) => p.name), ['Sam', 'Alex', 'Alex Jones', 'Jo']);
      expect([people()[2].color, people()[3].color],
          [calendarPalette[2], calendarPalette[3]],
          reason: 'the next free colours, one each');

      final (again, body2) = await send('POST', 'import');
      expect(again, 200);
      expect(body2['added'], isEmpty);
      expect(people(), hasLength(4));
      final links = [for (final p in people()) if (p.isLinked) p.haPersonEntityId];
      expect(links.toSet(), hasLength(links.length));
    });

    test('two imports at once still link each entity once', () async {
      await startWith(const HubConfig());
      configNotifier.writeDelay = const Duration(milliseconds: 50);
      final results =
          await Future.wait([send('POST', 'import'), send('POST', 'import')]);
      expect(results.map((r) => r.$1), [200, 200]);
      expect(people().map((p) => p.haPersonEntityId),
          ['person.alex', 'person.jo', 'person.sam']);
    });

    test('503 while HA is not connected', () async {
      await startWith(const HubConfig(), connected: false);
      expect((await send('POST', 'import')).$1, 503);
      expect(people(), isEmpty);
    });
  });
}

class _FakeHa extends HomeAssistantService {
  _FakeHa(this._fixed, {required this.connected});
  final Map<String, HaEntity> _fixed;
  final bool connected;

  @override
  Map<String, HaEntity> get entities => _fixed;

  @override
  bool get isConnected => connected;
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  /// Like the real notifier, state lands only after the (simulated) write.
  Duration writeDelay = Duration.zero;

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    final updated = updater(state);
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    state = updated;
  }
}
