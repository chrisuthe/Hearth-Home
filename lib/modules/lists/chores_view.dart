import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/tokens/tokens.dart';
import '../../config/person.dart';
import '../../services/people.dart';
import '../../widgets/person_avatar.dart';
import 'lists_providers.dart';
import 'models.dart';

/// The narrowest a person's column gets before the chart wraps.
const kChoreColumnWidth = 260.0;

/// One person's chores, sorted into the chart's sections.
class ChoreColumn {
  ChoreColumn(this.person);

  final Person person;

  Color get color => Color(person.color);

  /// Open and due today or late; late first.
  final due = <ChoreLine>[];
  final undated = <ChoreLine>[];

  /// Completed today, by HA's `completed`.
  final doneToday = <ChoreLine>[];

  /// Open and due after today.
  final upcoming = <ChoreLine>[];

  int get total => due.length + undated.length + doneToday.length;
}

/// One column per person, in the order their first list comes, merging that
/// person's lists. A list whose person is not in [people] is left out, as is
/// a completed item without a `completed` time; the Lists view has both.
List<ChoreColumn> choreColumns(
  List<TodoListConfig> lists,
  List<Person> people,
  List<TodoItem> Function(String entityId) items,
  DateTime now,
) {
  final columns = <String, ChoreColumn>{};
  final today = <String, List<ChoreLine>>{};
  for (final list in lists.where((l) => l.isChore)) {
    final person = personById(people, list.personId);
    if (person == null) continue;
    final column = columns[person.id] ??= ChoreColumn(person);
    final dueToday = today[person.id] ??= [];
    for (final item in items(list.entityId)) {
      if (item.status == TodoStatus.completed) {
        final at = item.completed?.toLocal();
        if (at != null &&
            at.year == now.year &&
            at.month == now.month &&
            at.day == now.day) {
          column.doneToday.add(ChoreLine(list, item, late: false));
        }
      } else if (item.due == null) {
        column.undated.add(ChoreLine(list, item, late: false));
      } else {
        final chore = choreToday(item, now);
        if (chore == null) {
          column.upcoming.add(ChoreLine(list, item, late: false));
        } else {
          dueToday.add(ChoreLine(list, item, late: chore.late));
        }
      }
    }
  }
  for (final column in columns.values) {
    final lines = today[column.person.id]!;
    column.due
      ..addAll(lines.where((l) => l.late))
      ..addAll(lines.where((l) => !l.late));
  }
  return columns.values.toList();
}

/// The chore chart: a column per person, wrapping into more rows when the
/// width runs out. Doing chores only; adding and editing are the Lists
/// view's.
class ChoresView extends StatefulWidget {
  const ChoresView({super.key, required this.columns, required this.row});

  final List<ChoreColumn> columns;
  final Widget Function(ChoreLine line) row;

  @override
  State<ChoresView> createState() => _ChoresViewState();
}

class _ChoresViewState extends State<ChoresView> {
  /// People whose Upcoming is open.
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final columns = widget.columns;
    return LayoutBuilder(
      builder: (context, c) {
        final across = math.min(
          math.max(c.maxWidth ~/ kChoreColumnWidth, 1),
          columns.length,
        );
        return ListView(
          padding: const EdgeInsets.only(bottom: HearthSpacing.x8),
          children: [
            for (var start = 0; start < columns.length; start += across) ...[
              if (start > 0)
                Divider(height: 1, color: context.hearthColors.inkAt(0.12)),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < math.min(start + across, columns.length);
                      i++
                    ) ...[
                      if (i > start)
                        VerticalDivider(width: 1, color: context.hearthColors.inkAt(0.12)),
                      Expanded(child: _column(columns[i])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _column(ChoreColumn column) {
    final hc = context.hearthColors;
    final muted = hc.inkAt(0.5);
    final id = column.person.id;
    final open = _expanded.contains(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HearthSpacing.x4,
            HearthSpacing.x3,
            HearthSpacing.x4,
            HearthSpacing.x1,
          ),
          child: Row(
            children: [
              ChorePersonMark(person: column.person, size: 28),
              const SizedBox(width: HearthSpacing.x3),
              Expanded(
                child: Text(
                  column.person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HearthFont.bodyLg,
                    fontWeight: FontWeight.w600,
                    color: hc.text,
                  ),
                ),
              ),
              const SizedBox(width: HearthSpacing.x2),
              Text(
                '${column.doneToday.length}/${column.total}',
                style: TextStyle(fontSize: HearthFont.body, color: muted),
              ),
            ],
          ),
        ),
        for (final line in column.due) widget.row(line),
        for (final line in column.undated) widget.row(line),
        for (final line in column.doneToday) widget.row(line),
        if (column.total == 0)
          Padding(
            padding: const EdgeInsets.all(HearthSpacing.x4),
            child: Text(
              'Nothing for today',
              style: TextStyle(fontSize: HearthFont.body, color: muted),
            ),
          ),
        if (column.upcoming.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(
              () => open
                  ? _expanded.remove(id)
                  : _expanded.add(id),
            ),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.x3),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    color: hc.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.x2),
                  Text(
                    'Upcoming (${column.upcoming.length})',
                    style: TextStyle(
                      fontSize: HearthFont.body,
                      color: hc.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final line in column.upcoming) widget.row(line),
        ],
      ],
    );
  }
}

/// A linked person's avatar and presence; an unlinked person's colour dot.
class ChorePersonMark extends ConsumerWidget {
  const ChorePersonMark({super.key, required this.person, required this.size});

  final Person person;

  /// The avatar's; the dot is less than half of it.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (person.isLinked) {
      final view = ref.watch(personViewProvider(person.id));
      return PersonAvatar(view: view ?? PersonView(person), size: size);
    }
    final dot = (size * 0.43).roundToDouble();
    return SizedBox(
      width: dot,
      height: dot,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(person.color),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
