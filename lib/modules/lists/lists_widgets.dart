import 'package:flutter/material.dart';

import '../../app/tokens/tokens.dart';
import '../../models/ha_entity.dart';
import '../../utils/time_format.dart';
import 'models.dart';

const kListsAccent = Color(0xFF646CFF);

/// The configured name, else the entity's friendly_name.
String todoListName(TodoListConfig list, HaEntity? entity) =>
    list.name.isNotEmpty ? list.name : (entity?.name ?? list.entityId);

/// "today", "tomorrow", "Friday, Oct 16", with the time when it has one.
String todoDueLabel(TodoDue due, DateTime now, bool use24h) {
  final local = due.hasTime ? due.value.toLocal() : due.value;
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  final date = switch (days) {
    -1 => 'yesterday',
    0 => 'today',
    1 => 'tomorrow',
    _ => formatDateShort(day),
  };
  return due.hasTime ? '$date ${formatTime(local, use24h)}' : date;
}

/// Past due: before today for a date, before now for a datetime.
bool todoOverdue(TodoDue due, DateTime now) => due.hasTime
    ? due.value.isBefore(now)
    : due.value.isBefore(DateTime(now.year, now.month, now.day));

bool todoDueToday(TodoDue due, DateTime now) {
  final local = due.hasTime ? due.value.toLocal() : due.value;
  return local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
}

/// One item: checkbox, summary, due and description line, drag handle.
class TodoItemRow extends StatelessWidget {
  const TodoItemRow({
    super.key,
    required this.item,
    required this.now,
    required this.use24h,
    this.showCheckbox = true,
    this.busy = false,
    this.onToggle,
    this.onTap,
    this.dragIndex,
    this.late = false,
  });

  final TodoItem item;
  final DateTime now;
  final bool use24h;
  final bool showCheckbox;

  /// A write for this item is in flight.
  final bool busy;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  /// The item's index in the reorderable list; null draws no handle.
  final int? dragIndex;

  /// Tags the row "late", as the chore chart marks an overdue chore.
  final bool late;

  @override
  Widget build(BuildContext context) {
    final done = item.status == TodoStatus.completed;
    final due = item.due;
    final description = item.description?.split('\n').first.trim() ?? '';
    final muted = Colors.white.withValues(alpha: 0.5);
    final dueColor = due == null || done
        ? muted
        : todoOverdue(due, now)
            ? Colors.redAccent
            : todoDueToday(due, now)
                ? kListsAccent
                : muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.x2,
          vertical: HearthSpacing.x1,
        ),
        child: Row(
          children: [
            if (showCheckbox)
              Checkbox(
                value: done,
                activeColor: kListsAccent,
                onChanged: onToggle == null ? null : (_) => onToggle!(),
              )
            else
              const SizedBox(width: HearthSpacing.x3),
            const SizedBox(width: HearthSpacing.x2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: HearthSpacing.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HearthFont.bodyLg,
                        color: done ? muted : Colors.white,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (due != null || description.isNotEmpty)
                      Text.rich(
                        TextSpan(children: [
                          if (due != null)
                            TextSpan(
                              text: 'due ${todoDueLabel(due, now, use24h)}',
                              style: TextStyle(color: dueColor),
                            ),
                          if (due != null && description.isNotEmpty)
                            const TextSpan(text: ' · '),
                          if (description.isNotEmpty)
                            TextSpan(text: description),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: HearthFont.label, color: muted),
                      ),
                  ],
                ),
              ),
            ),
            if (late)
              const Padding(
                padding: EdgeInsets.only(left: HearthSpacing.x2),
                child: Text(
                  'late',
                  style: TextStyle(
                    fontSize: HearthFont.label,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            if (busy)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
                child: SizedBox(
                  width: HearthIcon.xs,
                  height: HearthIcon.xs,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: Padding(
                  padding: const EdgeInsets.all(HearthSpacing.x3),
                  child: Icon(Icons.drag_handle, color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
