import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/lists/ha_todo_list.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/modules/lists/todo_actions.dart';
import 'package:hearth/services/home_assistant_service.dart';

import '../../services/home_assistant_service_test.dart'
    show FakeWebSocketChannel;

final Map<String, dynamic> _fixture = jsonDecode(
        File('test/fixtures/lists/todo_items.json').readAsStringSync())
    as Map<String, dynamic>;
final _subscriptionItems = _fixture['subscription'] as List;
final _getItems = _fixture['get_items'] as List;

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

List<Map<String, dynamic>> _sent(FakeWebSocketChannel c) => c.sentMessages
    .map((m) => jsonDecode(m) as Map<String, dynamic>)
    .toList();

Map<String, dynamic>? _lastOfType(FakeWebSocketChannel c, String type) {
  final matches = _sent(c).where((m) => m['type'] == type);
  return matches.isEmpty ? null : matches.last;
}

Future<void> _tick() => Future.delayed(const Duration(milliseconds: 20));

void main() {
  group('TodoItem.parseItems', () {
    final items = TodoItem.parseItems(_subscriptionItems);

    test('date due is a local date', () {
      final due = items[1].due!;
      expect(due.hasTime, isFalse);
      expect(due.value, DateTime(2026, 10, 16));
      expect(due.value.isUtc, isFalse);
      expect(items[1].description, 'A dozen');
    });

    test('datetime due keeps its offset as a UTC instant', () {
      final due = items[2].due!;
      expect(due.hasTime, isTrue);
      expect(due.value, DateTime.utc(2026, 10, 14, 22));
      expect(due.value.isUtc, isTrue);
    });

    test('no due', () {
      expect(items[0].due, isNull);
      expect(items[0].summary, 'Milk');
      expect(items[0].status, TodoStatus.needsAction);
    });

    test('completed present and absent', () {
      expect(items[3].status, TodoStatus.completed);
      expect(items[3].completed, DateTime.utc(2026, 10, 14, 12, 30, 0, 747, 356));
      expect(items[4].status, TodoStatus.completed);
      expect(items[4].completed, isNull);
      expect(items[7].status, TodoStatus.completed);
      expect(items[7].completed, isNull);
    });

    test('status and summary null read as open and empty', () {
      expect(items[5].status, TodoStatus.needsAction);
      expect(items[5].summary, '');
    });

    test('an item without uid parses with a null uid', () {
      expect(items[6].uid, isNull);
      expect(items[6].summary, 'No id');
    });

    test('get_items shape parses to the same items', () {
      expect(TodoItem.parseItems(_getItems), items);
    });

    test('skips what is not an object', () {
      expect(TodoItem.parseItems(['x', 1, null, {'uid': 'a'}]).single.uid, 'a');
    });

    test('an unreadable due is no due', () {
      expect(TodoItem.fromJson({'due': 'soon'}).due, isNull);
      expect(TodoItem.fromJson({'due': 5}).due, isNull);
    });
  });

  group('TodoFeatures', () {
    test('reads each flag', () {
      const f = TodoFeatures(1 | 2 | 4 | 8 | 16 | 64);
      expect([
        f.canAdd,
        f.canDelete,
        f.canUpdate,
        f.canMove,
        f.canSetDueDate,
        f.canSetDueTime,
        f.canSetDescription,
      ], [true, true, true, true, true, false, true]);
    });

    test('from an entity, none until it arrives', () {
      expect(TodoFeatures.of(null).bits, 0);
      final e = HaEntity(
        entityId: 'todo.a',
        state: '3',
        attributes: const {'supported_features': 15},
        lastChanged: DateTime(2026),
      );
      expect(TodoFeatures.of(e), const TodoFeatures(15));
    });
  });

  group('HaTodoList', () {
    late FakeWebSocketChannel channel;
    late HomeAssistantService ha;
    HaTodoList? list;

    setUp(() {
      channel = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(channel);
    });

    tearDown(() async {
      list?.dispose();
      list = null;
      ha.dispose();
      await channel.close();
    });

    HaTodoList start({Duration connectTimeout = const Duration(seconds: 20)}) {
      final l = HaTodoList(
          ha: ha, entityId: 'todo.groceries', connectTimeout: connectTimeout);
      l.stream.listen((_) {});
      return list = l;
    }

    Future<int> connectAndSubscribe() async {
      ha.connect('token');
      channel.simulateMessage({'type': 'auth_ok'});
      await _tick();
      return _lastOfType(channel, 'todo/item/subscribe')!['id'] as int;
    }

    void push(FakeWebSocketChannel c, int id, Object? items) =>
        c.simulateMessage({
          'id': id,
          'type': 'event',
          'event': {'items': items},
        });

    void fail(int id, String code) => channel.simulateMessage({
          'id': id,
          'type': 'result',
          'success': false,
          'error': {'code': code, 'message': code},
        });

    test('subscribes; result then event fills the items, nulls included',
        () async {
      start();
      final id = await connectAndSubscribe();
      final msg = _lastOfType(channel, 'todo/item/subscribe')!;
      expect(msg, {
        'type': 'todo/item/subscribe',
        'entity_id': 'todo.groceries',
        'id': id,
      });

      channel.simulateMessage(
          {'id': id, 'type': 'result', 'success': true, 'result': null});
      await _tick();
      expect(list!.current.status, ListStatus.loading);

      push(channel, id, _subscriptionItems);
      await _tick();
      expect(list!.current.status, ListStatus.ok);
      expect(list!.current.items, TodoItem.parseItems(_subscriptionItems));
    });

    test('a second event replaces the items', () async {
      start();
      final id = await connectAndSubscribe();
      push(channel, id, _subscriptionItems);
      push(channel, id, [
        {'uid': 'x', 'summary': 'Only', 'status': 'needs_action'}
      ]);
      await _tick();
      expect(list!.current.items.map((i) => i.uid), ['x']);
    });

    test('an empty list is ok and empty', () async {
      start();
      final id = await connectAndSubscribe();
      push(channel, id, _subscriptionItems);
      push(channel, id, []);
      await _tick();
      expect(list!.current.status, ListStatus.ok);
      expect(list!.current.items, isEmpty);
    });

    test('invalid_entity_id is an error and is not retried', () async {
      start();
      final id = await connectAndSubscribe();
      fail(id, 'invalid_entity_id');
      await _tick();
      expect(list!.current.status, ListStatus.error);
      expect(list!.current.error, 'List not found in Home Assistant');

      channel.simulateMessage({'type': 'auth_ok'});
      await _tick();
      expect(
          _sent(channel).where((m) => m['type'] == 'todo/item/subscribe'),
          hasLength(1));
    });

    test('unknown_command names HA 2023.12', () async {
      start();
      final id = await connectAndSubscribe();
      fail(id, 'unknown_command');
      await _tick();
      expect(list!.current.status, ListStatus.error);
      expect(list!.current.error, contains('2023.12'));
    });

    test('drop: stale with items kept, new subscribe after auth_ok',
        () async {
      start();
      final oldId = await connectAndSubscribe();
      push(channel, oldId, _subscriptionItems);
      await _tick();

      await channel.close();
      await _tick();
      expect(list!.current.status, ListStatus.stale);
      expect(list!.current.items, hasLength(_subscriptionItems.length));

      final second = FakeWebSocketChannel();
      ha.replaceChannel(second);
      ha.connect('token');
      second.simulateMessage({'type': 'auth_ok'});
      await _tick();
      final newId = _lastOfType(second, 'todo/item/subscribe')!['id'] as int;
      expect(newId, isNot(oldId));

      push(second, newId, [
        {'uid': 'x', 'summary': 'After', 'status': 'needs_action'}
      ]);
      await _tick();
      expect(list!.current.status, ListStatus.ok);
      expect(list!.current.items.single.summary, 'After');
      await second.close();
    });

    test('unreachable HA times out to an error', () async {
      start(connectTimeout: const Duration(milliseconds: 30));
      await Future.delayed(const Duration(milliseconds: 80));
      expect(list!.current.status, ListStatus.error);
      expect(list!.current.error, contains("Can't reach"));
    });

    test('dispose unsubscribes the id', () async {
      start();
      final id = await connectAndSubscribe();
      list!.dispose();
      await _tick();
      expect(_lastOfType(channel, 'unsubscribe_events')!['subscription'], id);
    });
  });

  group('TodoActions', () {
    late FakeWebSocketChannel channel;
    late HomeAssistantService ha;
    var features = const TodoFeatures(0);
    late TodoActions actions;

    setUp(() async {
      channel = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(channel);
      actions = TodoActions(ha, (_) => features);
      ha.connect('t');
      channel.simulateMessage({'type': 'auth_ok'});
      await _tick();
    });

    tearDown(() async {
      ha.dispose();
      await channel.close();
    });

    const all = TodoFeatures(127);
    const shoppingList = TodoFeatures(1 | 2 | 4 | 8);
    const googleTasks = TodoFeatures(1 | 2 | 4 | 8 | 16 | 64);
    const dateTimeOnly = TodoFeatures(1 | 2 | 4 | 32);

    /// Runs [action], answers its message with [reply], and returns what was
    /// sent (without the id) and the action's result.
    Future<(Map<String, dynamic>?, String?)> run(
      Future<String?> Function() action, {
      Map<String, dynamic> reply = const {'success': true, 'result': null},
    }) async {
      final before = channel.sentMessages.length;
      final result = action();
      await _tick();
      Map<String, dynamic>? sent;
      if (channel.sentMessages.length > before) {
        sent = jsonDecode(channel.sentMessages.last) as Map<String, dynamic>;
        channel.simulateMessage({'id': sent['id'], 'type': 'result', ...reply});
        sent.remove('id');
      }
      return (sent, await result);
    }

    Map<String, dynamic> service(String name, Map<String, dynamic> data,
            [String entity = 'todo.groceries']) =>
        {
          'type': 'call_service',
          'domain': 'todo',
          'service': name,
          'service_data': data,
          'target': {'entity_id': entity},
        };

    const milk = TodoItem(uid: 'milk', summary: 'Milk');

    test('add sends the summary and only supported fields', () async {
      features = all;
      var (sent, result) = await run(() => actions.add('todo.groceries', 'Eggs',
          due: TodoDue.date(DateTime(2026, 10, 16)), description: 'A dozen'));
      expect(sent, service('add_item', {
        'item': 'Eggs',
        'due_date': '2026-10-16',
        'description': 'A dozen',
      }));
      expect(result, isNull);

      features = shoppingList;
      (sent, _) = await run(() => actions.add('todo.groceries', 'Eggs',
          due: TodoDue.date(DateTime(2026, 10, 16)), description: 'A dozen'));
      expect(sent, service('add_item', {'item': 'Eggs'}));
    });

    test('add with a time sends due_datetime as an instant', () async {
      features = all;
      final (sent, _) = await run(() => actions.add('todo.groceries', 'Bills',
          due: TodoDue.instant(DateTime.utc(2026, 10, 14, 22))));
      expect(sent!['service_data'],
          {'item': 'Bills', 'due_datetime': '2026-10-14T22:00:00.000Z'});
    });

    test('complete sends uid as item and only the status', () async {
      features = shoppingList;
      final (sent, result) = await run(() => actions.update('todo.groceries',
          milk, const TodoItem(uid: 'milk', summary: 'Milk', status: TodoStatus.completed)));
      expect(sent, service('update_item', {'item': 'milk', 'status': 'completed'}));
      expect(result, isNull);
    });

    test('uncomplete sends needs_action', () async {
      features = shoppingList;
      final (sent, _) = await run(() => actions.update(
          'todo.groceries',
          const TodoItem(uid: 'milk', summary: 'Milk', status: TodoStatus.completed),
          milk));
      expect(sent!['service_data'], {'item': 'milk', 'status': 'needs_action'});
    });

    test('rename sends only rename', () async {
      features = all;
      final (sent, _) = await run(() => actions.update('todo.groceries', milk,
          const TodoItem(uid: 'milk', summary: 'Oat milk')));
      expect(sent!['service_data'], {'item': 'milk', 'rename': 'Oat milk'});
    });

    test('an unsupported field is never sent; nothing left sends nothing',
        () async {
      features = shoppingList;
      final (sent, result) = await run(() => actions.update(
          'todo.groceries',
          milk,
          TodoItem(
              uid: 'milk',
              summary: 'Milk',
              description: 'Oat',
              due: TodoDue.date(DateTime(2026, 10, 16)))));
      expect(sent, isNull);
      expect(result, isNull);
    });

    test('a timed due on a date-only list is not sent', () async {
      features = googleTasks;
      final (sent, _) = await run(() => actions.update('todo.groceries', milk,
          TodoItem(
              uid: 'milk',
              summary: 'Milk 2',
              due: TodoDue.instant(DateTime.utc(2026, 10, 14, 22)))));
      expect(sent!['service_data'], {'item': 'milk', 'rename': 'Milk 2'});
    });

    test('a clear sends the supported due field as null', () async {
      final dated =
          TodoItem(uid: 'milk', summary: 'Milk', due: TodoDue.date(DateTime(2026, 10, 16)));
      features = googleTasks;
      var (sent, _) = await run(() => actions.update('todo.groceries', dated, milk));
      expect(sent!['service_data'], {'item': 'milk', 'due_date': null});

      features = dateTimeOnly;
      (sent, _) = await run(() => actions.update('todo.groceries', dated, milk));
      expect(sent!['service_data'], {'item': 'milk', 'due_datetime': null});
      expect(sent['service_data'], isNot(contains('due_date')));
    });

    test('description is sent when supported, null clears it', () async {
      features = googleTasks;
      const described =
          TodoItem(uid: 'milk', summary: 'Milk', description: 'Oat');
      final (sent, _) =
          await run(() => actions.update('todo.groceries', described, milk));
      expect(sent!['service_data'], {'item': 'milk', 'description': null});
    });

    test('remove sends the uid; clearCompleted sends no data', () async {
      var (sent, _) = await run(() => actions.remove('todo.groceries', milk));
      expect(sent, service('remove_item', {'item': 'milk'}));
      (sent, _) = await run(() => actions.clearCompleted('todo.groceries'));
      expect(sent, service('remove_completed_items', {}));
    });

    test('an item without uid sends nothing and says why', () async {
      const noUid = TodoItem(summary: 'No id');
      var (sent, result) = await run(() => actions.update('todo.groceries',
          noUid, const TodoItem(summary: 'No id', status: TodoStatus.completed)));
      expect(sent, isNull);
      expect(result, isNotNull);
      (sent, result) = await run(() => actions.remove('todo.groceries', noUid));
      expect(sent, isNull);
      expect(result, isNotNull);
    });

    test('an error reply returns HA\'s message', () async {
      final (_, result) = await run(
        () => actions.remove('todo.groceries', milk),
        reply: const {
          'success': false,
          'error': {
            'code': 'service_validation_error',
            'message': 'Unable to find to-do list item: milk',
          },
        },
      );
      expect(result, 'Unable to find to-do list item: milk');
    });

    test('move to the top omits previous_uid', () async {
      final (sent, result) =
          await run(() => actions.move('todo.groceries', 'milk'));
      expect(sent, {
        'type': 'todo/item/move',
        'entity_id': 'todo.groceries',
        'uid': 'milk',
      });
      expect(result, isNull);
    });

    test('move after an item sends previous_uid', () async {
      final (sent, _) = await run(
          () => actions.move('todo.groceries', 'milk', previousUid: 'eggs'));
      expect(sent!['previous_uid'], 'eggs');
    });

    test('move not_supported is reported', () async {
      final (_, result) = await run(
        () => actions.move('todo.groceries', 'milk'),
        reply: const {
          'success': false,
          'error': {
            'code': 'not_supported',
            'message': 'To-do list does not support moving',
          },
        },
      );
      expect(result, 'To-do list does not support moving');
    });

    test('not connected is reported without sending', () async {
      await channel.close();
      await _tick();
      final before = channel.sentMessages.length;
      final result = await actions.move('todo.groceries', 'milk');
      expect(result, isNotNull);
      expect(channel.sentMessages.length, before);
    });

    test('a timeout says the change was not confirmed', () {
      fakeAsync((async) {
        final c = FakeWebSocketChannel();
        final h = HomeAssistantService.withChannel(c);
        h.connect('t');
        c.simulateMessage({'type': 'auth_ok'});
        async.flushMicrotasks();
        String? result;
        TodoActions(h, (_) => all)
            .clearCompleted('todo.groceries')
            .then((r) => result = r);
        async.elapse(const Duration(seconds: 11));
        expect(result, "Couldn't confirm the change");
        h.dispose();
      });
    });
  });

  group('choreToday', () {
    final now = DateTime(2026, 10, 14, 12);
    TodoItem due(TodoDue? d, {TodoStatus status = TodoStatus.needsAction}) =>
        TodoItem(uid: 'x', summary: 'x', due: d, status: status);

    test('date today is today, not late', () {
      expect(choreToday(due(TodoDue.date(DateTime(2026, 10, 14))), now),
          (late: false));
    });

    test('date yesterday is late', () {
      expect(choreToday(due(TodoDue.date(DateTime(2026, 10, 13))), now),
          (late: true));
    });

    test('date tomorrow is not today', () {
      expect(choreToday(due(TodoDue.date(DateTime(2026, 10, 15))), now), isNull);
    });

    test('datetime later today is today, not late', () {
      expect(
          choreToday(
              due(TodoDue.instant(DateTime(2026, 10, 14, 18))), now),
          (late: false));
    });

    test('datetime an hour ago is late', () {
      expect(
          choreToday(due(TodoDue.instant(now.subtract(const Duration(hours: 1)))),
              now),
          (late: true));
    });

    test('datetime tomorrow 00:30 is not today', () {
      expect(
          choreToday(
              due(TodoDue.instant(DateTime(2026, 10, 15, 0, 30))), now),
          isNull);
    });

    test('no due, or completed, is not today', () {
      expect(choreToday(due(null), now), isNull);
      expect(
          choreToday(
              due(TodoDue.date(DateTime(2026, 10, 13)),
                  status: TodoStatus.completed),
              now),
          isNull);
    });
  });

  group('choresTodayProvider', () {
    const ava =
        TodoListConfig(entityId: 'todo.ava', name: 'Ava', personId: 'person:ava');
    const ben =
        TodoListConfig(entityId: 'todo.ben', name: 'Ben', personId: 'person:ben');
    const groceries = TodoListConfig(entityId: 'todo.groceries');

    test('late first, then config order; plain lists left out; midnight tick',
        () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 14, 23);
        final feeds = <String, StreamController<TodoListState>>{};
        final c = ProviderContainer(overrides: [
          hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier(
              const HubConfig(todoLists: [groceries, ava, ben]))),
          todoNowProvider.overrideWithValue(() => start.add(async.elapsed)),
          todoListProvider.overrideWith((ref, id) =>
              (feeds[id] = StreamController<TodoListState>()).stream),
        ]);
        final sub = c.listen(choresTodayProvider, (_, _) {});
        async.flushMicrotasks();
        expect(feeds.keys, unorderedEquals(['todo.ava', 'todo.ben']),
            reason: 'a plain list is not watched');

        TodoItem item(String uid, TodoDue? due) =>
            TodoItem(uid: uid, summary: uid, due: due);
        feeds['todo.ava']!.add(TodoListState(status: ListStatus.ok, items: [
          item('ava-today', TodoDue.date(DateTime(2026, 10, 14))),
          item('ava-tomorrow', TodoDue.date(DateTime(2026, 10, 15))),
          item('ava-undated', null),
        ]));
        feeds['todo.ben']!.add(TodoListState(status: ListStatus.ok, items: [
          item('ben-2330', TodoDue.instant(DateTime(2026, 10, 14, 23, 30))),
          item('ben-late', TodoDue.date(DateTime(2026, 10, 12))),
        ]));
        async.flushMicrotasks();

        List<(String, bool)> lines() =>
            [for (final l in sub.read()) (l.item.uid!, l.late)];
        expect(lines(), [
          ('ben-late', true),
          ('ava-today', false),
          ('ben-2330', false),
        ]);
        expect(sub.read().first.list, ben);

        // A timed chore turns late at its instant, without a push.
        async.elapse(const Duration(minutes: 31));
        expect(lines(), [
          ('ben-2330', true),
          ('ben-late', true),
          ('ava-today', false),
        ]);

        // Past midnight: yesterday's date is late, tomorrow's is today.
        async.elapse(const Duration(minutes: 30));
        expect(lines(), [
          ('ava-today', true),
          ('ben-2330', true),
          ('ben-late', true),
          ('ava-tomorrow', false),
        ]);
        c.dispose();
      });
    });
  });

  group('todoListProvider', () {
    late FakeWebSocketChannel channel;
    late HomeAssistantService ha;

    setUp(() {
      channel = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(channel);
    });

    tearDown(() async {
      ha.dispose();
      await channel.close();
    });

    ProviderContainer container(HubConfig config) {
      final c = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier(config)),
        homeAssistantServiceProvider.overrideWithValue(ha),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    const configured = HubConfig(
      haUrl: 'http://ha.local:8123',
      haToken: 'token',
      todoLists: [TodoListConfig(entityId: 'todo.groceries')],
    );

    test('builds nothing for an entity not in config', () async {
      final c = container(configured);
      ha.connect('t');
      channel.simulateMessage({'type': 'auth_ok'});
      final sub = c.listen(todoListProvider('todo.other'), (_, _) {});
      await _tick();
      expect(sub.read().value?.status, ListStatus.error);
      expect(_lastOfType(channel, 'todo/item/subscribe'), isNull);
    });

    test('HA unconfigured is an error', () async {
      final c = container(const HubConfig(
          todoLists: [TodoListConfig(entityId: 'todo.groceries')]));
      final sub = c.listen(todoListProvider('todo.groceries'), (_, _) {});
      await _tick();
      expect(sub.read().value?.error, 'Home Assistant is not configured');
    });

    test('subscribes while watched, unsubscribes when no one watches',
        () async {
      final c = container(configured);
      ha.connect('t');
      channel.simulateMessage({'type': 'auth_ok'});
      final sub = c.listen(todoListProvider('todo.groceries'), (_, _) {});
      await _tick();
      final id = _lastOfType(channel, 'todo/item/subscribe')!['id'] as int;
      channel.simulateMessage({
        'id': id,
        'type': 'event',
        'event': {'items': _subscriptionItems},
      });
      await _tick();
      expect(sub.read().value?.items, hasLength(_subscriptionItems.length));

      sub.close();
      await _tick();
      expect(_lastOfType(channel, 'unsubscribe_events')?['subscription'], id);
    });

    test('todoFeaturesProvider follows the entity cache', () async {
      final c = container(configured);
      final sub = c.listen(todoFeaturesProvider('todo.groceries'), (_, _) {});
      expect(sub.read().bits, 0);
      ha.connect('t');
      channel.simulateMessage({'type': 'auth_ok'});
      await _tick();
      final getStates = _lastOfType(channel, 'get_states')!['id'];
      channel.simulateMessage({
        'id': getStates,
        'type': 'result',
        'success': true,
        'result': [
          {
            'entity_id': 'todo.groceries',
            'state': '4',
            'attributes': {'supported_features': 15},
            'last_changed': '2026-10-14T10:00:00Z',
          }
        ],
      });
      await _tick();
      expect(sub.read(), const TodoFeatures(15));
    });
  });
}
