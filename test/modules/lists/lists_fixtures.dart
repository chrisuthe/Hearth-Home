import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/modules/lists/todo_actions.dart';
import 'package:hearth/services/home_assistant_service.dart';

import '../../portrait/module_support.dart';

/// Every TodoListEntityFeature bit.
const kAllTodoFeatures = 127;

HaEntity todoEntity(
  String entityId, {
  int features = kAllTodoFeatures,
  int open = 0,
  String? name,
}) =>
    HaEntity(
      entityId: entityId,
      state: '$open',
      attributes: {
        'supported_features': features,
        'friendly_name': ?name,
      },
      lastChanged: DateTime(2026, 10, 14),
    );

HubConfig listsConfig(List<String> entityIds) => HubConfig(
      haUrl: 'http://ha.invalid:8123',
      haToken: 'token',
      todoLists: [
        for (final (i, id) in entityIds.indexed)
          TodoListConfig(entityId: id, color: [0xFF4CAF50, 0xFFFF9800, 0xFF2196F3][i % 3]),
      ],
    );

/// Records each write and answers with [reply] (null = success), or waits
/// on [hold] when set.
class FakeTodoActions implements TodoActions {
  final calls = <String>[];
  String? reply;
  Completer<String?>? hold;

  Future<String?> _answer(String call) {
    calls.add(call);
    return hold?.future ?? Future.value(reply);
  }

  @override
  Future<String?> add(String entityId, String summary,
          {TodoDue? due, String? description}) =>
      _answer('add $entityId $summary');

  @override
  Future<String?> update(String entityId, TodoItem from, TodoItem to) =>
      _answer('update $entityId ${from.uid} '
          '${to.summary} ${to.status.name} ${to.description} ${to.due}');

  @override
  Future<String?> remove(String entityId, TodoItem item) =>
      _answer('remove $entityId ${item.uid}');

  @override
  Future<String?> clearCompleted(String entityId) =>
      _answer('clear $entityId');

  @override
  Future<String?> move(String entityId, String uid, {String? previousUid}) =>
      _answer('move $entityId $uid after $previousUid');
}

/// One stream per list; [push] sends a new state as HA's subscription would.
class FakeTodoLists {
  FakeTodoLists(Map<String, List<TodoItem>> initial) {
    for (final e in initial.entries) {
      _controllers[e.key] = StreamController<TodoListState>.broadcast();
      _latest[e.key] = TodoListState(items: e.value, status: ListStatus.ok);
    }
  }

  final _controllers = <String, StreamController<TodoListState>>{};
  final _latest = <String, TodoListState>{};

  void push(String entityId, List<TodoItem> items,
      {ListStatus status = ListStatus.ok, String? error}) {
    final state = TodoListState(items: items, status: status, error: error);
    _latest[entityId] = state;
    _controllers[entityId]!.add(state);
  }

  Stream<TodoListState> stream(String entityId) async* {
    final latest = _latest[entityId];
    if (latest == null) return;
    yield latest;
    yield* _controllers[entityId]!.stream;
  }
}

List<Override> listsOverrides({
  required List<HaEntity> entities,
  required FakeTodoLists lists,
  FakeTodoActions? actions,
}) =>
    [
      homeAssistantServiceProvider
          .overrideWithValue(FakeHomeAssistant(entities)),
      todoListProvider.overrideWith((ref, id) => lists.stream(id)),
      todoActionsProvider.overrideWithValue(actions ?? FakeTodoActions()),
    ];

TodoItem todo(
  String uid,
  String summary, {
  bool done = false,
  TodoDue? due,
  String? description,
}) =>
    TodoItem(
      uid: uid,
      summary: summary,
      status: done ? TodoStatus.completed : TodoStatus.needsAction,
      due: due,
      description: description,
    );

const kAvaChores = TodoListConfig(
    entityId: 'todo.ava', name: 'Ava', color: 0xFFE91E63, person: 'Ava');
const kBenChores = TodoListConfig(
    entityId: 'todo.ben', name: 'Ben', color: 0xFF2196F3, person: 'Ben');

/// Ava's and Ben's chore lists plus a plain one, glance on unless [glance].
HubConfig choreConfig({bool glance = true}) => HubConfig(
      haUrl: 'http://ha.invalid:8123',
      haToken: 'token',
      todoChoreGlance: glance,
      todoLists: const [
        kAvaChores,
        kBenChores,
        TodoListConfig(entityId: 'todo.groceries', name: 'Groceries'),
      ],
    );
