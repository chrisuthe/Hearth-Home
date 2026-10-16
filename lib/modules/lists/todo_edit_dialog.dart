import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/tokens/tokens.dart';
import 'lists_widgets.dart';
import 'models.dart';

/// What the edit dialog asked for: the edited item, or a delete.
class TodoEdit {
  const TodoEdit.save(TodoItem this.item) : delete = false;
  const TodoEdit.delete()
      : item = null,
        delete = true;

  final TodoItem? item;
  final bool delete;
}

/// Edits one item. A field the list does not support is absent, so it is
/// never sent; null when the dialog is dismissed.
Future<TodoEdit?> showTodoEditDialog(
  BuildContext context, {
  required TodoItem item,
  required TodoFeatures features,
  required bool use24h,
}) =>
    showDialog<TodoEdit>(
      context: context,
      builder: (_) =>
          TodoEditDialog(item: item, features: features, use24h: use24h),
    );

class TodoEditDialog extends StatefulWidget {
  const TodoEditDialog({
    super.key,
    required this.item,
    required this.features,
    required this.use24h,
  });

  final TodoItem item;
  final TodoFeatures features;
  final bool use24h;

  @override
  State<TodoEditDialog> createState() => _TodoEditDialogState();
}

class _TodoEditDialogState extends State<TodoEditDialog> {
  late final _name = TextEditingController(text: widget.item.summary);
  late final _description =
      TextEditingController(text: widget.item.description ?? '');
  late TodoDue? _due = widget.item.due;

  TodoFeatures get _features => widget.features;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final item = widget.item;
    final name = _name.text.trim();
    final description = _description.text;
    Navigator.of(context).pop(TodoEdit.save(TodoItem(
      uid: item.uid,
      summary: name.isEmpty ? item.summary : name,
      status: item.status,
      due: _due,
      // An empty field over no description is no change.
      description: description.isEmpty && (item.description ?? '').isEmpty
          ? item.description
          : description,
      completed: item.completed,
    )));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final last = DateTime(now.year + 10, 12, 31);
    final current = _due == null
        ? now
        : (_due!.hasTime ? _due!.value.toLocal() : _due!.value);
    final day = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) || current.isAfter(last) ? now : current,
      firstDate: first,
      lastDate: last,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (day == null || !mounted) return;
    if (_due?.hasTime == true) {
      final t = _due!.value.toLocal();
      setState(() => _due = TodoDue.instant(
          DateTime(day.year, day.month, day.day, t.hour, t.minute)));
    } else if (_features.canSetDueDate) {
      setState(() => _due = TodoDue.date(day));
    } else {
      // The list only takes a datetime.
      await _pickTime(day);
    }
  }

  Future<void> _pickTime([DateTime? day]) async {
    final base = day ??
        (_due == null
            ? DateTime.now()
            : (_due!.hasTime ? _due!.value.toLocal() : _due!.value));
    final initial = _due?.hasTime == true
        ? TimeOfDay.fromDateTime(_due!.value.toLocal())
        : const TimeOfDay(hour: 9, minute: 0);
    final time = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dialOnly,
    );
    if (time == null || !mounted) return;
    setState(() => _due = TodoDue.instant(
        DateTime(base.year, base.month, base.day, time.hour, time.minute)));
  }

  @override
  Widget build(BuildContext context) {
    final f = _features;
    final canDue = f.canUpdate && (f.canSetDueDate || f.canSetDueTime);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final c = context.hearthColors;
    final muted = c.inkAt(0.6);

    return Dialog(
      insetPadding: narrow
          ? const EdgeInsets.symmetric(
              horizontal: HearthSpacing.x2, vertical: HearthSpacing.x6)
          : const EdgeInsets.symmetric(
              horizontal: HearthSpacing.x10, vertical: HearthSpacing.x6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: HearthSpacing.allX6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (f.canUpdate)
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: const TextStyle(fontSize: HearthFont.title),
                  decoration: const InputDecoration(labelText: 'Name'),
                )
              else
                Text(
                  widget.item.summary,
                  style: TextStyle(
                    fontSize: HearthFont.title,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              if (f.canUpdate && f.canSetDescription) ...[
                const SizedBox(height: HearthSpacing.x4),
                TextField(
                  controller: _description,
                  keyboardType: TextInputType.multiline,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
              if (canDue) ...[
                const SizedBox(height: HearthSpacing.x4),
                Row(
                  children: [
                    Icon(Icons.event, size: HearthIcon.sm, color: muted),
                    const SizedBox(width: HearthSpacing.x3),
                    Expanded(
                      child: Text(
                        _due == null
                            ? 'No due date'
                            : 'Due ${todoDueLabel(_due!, DateTime.now(), widget.use24h)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: HearthFont.body),
                      ),
                    ),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Clear due date',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _due = null),
                      ),
                  ],
                ),
                Wrap(
                  spacing: HearthSpacing.x2,
                  children: [
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Date'),
                    ),
                    if (f.canSetDueTime)
                      TextButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule),
                        label: const Text('Time'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: HearthSpacing.x6),
              Row(
                children: [
                  if (f.canDelete)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(const TodoEdit.delete()),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      label: const Text('Delete',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  if (f.canUpdate) ...[
                    const SizedBox(width: HearthSpacing.x2),
                    FilledButton(onPressed: _save, child: const Text('Save')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
