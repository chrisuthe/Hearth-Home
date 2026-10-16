import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/tokens/tokens.dart';
import '../../widgets/themed_background.dart';
import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';
import '../../utils/time_format.dart';
import 'chores_view.dart';
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

/// The configured HA to-do lists: complete, add, edit, delete, reorder;
/// and, once a list has a person, the chore chart. Nothing here uses a
/// horizontal gesture; those belong to HubShell's PageView.
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

  /// The lists on screen at the last build.
  Set<String> _shown = const {};
  bool _showCompleted = false;
  final Map<String, List<_Write>> _writes = {};

  /// Pushes seen per list, so a write can tell one arrived while it waited.
  final Map<String, int> _pushes = {};
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  late DateTime _now = _clockNow();
  Timer? _clock;

  DateTime _clockNow() => ref.read(todoNowProvider)();

  @override
  void initState() {
    super.initState();
    // Keeps "today", "late" and the overdue colour current.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = _clockNow());
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
      // call_service answers after the integration has written, so a push
      // that came in meanwhile is already the result. A list no longer shown
      // resubscribes, fresh, when it is shown again.
      if (error != null ||
          !_shown.contains(entityId) ||
          _pushes[entityId] != pushes ||
          listEquals(apply(_items(entityId)), _items(entityId))) {
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
    final completing = item.status != TodoStatus.completed;
    final to = TodoItem(
      uid: item.uid,
      summary: item.summary,
      status: completing ? TodoStatus.completed : TodoStatus.needsAction,
      due: item.due,
      description: item.description,
      // Drawn as HA will stamp it, so the chart keeps it under done today.
      completed: completing ? _clockNow().toUtc() : null,
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

  /// [entityId]'s state, with the writes in flight drawn over its items and
  /// the uids they hold busy. Also counts its pushes, and drops the writes a
  /// push settles.
  ({TodoListState state, List<TodoItem> items, Set<String> busy}) _watchList(
      String entityId) {
    ref.listen(todoListProvider(entityId), (_, next) {
      if (!next.hasValue) return;
      _pushes[entityId] = (_pushes[entityId] ?? 0) + 1;
      final writes = _writes[entityId];
      if (writes == null || !writes.any((w) => w.settled)) return;
      setState(() => writes.removeWhere((w) => w.settled));
    });
    final state = ref.watch(todoListProvider(entityId)).valueOrNull ??
        const TodoListState();
    final writes = _writes[entityId] ?? const <_Write>[];
    var items = state.items;
    for (final w in writes) {
      items = w.apply(items);
    }
    return (
      state: state,
      items: items,
      busy: {for (final w in writes) ...w.uids},
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lists = ref.watch(hubConfigProvider.select((c) => c.todoLists));
    if (lists.isEmpty) return const _NotConfigured();
    final hasChores = lists.any((l) => l.isChore);
    final view = hasChores ? ref.watch(listsViewProvider) : ListsView.lists;
    final switcher = _ViewSwitch(
      view: view,
      onChanged: hasChores
          ? (v) => ref.read(listsViewProvider.notifier).state = v
          : null,
    );
    return ThemedBackground.screen(
      child: view == ListsView.chores
          ? _buildChores(lists, switcher)
          : _buildLists(lists, switcher),
    );
  }

  Widget _buildChores(List<TodoListConfig> lists, _ViewSwitch switcher) {
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final chores = [for (final l in lists) if (l.isChore) l];
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    _shown = {for (final l in chores) l.entityId};
    final watched = {for (final l in chores) l.entityId: _watchList(l.entityId)};
    final features = {
      for (final l in chores) l.entityId: ref.watch(todoFeaturesProvider(l.entityId)),
    };
    final states = [for (final w in watched.values) w.state];
    final note = states.firstWhere(
      (s) => s.status == ListStatus.error || s.status == ListStatus.stale,
      orElse: () => const TodoListState(status: ListStatus.ok),
    );
    final loading = states.every(
        (s) => s.status == ListStatus.loading && s.items.isEmpty);

    Widget row(ChoreLine line) {
      final entityId = line.list.entityId;
      final item = line.item;
      final uid = item.uid;
      final canUpdate = features[entityId]!.canUpdate;
      final toggle =
          uid == null || !canUpdate ? null : () => _toggle(entityId, item);
      return TodoItemRow(
        item: item,
        now: _now,
        use24h: use24h,
        showCheckbox: canUpdate,
        busy: uid != null && watched[entityId]!.busy.contains(uid),
        late: line.late,
        onToggle: toggle,
        onTap: toggle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          switcher: switcher,
          wide: false,
          current: Text(
            formatDateShort(_now),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: HearthFont.bodyLg,
              color: context.hearthColors.textSecondary,
            ),
          ),
        ),
        _StatusNote(state: note),
        Divider(height: 1, color: context.hearthColors.inkAt(0.12)),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ChoresView(
                  columns: choreColumns(chores, people,
                      (id) => watched[id]!.items, _now),
                  row: row,
                ),
        ),
      ],
    );
  }

  Widget _buildLists(List<TodoListConfig> lists, _ViewSwitch switcher) {
    final list = lists.firstWhere(
      (l) => l.entityId == _selected,
      orElse: () => lists.first,
    );
    final entityId = list.entityId;
    _shown = {entityId};
    final ha = ref.watch(homeAssistantServiceProvider);
    final name = todoListName(list, ha.entities[entityId]);
    final features = ref.watch(todoFeaturesProvider(entityId));
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final (:state, :items, :busy) = _watchList(entityId);
    final open = [
      for (final i in items)
        if (i.status == TodoStatus.needsAction) i,
    ];
    final done = [
      for (final i in items)
        if (i.status == TodoStatus.completed) i,
    ];

    Widget row(TodoItem item, int index, {bool reorderable = false}) {
      final uid = item.uid;
      return TodoItemRow(
        // HA may send items without a uid, and two can share a summary.
        key: ValueKey('${item.status.name}:${uid ?? '#$index'}'),
        item: item,
        now: _now,
        use24h: use24h,
        showCheckbox: features.canUpdate,
        busy: uid != null && busy.contains(uid),
        onToggle: uid == null ? null : () => _toggle(entityId, item),
        onTap: uid == null || !(features.canUpdate || features.canDelete)
            ? null
            : () => _edit(entityId, item, features),
        dragIndex: reorderable && features.canMove && uid != null ? index : null,
      );
    }

    return LayoutBuilder(
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
              itemBuilder: (context, i) => row(open[i], i, reorderable: true),
              onReorderItem: (from, to) => _reorder(entityId, open, from, to),
              proxyDecorator: (child, _, _) => Material(
                color: context.hearthColors.raised,
                elevation: 4,
                child: child,
              ),
            ),
            if (done.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: InkWell(
                  onTap: () => setState(() => _showCompleted = !_showCompleted),
                  child: Padding(
                    padding: const EdgeInsets.all(HearthSpacing.x3),
                    child: Row(
                      children: [
                        Icon(
                          _showCompleted
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          color: context.hearthColors.textMuted,
                        ),
                        const SizedBox(width: HearthSpacing.x2),
                        Text(
                          'Completed (${done.length})',
                          style: TextStyle(
                            fontSize: HearthFont.body,
                            color: context.hearthColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_showCompleted)
                SliverList.list(children: [
                  for (final (i, item) in done.indexed) row(item, i),
                ]),
            ],
            const SliverToBoxAdapter(
              child: SizedBox(height: HearthSpacing.x8),
            ),
          ],
        );

        final Widget current = narrow
            ? _ListDropdown(
                lists: lists,
                selected: entityId,
                onSelect: (id) => setState(() => _selected = id),
              )
            : Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HearthFont.title,
                  color: context.hearthColors.text,
                ),
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              switcher: switcher,
              wide: !narrow,
              current: current,
              onClearDone: features.canDelete && done.isNotEmpty
                  ? () => _clearCompleted(entityId, name, done)
                  : null,
            ),
            _StatusNote(state: state),
            Divider(height: 1, color: context.hearthColors.inkAt(0.12)),
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
                        VerticalDivider(width: 1, color: context.hearthColors.inkAt(0.12)),
                        Expanded(child: body),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => ThemedBackground.screen(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.checklist,
                size: HearthIcon.xxl,
                color: context.hearthColors.inkAt(0.2),
              ),
              const SizedBox(height: HearthSpacing.x4),
              Text(
                'Lists not configured',
                style: TextStyle(
                  fontSize: HearthFont.bodyLg,
                  color: context.hearthColors.textMuted,
                ),
              ),
              const SizedBox(height: HearthSpacing.x2),
              Text(
                'Add a Home Assistant to-do list in Settings → Lists',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.hearthColors.inkAt(0.3),
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
            color: context.hearthColors.textMuted,
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.switcher,
    required this.wide,
    required this.current,
    this.onClearDone,
  });

  final _ViewSwitch switcher;

  /// Lines the title up over the list, clear of the rail.
  final bool wide;
  final Widget current;
  final VoidCallback? onClearDone;

  @override
  Widget build(BuildContext context) {
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
            // The Lists | Chores switch is wider than the rail.
            if (wide && switcher.onChanged == null)
              SizedBox(
                width: _railWidth - HearthSpacing.x20,
                child: Align(alignment: Alignment.centerLeft, child: switcher),
              )
            else
              switcher,
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

/// "Lists", or the Lists | Chores switch once a list has a person.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.onChanged});

  final ListsView view;

  /// Null when there is no chore list, so no Chores view.
  final ValueChanged<ListsView>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return Text(
        'Lists',
        style: TextStyle(
          fontSize: HearthFont.title,
          fontWeight: FontWeight.w600,
          color: context.hearthColors.text,
        ),
      );
    }
    return SegmentedButton<ListsView>(
      segments: const [
        ButtonSegment(value: ListsView.lists, label: Text('Lists')),
        ButtonSegment(value: ListsView.chores, label: Text('Chores')),
      ],
      selected: {view},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.single),
    );
  }
}

/// The rail, folded into the header on a narrow screen.
class _ListDropdown extends ConsumerWidget {
  const _ListDropdown({
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
    return DropdownButton<String>(
      value: selected,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      dropdownColor: context.hearthColors.raised,
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
              style: TextStyle(
                fontSize: HearthFont.bodyLg,
                color: context.hearthColors.text,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: HearthSpacing.x2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: HearthFont.body,
                color: context.hearthColors.textMuted,
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
                  ? context.hearthColors.inkAt(0.1)
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
    final c = context.hearthColors;
    final (icon, color, text) = switch (state.status) {
      ListStatus.loading || ListStatus.ok => (null, null, null),
      ListStatus.stale => (
          Icons.history,
          c.warning,
          "Can't reach Home Assistant; showing the last items it sent",
        ),
      ListStatus.error => (
          Icons.error_outline,
          c.danger,
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
