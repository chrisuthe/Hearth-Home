import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';
import 'package:hearth/plugins/lists/lists_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/local_api_server.dart';

const _groceries = TodoListConfig(
  entityId: 'todo.groceries',
  name: 'Groceries',
  color: 0xFF646CFF,
);

const _alex = TodoListConfig(
  entityId: 'todo.alex',
  name: 'Alex',
  color: 0xFFE57373,
  personId: 'person:alex',
);

const _people = [
  Person(id: 'person:alex', name: 'Alex'),
  Person(id: 'person:sam', name: 'Sam'),
  Person(id: 'person:jo', name: 'Jo'),
];

void main() {
  late ProviderContainer container;
  late _MemoryHubConfigNotifier configNotifier;
  late LocalApiServer server;
  late int port;
  const auth = 'Bearer test-api-key-12345';

  Future<(int, Map<String, dynamic>)> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.open(
      method,
      'localhost',
      port,
      '/api/plugin/hearth.lists/$path',
    );
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
    container = ProviderContainer(
      overrides: [
        homeAssistantServiceProvider.overrideWithValue(
          _FakeHa({
            'todo.groceries': _todo(
              'todo.groceries',
              'Groceries',
              '3',
              1 | 4 | 8,
            ),
            'todo.chores': _todo('todo.chores', 'House chores', '0', 1 | 16),
          }),
        ),
      ],
    );
    configNotifier = _MemoryHubConfigNotifier()
      ..state = config.copyWith(
        people: config.people.isEmpty ? _people : config.people,
        apiKey: 'test-api-key-12345',
        haUrl: 'http://ha',
        haToken: 't',
      );
    server = LocalApiServer(
      displayModeService: DisplayModeService(),
      configNotifier: configNotifier,
      readProvider: container.read,
      plugins: [ListsPlugin()],
    );
    port = await server.start(port: 0);
    addTearDown(() async {
      await server.stop();
      container.dispose();
    });
  }

  List<TodoListConfig> lists() => configNotifier.state.todoLists;

  group('GET lists', () {
    test('lists each with person, live status and features', () async {
      await startWith(const HubConfig(todoLists: [_groceries, _alex]));
      final (status, body) = await send('GET', 'lists');
      expect(status, 200);
      expect(body['palette'], hasLength(8));
      final rows = body['lists'] as List;
      expect(rows.first, {
        'entityId': 'todo.groceries',
        'name': 'Groceries',
        'color': '#646cff',
        'personId': '',
        'kindLabel': 'List',
        'status': '3 open',
        'bad': false,
        'features': 'add · edit · reorder',
      });
      expect(rows.last['kindLabel'], 'Alex');
      expect(rows.last['status'], 'Not found in Home Assistant');
      expect(rows.last['bad'], isTrue);
      expect(rows.last['features'], '');
    });
  });

  group('POST lists', () {
    test('adds a list named from HA, next colour, no person', () async {
      await startWith(const HubConfig(todoLists: [_groceries]));
      final (status, body) = await send('POST', 'lists', {
        'entityId': 'todo.chores',
      });
      expect(status, 200);
      expect(body['list']['status'], 'All done');
      expect(
        lists().last,
        TodoListConfig(
          entityId: 'todo.chores',
          name: 'House chores',
          color: calendarPalette[1],
        ),
      );
    });

    test('keeps a given name, colour and person', () async {
      await startWith(const HubConfig());
      await send('POST', 'lists', {
        'entityId': 'todo.chores',
        'name': ' Sam ',
        'color': '#123456',
        'personId': 'person:sam',
      });
      expect(
        lists().single,
        const TodoListConfig(
          entityId: 'todo.chores',
          name: 'Sam',
          color: 0xFF123456,
          personId: 'person:sam',
        ),
      );
    });

    test('an entity HA does not know is named by its id', () async {
      await startWith(const HubConfig());
      await send('POST', 'lists', {'entityId': 'todo.later'});
      expect(lists().single.name, 'todo.later');
    });

    test('rejects bad entity ids, fields and duplicates', () async {
      await startWith(const HubConfig(todoLists: [_groceries]));
      final cases = <Map<String, Object?>, int>{
        {}: 400,
        {'entityId': 42}: 400,
        {'entityId': 'light.kitchen'}: 400,
        {'entityId': 'todo.chores', 'color': 'blue'}: 400,
        {'entityId': 'todo.chores', 'name': 3}: 400,
        {'entityId': 'todo.chores', 'personId': true}: 400,
        {'entityId': 'todo.chores', 'personId': 'person:nobody'}: 400,
        {'entityId': 'todo.groceries'}: 409,
      };
      for (final entry in cases.entries) {
        final (status, body) = await send('POST', 'lists', entry.key);
        expect(status, entry.value, reason: '${entry.key}');
        expect(body['error'], isA<String>());
      }
      expect(lists(), [_groceries]);
    });
  });

  group('PUT lists/<entityId>', () {
    test('changes name, colour and person', () async {
      await startWith(const HubConfig(todoLists: [_groceries, _alex]));
      final (status, _) = await send('PUT', 'lists/todo.groceries', {
        'name': ' Food ',
        'color': '#00ff00',
        'personId': 'person:jo',
      });
      expect(status, 200);
      expect(
        lists().first,
        const TodoListConfig(
          entityId: 'todo.groceries',
          name: 'Food',
          color: 0xFF00FF00,
          personId: 'person:jo',
        ),
      );
      expect(lists().last, _alex);
    });

    test('an empty person makes a chore list plain again', () async {
      await startWith(const HubConfig(todoLists: [_alex]));
      await send('PUT', 'lists/todo.alex', {'personId': ''});
      expect(lists().single.isChore, isFalse);
      expect(lists().single.name, 'Alex');
    });

    test(
      'rejects a new entity, an empty name, bad fields; 404 for none',
      () async {
        await startWith(const HubConfig(todoLists: [_groceries]));
        for (final body in [
          {'entityId': 'todo.other'},
          {'name': ' '},
          {'color': 7.5},
          {'personId': 1},
          {'personId': 'person:nobody'},
        ]) {
          expect(
            (await send('PUT', 'lists/todo.groceries', body)).$1,
            400,
            reason: '$body',
          );
        }
        // Echoing the entity back is fine.
        expect(
          (await send('PUT', 'lists/todo.groceries', {
            'entityId': 'todo.groceries',
            'name': 'Shop',
          })).$1,
          200,
        );
        expect((await send('PUT', 'lists/todo.nope', {'name': 'x'})).$1, 404);
        expect(lists().single.name, 'Shop');
      },
    );
  });

  group('DELETE lists/<entityId>', () {
    test('removes the list', () async {
      await startWith(const HubConfig(todoLists: [_groceries, _alex]));
      final (status, _) = await send('DELETE', 'lists/todo.groceries');
      expect(status, 200);
      expect(lists(), [_alex]);
    });

    test('404 for an unknown entity', () async {
      await startWith(const HubConfig(todoLists: [_groceries]));
      expect((await send('DELETE', 'lists/todo.nope')).$1, 404);
      expect(lists(), [_groceries]);
    });
  });
}

HaEntity _todo(String id, String name, String state, int features) => HaEntity(
  entityId: id,
  state: state,
  attributes: {'friendly_name': name, 'supported_features': features},
  lastChanged: DateTime(2026),
);

class _FakeHa extends HomeAssistantService {
  _FakeHa(this._fixed);
  final Map<String, HaEntity> _fixed;

  @override
  Map<String, HaEntity> get entities => _fixed;

  @override
  bool get isConnected => true;
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
