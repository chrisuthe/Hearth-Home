import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens/tokens.dart';
import 'lists_providers.dart';
import 'models.dart';

/// The narrowest a person's column gets before the chart wraps.
const kChoreColumnWidth = 260.0;

/// One person's chores, sorted into the chart's sections.
class ChoreColumn {
  ChoreColumn(this.person, this.color);

  final String person;

  /// The person's first list's colour.
  final Color color;

  /// Open and due today or late; late first.
  final due = <ChoreLine>[];
  final undated = <ChoreLine>[];

  /// Completed today, by HA's `completed`.
  final doneToday = <ChoreLine>[];

  /// Open and due after today.
  final upcoming = <ChoreLine>[];

  int get total => due.length + undated.length + doneToday.length;
}

/// One column per person, in config order, merging that person's lists.
/// A completed item without a `completed` time is left out; the Lists view
/// has it.
List<ChoreColumn> choreColumns(
  List<TodoListConfig> lists,
  List<TodoItem> Function(String entityId) items,
  DateTime now,
) {
  final columns = <String, ChoreColumn>{};
  final today = <String, List<ChoreLine>>{};
  for (final list in lists.where((l) => l.isChore)) {
    final column = columns[list.person] ??= ChoreColumn(
      list.person,
      Color(list.color),
    );
    final dueToday = today[list.person] ??= [];
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
    final lines = today[column.person]!;
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
              if (start > 0) const Divider(height: 1, color: Colors.white12),
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
                        const VerticalDivider(width: 1, color: Colors.white12),
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
    final muted = Colors.white.withValues(alpha: 0.5);
    final open = _expanded.contains(column.person);
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
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: column.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: HearthSpacing.x3),
              Expanded(
                child: Text(
                  column.person,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: HearthFont.bodyLg,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
                  ? _expanded.remove(column.person)
                  : _expanded.add(column.person),
            ),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.x3),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: HearthSpacing.x2),
                  Text(
                    'Upcoming (${column.upcoming.length})',
                    style: const TextStyle(
                      fontSize: HearthFont.body,
                      color: Colors.white70,
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
