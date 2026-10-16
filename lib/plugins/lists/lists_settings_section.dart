import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import '../../config/person.dart';
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
    final c = context.hearthColors;
    ref.watch(haEntitiesProvider);
    final config = ref.watch(hubConfigProvider);
    final kind = todoListKindLabel(list, config.people);
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
          '$kind · ${status.label}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: status.bad ? Colors.orangeAccent : c.textMuted,
            fontSize: 12,
          ),
        ),
        if (features.isNotEmpty)
          Text(
            features,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
      ],
    );
  }
}

/// Name, person and colour: the fields add and edit share.
List<Widget> _fields({
  required HearthColors c,
  required TextEditingController name,
  required List<Person> people,
  required String personId,
  required ValueChanged<String> onPerson,
  required int color,
  required ValueChanged<int> onColor,
}) => [
  TextField(
    key: const ValueKey('list-name'),
    controller: name,
    style: TextStyle(color: c.text),
    decoration: InputDecoration(
      labelText: 'Name',
      labelStyle: TextStyle(color: c.textMuted),
    ),
  ),
  const SizedBox(height: 16),
  Text('Person', style: TextStyle(color: c.textMuted)),
  DropdownButton<String>(
    key: const ValueKey('list-person'),
    value: personById(people, personId) == null ? '' : personId,
    isExpanded: true,
    dropdownColor: c.menu,
    style: TextStyle(color: c.text),
    items: [
      const DropdownMenuItem(value: '', child: Text('No one (a plain list)')),
      for (final p in people)
        DropdownMenuItem(value: p.id, child: Text("${p.name}'s chores")),
    ],
    onChanged: (v) {
      if (v != null) onPerson(v);
    },
  ),
  if (people.isEmpty)
    Text(
      'Add people on the People panel to make chore lists.',
      style: TextStyle(color: c.textFaint, fontSize: 12),
    ),
  const SizedBox(height: 16),
  Text('Colour', style: TextStyle(color: c.textMuted)),
  const SizedBox(height: 6),
  CalendarColorPicker(selected: color, onChanged: onColor),
];

AlertDialog _dialog(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  required String action,
  required VoidCallback? onAction,
}) {
  final c = context.hearthColors;
  return AlertDialog(
  backgroundColor: c.menu,
  title: Text(title, style: TextStyle(color: c.text)),
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
      child: Text('Cancel', style: TextStyle(color: c.textMuted)),
    ),
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: c.accentFill),
      onPressed: onAction,
      child: Text(action),
    ),
  ],
);
}

class _AddListDialog extends ConsumerStatefulWidget {
  const _AddListDialog();

  @override
  ConsumerState<_AddListDialog> createState() => _AddListDialogState();
}

class _AddListDialogState extends ConsumerState<_AddListDialog> {
  final _name = TextEditingController();
  String _personId = '';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
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
                  personId: _personId,
                ),
              );
            },
      children: [
        if (entities.isEmpty)
          Text(
            'No lists to add. Is Home Assistant connected, and does it have '
            'to-do entities?',
            style: TextStyle(color: c.textSecondary),
          )
        else
          DropdownButton<HaEntity>(
            key: const ValueKey('list-entity'),
            value: entity,
            isExpanded: true,
            hint: Text('To-do entity', style: TextStyle(color: c.textMuted)),
            dropdownColor: c.menu,
            style: TextStyle(color: c.text),
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
          c: c,
          name: _name,
          people: people,
          personId: _personId,
          onPerson: (id) => setState(() => _personId = id),
          color: _color,
          onColor: (c) => setState(() => _color = c),
        ),
      ],
    );
  }
}

class _EditListDialog extends ConsumerStatefulWidget {
  final TodoListConfig list;
  const _EditListDialog({required this.list});

  @override
  ConsumerState<_EditListDialog> createState() => _EditListDialogState();
}

class _EditListDialogState extends ConsumerState<_EditListDialog> {
  late final _name = TextEditingController(text: widget.list.name);
  late String _personId = widget.list.personId;
  late int _color = widget.list.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
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
            personId: personById(people, _personId) == null ? '' : _personId,
          ),
        );
      },
      children: [
        Text(
          widget.list.entityId,
          style: TextStyle(color: c.textSecondary),
        ),
        Text(
          'To change the list itself, delete it and add it again.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        ..._fields(
          c: c,
          name: _name,
          people: people,
          personId: _personId,
          onPerson: (id) => setState(() => _personId = id),
          color: _color,
          onColor: (c) => setState(() => _color = c),
        ),
      ],
    );
  }
}
