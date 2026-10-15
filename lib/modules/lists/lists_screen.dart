import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';
import 'lists_providers.dart';
import 'lists_widgets.dart';
import 'models.dart';
import 'todo_actions.dart';
import 'todo_edit_dialog.dart';

/// Below this width the rail folds into a dropdown in the header.
const kListsNarrowWidth = 900.0;

const _railWidth = 240.0;

/// A write in flight, drawn over the list until the push shows it.
class _Write {
  _Write(this.uids, this.apply);

  /// Rows that draw a spinner while it is pending.
  final Set<String> uids;

  /// What the list looks like once HA has it.
  final List<TodoItem> Function(List<TodoItem>) apply;

  /// HA said yes; dropped at the next push.
  bool settled = false;
}

/// The configured HA to-do lists: complete, add, edit, delete, reorder.
/// Nothing here uses a horizontal gesture; those belong to HubShell's
/// PageView.
class ListsScreen extends ConsumerStatefulWidget {
  const ListsScreen({super.key, this.isActive = false});

  final bool isActive;

  @override
  ConsumerState<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends ConsumerState<ListsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _selected;
  bool _showCompleted = false;
  final Map<String, List<_Write>> _writes = {};

  /// Pushes seen per list, so a write can tell one arrived while it waited.
  final Map<String, int> _pushes = {};
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keeps "today" and the overdue colour current.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  List<TodoItem> _items(String entityId) =>
      ref.read(todoListProvider(entityId)).valueOrNull?.items ?? const [];

  /// Draws [apply] at once and sends [send]. An error reverts it and shows
  /// HA's message; a success holds it until the push that carries it.
  Future<void> _write(
    String entityId,
    Set<String> uids,
    List<TodoItem> Function(List<TodoItem>) apply,
    Future<String?> Function(TodoActions) send,
  ) async {
    final write = _Write(uids, apply);
    final pushes = _pushes[entityId] ?? 0;
    setState(() => (_writes[entityId] ??= []).add(write));
    final error = await send(ref.read(todoActionsProvider));
    if (!mounted) return;
    setState(() {
      final current = _items(entityId);
      // call_service answers after the integration has written, so a push
      // that came in meanwhile is already the result.
      if (error != null ||
          _pushes[entityId] != pushes ||
          listEquals(apply(current), current)) {
        _writes[entityId]?.remove(write);
      } else {
        write.settled = true;
      }
    });
    if (error != null) _showError(error);
  }

  void _showError(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggle(String entityId, TodoItem item) {
    final to = TodoItem(
      uid: item.uid,
      summary: item.summary,
      status: item.status == TodoStatus.completed
          ? TodoStatus.needsAction
          : TodoStatus.completed,
      due: item.due,
      description: item.description,
      completed: item.completed,
    );
    _update(entityId, item, to);
  }

  void _update(String entityId, TodoItem from, TodoItem to) {
    final uid = from.uid!;
    _write(
      entityId,
      {uid},
      (items) => [for (final i in items) i.uid == uid ? to : i],
      (a) => a.update(entityId, from, to),
    );
  }

  void _remove(String entityId, TodoItem item) {
    final uid = item.uid!;
    _write(
      entityId,
      {uid},
      (items) => [for (final i in items) if (i.uid != uid) i],
      (a) => a.remove(entityId, item),
    );
  }

  Future<void> _addItem(String entityId) async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    _add.clear();
    _addFocus.requestFocus();
    final error = await ref.read(todoActionsProvider).add(entityId, text);
    if (!mounted || error == null) return;
    if (_add.text.isEmpty) _add.text = text;
    _showError(error);
  }

  Future<void> _clearCompleted(
      String entityId, String name, List<TodoItem> done) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear completed items?'),
        content: Text(
            'Removes ${done.length} completed '
            '${done.length == 1 ? 'item' : 'items'} from $name '
            'in Home Assistant.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _write(
      entityId,
      {for (final i in done) ?i.uid},
      (items) => [
        for (final i in items)
          if (i.status != TodoStatus.completed) i,
      ],
      (a) => a.clearCompleted(entityId),
    );
  }

  /// Sends the move with the uid of the open item now above it, as HA's
  /// card does; none at the top.
  void _reorder(String entityId, List<TodoItem> open, int from, int to) {
    if (to == from) return;
    final order = [...open];
    final moving = order.removeAt(from);
    order.insert(to, moving);
    String? previous;
    for (var i = to - 1; i >= 0 && previous == null; i--) {
      previous = order[i].uid;
    }
    final uid = moving.uid!;
    _write(
      entityId,
      {uid},
      (items) => _moved(items, uid, previous),
      (a) => a.move(entityId, uid, previousUid: previous),
    );
  }

  static List<TodoItem> _moved(
      List<TodoItem> items, String uid, String? previousUid) {
    final at = items.indexWhere((i) => i.uid == uid);
    if (at < 0) return items;
    final rest = [...items];
    final moving = rest.removeAt(at);
    final index = previousUid == null
        ? 0
        : rest.indexWhere((i) => i.uid == previousUid) + 1;
    return rest..insert(index, moving);
  }

  Future<void> _edit(
      String entityId, TodoItem item, TodoFeatures features) async {
    final use24h = ref.read(hubConfigProvider).use24HourClock;
    final edit = await showTodoEditDialog(
      context,
      item: item,
      features: features,
      use24h: use24h,
    );
    if (edit == null || !mounted) return;
    if (edit.delete) {
      _remove(entityId, item);
    } else if (edit.item != item) {
      _update(entityId, item, edit.item!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lists = ref.watch(hubConfigProvider.select((c) => c.todoLists));
    if (lists.isEmpty) return const _NotConfigured();
    final list = lists.firstWhere(
      (l) => l.entityId == _selected,
      orElse: () => lists.first,
    );
    final entityId = list.entityId;
    final ha = ref.watch(homeAssistantServiceProvider);
    final name = todoListName(list, ha.entities[entityId]);
    final features = ref.watch(todoFeaturesProvider(entityId));
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final state =
        ref.watch(todoListProvider(entityId)).valueOrNull ??
            const TodoListState();
    ref.listen(todoListProvider(entityId), (_, next) {
      if (!next.hasValue) return;
      _pushes[entityId] = (_pushes[entityId] ?? 0) + 1;
      final writes = _writes[entityId];
      if (writes == null || !writes.any((w) => w.settled)) return;
      setState(() => writes.removeWhere((w) => w.settled));
    });

    final writes = _writes[entityId] ?? const <_Write>[];
    var items = state.items;
    for (final w in writes) {
      items = w.apply(items);
    }
    final busy = {for (final w in writes) ...w.uids};
    final open = [
      for (final i in items)
        if (i.status == TodoStatus.needsAction) i,
    ];
    final done = [
      for (final i in items)
        if (i.status == TodoStatus.completed) i,
    ];

    Widget row(TodoItem item, {int? dragIndex}) {
      final uid = item.uid;
      return TodoItemRow(
        key: ValueKey('${item.status.name}:${uid ?? item.summary}'),
        item: item,
        now: _now,
        use24h: use24h,
        showCheckbox: features.canUpdate,
        busy: uid != null && busy.contains(uid),
        onToggle: uid == null ? null : () => _toggle(entityId, item),
        onTap: uid == null || !(features.canUpdate || features.canDelete)
            ? null
            : () => _edit(entityId, item, features),
        dragIndex: features.canMove && uid != null ? dragIndex : null,
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < kListsNarrowWidth;
          final body = CustomScrollView(
            slivers: [
              if (features.canAdd)
                SliverToBoxAdapter(
                  child: _AddField(
                    controller: _add,
                    focusNode: _addFocus,
                    onSubmit: () => _addItem(entityId),
                  ),
                ),
              if (state.status == ListStatus.loading && items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: HearthSpacing.allX8,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (items.isEmpty && state.status == ListStatus.ok)
                SliverToBoxAdapter(child: _Empty(name: name)),
              SliverReorderableList(
                itemCount: open.length,
                itemBuilder: (context, i) => row(open[i], dragIndex: i),
                onReorderItem: (from, to) => _reorder(entityId, open, from, to),
                proxyDecorator: (child, _, _) => Material(
                  color: const Color(0xFF1E1E1E),
                  elevation: 4,
                  child: child,
                ),
              ),
              if (done.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _showCompleted = !_showCompleted),
                    child: Padding(
                      padding: const EdgeInsets.all(HearthSpacing.x3),
                      child: Row(
                        children: [
                          Icon(
                            _showCompleted
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: HearthSpacing.x2),
                          Text(
                            'Completed (${done.length})',
                            style: const TextStyle(
                              fontSize: HearthFont.body,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showCompleted)
                  SliverList.list(children: [for (final i in done) row(i)]),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: HearthSpacing.x8),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                narrow: narrow,
                lists: lists,
                selected: list,
                title: name,
                onSelect: (id) => setState(() => _selected = id),
                onClearDone: features.canDelete && done.isNotEmpty
                    ? () => _clearCompleted(entityId, name, done)
                    : null,
              ),
              _StatusNote(state: state),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: narrow
                    ? body
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _railWidth,
                            child: _Rail(
                              lists: lists,
                              selected: entityId,
                              onSelect: (id) => setState(() => _selected = id),
                            ),
                          ),
                          const VerticalDivider(
                              width: 1, color: Colors.white12),
                          Expanded(child: body),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.checklist,
                size: HearthIcon.xxl,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: HearthSpacing.x4),
              Text(
                'Lists not configured',
                style: TextStyle(
                  fontSize: HearthFont.bodyLg,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: HearthSpacing.x2),
              Text(
                'Add a Home Assistant to-do list in Settings → Lists',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Padding(
        padding: HearthSpacing.allX8,
        child: Text(
          '$name is empty',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: HearthFont.body,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.narrow,
    required this.lists,
    required this.selected,
    required this.title,
    required this.onSelect,
    required this.onClearDone,
  });

  final bool narrow;
  final List<TodoListConfig> lists;
  final TodoListConfig selected;
  final String title;
  final void Function(String entityId) onSelect;
  final VoidCallback? onClearDone;

  @override
  Widget build(BuildContext context) {
    // The Lists/Chores switcher goes here once there is a Chores view.
    const view = Text(
      'Lists',
      style: TextStyle(
        fontSize: HearthFont.title,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    final Widget current = narrow
        ? Consumer(
            builder: (context, ref, _) {
              final ha = ref.watch(homeAssistantServiceProvider);
              return DropdownButton<String>(
                value: selected.entityId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                dropdownColor: const Color(0xFF1E1E1E),
                onChanged: (id) {
                  if (id != null) onSelect(id);
                },
                items: [
                  for (final l in lists)
                    DropdownMenuItem(
                      value: l.entityId,
                      child: _ListLabel(
                        color: Color(l.color),
                        name: todoListName(l, ha.entities[l.entityId]),
                      ),
                    ),
                ],
              );
            },
          )
        : Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: HearthFont.title,
              color: Colors.white,
            ),
          );

    // HubShell's mic toggle sits over the top-left corner of every page, so
    // the header starts clear of it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x20,
        HearthSpacing.x2,
        HearthSpacing.x3,
        HearthSpacing.x2,
      ),
      child: SizedBox(
        height: HearthSpacing.x12,
        child: Row(
          children: [
            if (narrow)
              view
            else
              const SizedBox(
                width: _railWidth - HearthSpacing.x20,
                child: Align(alignment: Alignment.centerLeft, child: view),
              ),
            const SizedBox(width: HearthSpacing.x4),
            Expanded(child: current),
            if (onClearDone != null)
              TextButton.icon(
                onPressed: onClearDone,
                icon: const Icon(Icons.done_all),
                label: const Text('Clear done'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListLabel extends StatelessWidget {
  const _ListLabel({required this.color, required this.name, this.count});

  final Color color;
  final String name;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: HearthSpacing.x3),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: HearthFont.bodyLg,
                color: Colors.white,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: HearthSpacing.x2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: HearthFont.body,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      );
}

/// Every list with its open count, which is the entity's state, so an
/// unselected list costs no subscription.
class _Rail extends ConsumerWidget {
  const _Rail({
    required this.lists,
    required this.selected,
    required this.onSelect,
  });

  final List<TodoListConfig> lists;
  final String selected;
  final void Function(String entityId) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ha = ref.watch(homeAssistantServiceProvider);
    ref.watch(haEntitiesProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.x2),
      children: [
        for (final l in lists)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HearthSpacing.x2,
              vertical: 2,
            ),
            child: Material(
              color: l.entityId == selected
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(HearthSpacing.x2),
              child: InkWell(
                borderRadius: BorderRadius.circular(HearthSpacing.x2),
                onTap: () => onSelect(l.entityId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.x3,
                    vertical: HearthSpacing.x3,
                  ),
                  child: _ListLabel(
                    color: Color(l.color),
                    name: todoListName(l, ha.entities[l.entityId]),
                    count: int.tryParse(ha.entities[l.entityId]?.state ?? ''),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Typing a new item. Enter adds it and keeps the field focused for the
/// next one.
class _AddField extends StatelessWidget {
  const _AddField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          HearthSpacing.x4,
          HearthSpacing.x3,
          HearthSpacing.x4,
          HearthSpacing.x2,
        ),
        child: TextField(
          key: const Key('lists-add'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.done,
          // Set so Enter does not drop focus.
          onEditingComplete: () {},
          onSubmitted: (_) => onSubmit(),
          style: const TextStyle(fontSize: HearthFont.bodyLg),
          decoration: InputDecoration(
            hintText: 'Add an item…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Add',
              icon: const Icon(Icons.add),
              onPressed: onSubmit,
            ),
          ),
        ),
      );
}

/// One line when the list is stale or failing, so an empty list reads as
/// "can't reach" rather than "nothing on it".
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.state});

  final TodoListState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state.status) {
      ListStatus.loading || ListStatus.ok => (null, null, null),
      ListStatus.stale => (
          Icons.history,
          Colors.amber,
          "Can't reach Home Assistant; showing the last items it sent",
        ),
      ListStatus.error => (
          Icons.error_outline,
          Colors.redAccent,
          state.error ?? "Can't load this list",
        ),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x4,
        0,
        HearthSpacing.x4,
        HearthSpacing.x1,
      ),
      child: Row(
        children: [
          Icon(icon, size: HearthIcon.xs, color: color),
          const SizedBox(width: HearthSpacing.x2),
          Expanded(
            child: Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HearthFont.label, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
