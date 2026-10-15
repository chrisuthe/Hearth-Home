import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../modules/lists/lists_providers.dart';
import '../../modules/lists/models.dart';
import '../../services/home_assistant_service.dart';
import '../calendar/calendar_settings_section.dart'
    show CalendarColorPicker, CalendarSwatch;
import '../calendar/calendar_sources.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/list_section.dart';
import 'todo_lists.dart';

const _accent = Color(0xFF646CFF);
const _dialogBackground = Color(0xFF1A1A1A);
const _labelStyle = TextStyle(color: Colors.white54);

const todoChoreGlanceField = BoolSettingField(
  label: "Show today's chores when idle",
  configPath: 'todoChoreGlance',
);

/// The Lists plugin's on-device panel.
class ListsSettingsSection extends ConsumerWidget {
  const ListsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(hubConfigProvider.select((c) => c.todoLists));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection<TodoListConfig>(
          label: 'Lists',
          items: lists,
          summaryFor: (l) => l.name,
          leadingFor: (l) => CalendarSwatch(color: l.color),
          subtitleFor: (l) => _ListStatusLine(list: l),
          onListChanged: (list) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(todoLists: list)),
          editorBuilder: (context, existing) => showDialog<TodoListConfig>(
            context: context,
            builder: (_) => existing == null
                ? const _AddListDialog()
                : _EditListDialog(list: existing),
          ),
        ).buildWidget(context, ref),
        todoChoreGlanceField.buildWidget(ref),
      ],
    );
  }
}

class _ListStatusLine extends ConsumerWidget {
  final TodoListConfig list;
  const _ListStatusLine({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(haEntitiesProvider);
    final config = ref.watch(hubConfigProvider);
    final status = todoListStatus(
      config,
      ref.watch(homeAssistantServiceProvider),
      list.entityId,
    );
    final features = todoFeaturesLabel(
      ref.watch(todoFeaturesProvider(list.entityId)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${todoListKindLabel(list)} · ${status.label}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: status.bad ? Colors.orangeAccent : Colors.white54,
            fontSize: 12,
          ),
        ),
        if (features.isNotEmpty)
          Text(
            features,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
      ],
    );
  }
}

/// Name, person and colour: the fields add and edit share.
List<Widget> _fields({
  required TextEditingController name,
  required TextEditingController person,
  required int color,
  required ValueChanged<int> onColor,
}) => [
  TextField(
    key: const ValueKey('list-name'),
    controller: name,
    style: const TextStyle(color: Colors.white),
    decoration: const InputDecoration(
      labelText: 'Name',
      labelStyle: _labelStyle,
    ),
  ),
  TextField(
    key: const ValueKey('list-person'),
    controller: person,
    style: const TextStyle(color: Colors.white),
    decoration: const InputDecoration(
      labelText: 'Person',
      helperText:
          "Blank for a plain list; a name makes it that "
          "person's chores",
      labelStyle: _labelStyle,
      helperStyle: TextStyle(color: Colors.white38),
    ),
  ),
  const SizedBox(height: 16),
  const Text('Colour', style: _labelStyle),
  const SizedBox(height: 6),
  CalendarColorPicker(selected: color, onChanged: onColor),
];

AlertDialog _dialog(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  required String action,
  required VoidCallback? onAction,
}) => AlertDialog(
  backgroundColor: _dialogBackground,
  title: Text(title, style: const TextStyle(color: Colors.white)),
  content: SizedBox(
    width: 420,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  ),
  actions: [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
    ),
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: _accent),
      onPressed: onAction,
      child: Text(action),
    ),
  ],
);

class _AddListDialog extends ConsumerStatefulWidget {
  const _AddListDialog();

  @override
  ConsumerState<_AddListDialog> createState() => _AddListDialogState();
}

class _AddListDialogState extends ConsumerState<_AddListDialog> {
  final _name = TextEditingController();
  final _person = TextEditingController();
  HaEntity? _entity;
  late int _color;

  @override
  void initState() {
    super.initState();
    _color = nextFreePaletteColor([
      for (final l in ref.read(hubConfigProvider).todoLists) l.color,
    ]);
  }

  @override
  void dispose() {
    _name.dispose();
    _person.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final added = {
      for (final l in ref.read(hubConfigProvider).todoLists) l.entityId,
    };
    final entities =
        ref
            .read(homeAssistantServiceProvider)
            .entities
            .values
            .where((e) => e.domain == 'todo' && !added.contains(e.entityId))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final entity = _entity;
    return _dialog(
      context,
      title: 'Add list',
      action: 'Add',
      onAction: entity == null
          ? null
          : () {
              final name = _name.text.trim();
              Navigator.of(context).pop(
                TodoListConfig(
                  entityId: entity.entityId,
                  name: name.isEmpty ? entity.name : name,
                  color: _color,
                  person: _person.text.trim(),
                ),
              );
            },
      children: [
        if (entities.isEmpty)
          const Text(
            'No lists to add. Is Home Assistant connected, and does it have '
            'to-do entities?',
            style: TextStyle(color: Colors.white70),
          )
        else
          DropdownButton<HaEntity>(
            key: const ValueKey('list-entity'),
            value: entity,
            isExpanded: true,
            hint: const Text('To-do entity', style: _labelStyle),
            dropdownColor: _dialogBackground,
            style: const TextStyle(color: Colors.white),
            items: [
              for (final e in entities)
                DropdownMenuItem(
                  value: e,
                  child: Text('${e.name} (${e.entityId})'),
                ),
            ],
            onChanged: (e) {
              if (e != null) {
                setState(() {
                  _entity = e;
                  _name.text = e.name;
                });
              }
            },
          ),
        ..._fields(
          name: _name,
          person: _person,
          color: _color,
          onColor: (c) => setState(() => _color = c),
        ),
      ],
    );
  }
}

class _EditListDialog extends StatefulWidget {
  final TodoListConfig list;
  const _EditListDialog({required this.list});

  @override
  State<_EditListDialog> createState() => _EditListDialogState();
}

class _EditListDialogState extends State<_EditListDialog> {
  late final _name = TextEditingController(text: widget.list.name);
  late final _person = TextEditingController(text: widget.list.person);
  late int _color = widget.list.color;

  @override
  void dispose() {
    _name.dispose();
    _person.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _dialog(
      context,
      title: 'Edit list',
      action: 'Save',
      onAction: () {
        final name = _name.text.trim();
        if (name.isEmpty) return;
        Navigator.of(context).pop(
          widget.list.copyWith(
            name: name,
            color: _color,
            person: _person.text.trim(),
          ),
        );
      },
      children: [
        Text(
          widget.list.entityId,
          style: const TextStyle(color: Colors.white70),
        ),
        const Text(
          'To change the list itself, delete it and add it again.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        ..._fields(
          name: _name,
          person: _person,
          color: _color,
          onColor: (c) => setState(() => _color = c),
        ),
      ],
    );
  }
}
