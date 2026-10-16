import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import '../../config/person.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import '../../services/people.dart';
import '../../widgets/person_avatar.dart';
import '../calendar/calendar_settings_section.dart' show CalendarColorPicker;
import '../calendar/calendar_sources.dart';
import '../framework/list_section.dart';
import 'people_plugin.dart' show personStatusLabel;


/// The People plugin's on-device panel.
class PeopleSettingsSection extends ConsumerWidget {
  const PeopleSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection<Person>(
          label: 'People',
          items: people,
          summaryFor: (p) => p.name,
          leadingFor: (p) => _Avatar(personId: p.id),
          subtitleFor: (p) => _PersonStatusLine(personId: p.id),
          onListChanged: (list) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.withPeople(list)),
          editorBuilder: (context, existing) => showDialog<Person>(
            context: context,
            builder: (_) => _PersonDialog(person: existing),
          ),
        ).buildWidget(context, ref),
        const _ImportButton(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Calendars and chore lists are assigned to people on the '
            'Calendar and Lists panels.',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends ConsumerWidget {
  final String personId;
  const _Avatar({required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(personViewProvider(personId));
    return view == null
        ? const SizedBox(width: 32, height: 32)
        : PersonAvatar(view: view, size: 32);
  }
}

class _PersonStatusLine extends ConsumerWidget {
  final String personId;
  const _PersonStatusLine({required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final view = ref.watch(personViewProvider(personId));
    if (view == null) return const SizedBox.shrink();
    final config = ref.watch(hubConfigProvider);
    return Text(
      personStatusLabel(view.person, view, config,
          ref.watch(homeAssistantServiceProvider)),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: c.textMuted, fontSize: 12),
    );
  }
}

class _ImportButton extends ConsumerStatefulWidget {
  const _ImportButton();

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  String? _result;

  /// Held while an import saves: until the write lands the config still
  /// lacks the new people, so a second tap would add them again.
  bool _busy = false;

  Future<void> _import() async {
    final ha = ref.read(homeAssistantServiceProvider);
    if (!ha.isConnected) {
      setState(() => _result = "Can't reach Home Assistant");
      return;
    }
    setState(() => _busy = true);
    final added = importablePeople(
        ref.read(hubConfigProvider).people, ha, nextFreePaletteColor);
    try {
      if (added.isNotEmpty) {
        await ref
            .read(hubConfigProvider.notifier)
            .update((c) => c.withPeople([...c.people, ...added]));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() => _result = added.isEmpty
        ? 'Everyone in Home Assistant is already here.'
        : 'Added ${added.length} ${added.length == 1 ? 'person' : 'people'}.');
  }

  @override
  // A Wrap, so the result drops under the button on a narrow panel.
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          TextButton.icon(
            key: const ValueKey('people-import'),
            icon: Icon(Icons.download, color: c.accentText, size: 16),
            label: Text('Import from Home Assistant',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.accentText)),
            onPressed: _busy ? null : _import,
          ),
          if (_result != null)
            Text(
              _result!,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
        ],
      );
  }
}

/// Add (when [person] is null) or edit one person.
class _PersonDialog extends ConsumerStatefulWidget {
  final Person? person;
  const _PersonDialog({required this.person});

  @override
  ConsumerState<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends ConsumerState<_PersonDialog> {
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  late String _entityId = widget.person?.haPersonEntityId ?? '';
  late int _color = widget.person?.color ??
      nextFreePaletteColor(
          [for (final p in ref.read(hubConfigProvider).people) p.color]);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _link(String entityId, List<HaEntity> entities) {
    final previous =
        entities.where((e) => e.entityId == _entityId).firstOrNull?.name;
    setState(() => _entityId = entityId);
    // Linking pre-fills a blank name, or one that was the last link's.
    final picked = entities.where((e) => e.entityId == entityId).firstOrNull;
    final name = _name.text.trim();
    if (picked != null && (name.isEmpty || name == previous)) {
      _name.text = picked.name;
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final editing = widget.person;
    Navigator.of(context).pop(editing == null
        ? Person(
            id: newPersonId(),
            name: name,
            color: _color,
            haPersonEntityId: _entityId,
          )
        : editing.copyWith(
            name: name, color: _color, haPersonEntityId: _entityId));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final editing = widget.person;
    final linkedElsewhere = {
      for (final p in ref.read(hubConfigProvider).people)
        if (p.id != editing?.id && p.isLinked) p.haPersonEntityId,
    };
    final entities = haPersonEntities(ref.read(homeAssistantServiceProvider))
        .where((e) => !linkedElsewhere.contains(e.entityId))
        .toList();
    final known = entities.any((e) => e.entityId == _entityId);
    final name = _name.text.trim();
    return AlertDialog(
      backgroundColor: c.menu,
      title: Text(editing == null ? 'Add person' : 'Edit person',
          style: TextStyle(color: c.text)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('person-name'),
                controller: _name,
                style: TextStyle(color: c.text),
                decoration: InputDecoration(
                    labelText: 'Name', labelStyle: TextStyle(color: c.textMuted)),
              ),
              const SizedBox(height: 16),
              Text('Home Assistant person', style: TextStyle(color: c.textMuted)),
              DropdownButton<String>(
                key: const ValueKey('person-entity'),
                value: _entityId,
                isExpanded: true,
                dropdownColor: c.menu,
                style: TextStyle(color: c.text),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Not linked')),
                  for (final e in entities)
                    DropdownMenuItem(
                        value: e.entityId,
                        child: Text('${e.name} (${e.entityId})')),
                  // Keep a link HA has not reported (yet) selectable.
                  if (_entityId.isNotEmpty && !known)
                    DropdownMenuItem(
                        value: _entityId, child: Text(_entityId)),
                ],
                onChanged: (v) {
                  if (v != null) _link(v, entities);
                },
              ),
              if (entities.isEmpty)
                Text(
                  'No people in Home Assistant to link. Is it connected?',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              const SizedBox(height: 16),
              Text('Colour', style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 6),
              CalendarColorPicker(
                  selected: _color,
                  onChanged: (c) => setState(() => _color = c)),
            ],
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
          onPressed: name.isEmpty ? null : _save,
          child: Text(editing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
