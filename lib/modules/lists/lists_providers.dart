import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';
import 'ha_todo_list.dart';
import 'models.dart';
import 'todo_actions.dart';

/// Items of one configured list. autoDispose, so a list is subscribed only
/// while a view or the glance watches it.
final todoListProvider =
    StreamProvider.autoDispose.family<TodoListState, String>((ref, entityId) {
  final listed = ref.watch(hubConfigProvider
      .select((c) => c.todoLists.any((l) => l.entityId == entityId)));
  if (!listed) {
    return Stream.value(const TodoListState(
        status: ListStatus.error, error: 'List not configured'));
  }
  final haUrl = ref.watch(hubConfigProvider.select((c) => c.haUrl));
  final haToken = ref.watch(hubConfigProvider.select((c) => c.haToken));
  if (haUrl.isEmpty || haToken.isEmpty) {
    return Stream.value(const TodoListState(
        status: ListStatus.error, error: 'Home Assistant is not configured'));
  }
  final list = HaTodoList(
      ha: ref.watch(homeAssistantServiceProvider), entityId: entityId);
  ref.onDispose(list.dispose);
  return list.stream;
});

/// What a list supports, from the entity's `supported_features`; none until
/// the entity reaches the cache. Notifies only when the bits change.
final todoFeaturesProvider =
    Provider.family<TodoFeatures, String>((ref, entityId) {
  final ha = ref.watch(homeAssistantServiceProvider);
  ref.watch(haEntitiesProvider);
  return TodoFeatures.of(ha.entities[entityId]);
});

final todoActionsProvider = Provider<TodoActions>((ref) => TodoActions(
      ref.watch(homeAssistantServiceProvider),
      (entityId) => ref.read(todoFeaturesProvider(entityId)),
    ));

enum ListsView { lists, chores }

/// Which view the Lists screen shows. Outside the screen so the glance can
/// open it on Chores.
final listsViewProvider = StateProvider<ListsView>((ref) => ListsView.lists);

/// The clock [choresTodayProvider] reads; tests override it.
final todoNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// An open chore that is due today or late.
class ChoreLine {
  final TodoListConfig list;
  final TodoItem item;
  final bool late;

  const ChoreLine(this.list, this.item, {required this.late});

  @override
  bool operator ==(Object other) =>
      other is ChoreLine &&
      other.list == list &&
      other.item == item &&
      other.late == late;

  @override
  int get hashCode => Object.hash(list, item, late);
}

/// Whether [item] is one of today's chores at [now], and whether it is late;
/// null when it is not. A date is due through the end of that local day, a
/// datetime at its instant; an undated or completed item is never today's.
({bool late})? choreToday(TodoItem item, DateTime now) {
  final due = item.due;
  if (item.status == TodoStatus.completed || due == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  if (due.hasTime) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (!due.value.isBefore(tomorrow)) return null;
    return (late: !due.value.isAfter(now));
  }
  if (due.value.isAfter(today)) return null;
  return (late: due.value.isBefore(today));
}

/// Today's open chores across every chore list: late ones first, then
/// config order, then HA's order. Recomputed at local midnight and when a
/// timed chore falls due, so lines turn late without a push.
final choresTodayProvider = Provider.autoDispose<List<ChoreLine>>((ref) {
  final lists = ref.watch(hubConfigProvider.select((c) => c.todoLists));
  final now = ref.watch(todoNowProvider)();
  var next = DateTime(now.year, now.month, now.day + 1);

  final late = <ChoreLine>[];
  final today = <ChoreLine>[];
  for (final list in lists.where((l) => l.isChore)) {
    final state = ref.watch(todoListProvider(list.entityId)).valueOrNull;
    for (final item in state?.items ?? const <TodoItem>[]) {
      final chore = choreToday(item, now);
      if (chore == null) continue;
      (chore.late ? late : today).add(ChoreLine(list, item, late: chore.late));
      final due = item.due!;
      if (due.hasTime && !chore.late && due.value.isBefore(next)) {
        next = due.value;
      }
    }
  }

  final timer = Timer(
      next.difference(now) + const Duration(seconds: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return [...late, ...today];
});
