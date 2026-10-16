import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import '../../config/person.dart';
import '../../models/ha_entity.dart';
import '../../modules/calendar/calendar_providers.dart';
import '../../modules/calendar/ics_calendar_source.dart';
import '../../modules/calendar/models.dart';
import '../../services/home_assistant_service.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/select_setting_field.dart';
import '../framework/list_section.dart';
import 'calendar_sources.dart';


/// Poll interval choices, minutes → label. Shared with the portal.
const calendarPollOptions = {
  '15': '15 minutes',
  '30': '30 minutes',
  '60': '1 hour',
  '360': '6 hours',
  '1440': '24 hours',
};

const calendarViewOptions = {
  'day': 'Day',
  '3day': '3 days',
  'week': 'Week',
  'month': 'Month',
};

/// The poll option nearest a stored interval, which `fromJson` only clamps.
String calendarPollOption(int minutes) {
  var best = calendarPollOptions.keys.first;
  for (final key in calendarPollOptions.keys) {
    if ((int.parse(key) - minutes).abs() <
        (int.parse(best) - minutes).abs()) {
      best = key;
    }
  }
  return best;
}

final calendarPollField = SelectSettingField(
  label: 'ICS refresh interval',
  configPath: 'calendarIcsPollMinutes',
  options: calendarPollOptions,
  readOverride: (c) => calendarPollOption(c.calendarIcsPollMinutes),
  writeOverride: (ref, value) => ref
      .read(hubConfigProvider.notifier)
      .update((c) => c.copyWith(calendarIcsPollMinutes: int.parse(value))),
);

const calendarGlanceField = BoolSettingField(
  label: 'Show upcoming events when idle',
  configPath: 'calendarAmbientGlance',
);

const calendarViewField = SelectSettingField(
  label: 'Default view',
  configPath: 'calendarDefaultView',
  options: calendarViewOptions,
);

/// The Calendar plugin's on-device panel.
class CalendarSettingsSection extends ConsumerWidget {
  const CalendarSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(hubConfigProvider.select((c) => c.calendarSources));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection<CalendarSource>(
          label: 'Calendars',
          items: sources,
          summaryFor: (s) => s.name,
          leadingFor: (s) => CalendarSwatch(color: s.color),
          subtitleFor: (s) => _SourceStatusLine(source: s),
          onListChanged: (list) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(calendarSources: list)),
          editorBuilder: (context, existing) async {
            if (existing != null) {
              return showDialog<CalendarSource>(
                context: context,
                builder: (_) => _EditSourceDialog(source: existing),
              );
            }
            final kind = await showDialog<CalendarSourceKind>(
              context: context,
              builder: (_) => const _KindDialog(),
            );
            if (kind == null || !context.mounted) return null;
            return showDialog<CalendarSource>(
              context: context,
              builder: (_) => kind == CalendarSourceKind.ha
                  ? const _AddHaDialog()
                  : const _AddIcsDialog(),
            );
          },
        ).buildWidget(context, ref),
        calendarPollField.buildWidget(ref),
        calendarGlanceField.buildWidget(ref),
        calendarViewField.buildWidget(ref),
      ],
    );
  }
}

class CalendarSwatch extends StatelessWidget {
  final int color;
  final double size;
  const CalendarSwatch({super.key, required this.color, this.size = 16});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: Color(color), // theme-exempt: data color
            shape: BoxShape.circle),
      );
}

class _SourceStatusLine extends ConsumerWidget {
  final CalendarSource source;
  const _SourceStatusLine({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    // Watching a disabled source would start it.
    final status = source.enabled
        ? ref.watch(calendarSourceEventsProvider(source.id)).valueOrNull
        : null;
    final use24 = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final label = calendarStatusLabel(status,
        enabled: source.enabled, use24Hour: use24);
    final owner = ref.watch(hubConfigProvider
        .select((c) => personById(c.people, source.personId)?.name));
    final bad = status?.status == SourceStatus.error ||
        status?.status == SourceStatus.stale;
    return Text(
      [calendarKindLabel(source.kind), ?owner, label].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: bad ? c.warning : c.textMuted, fontSize: 12),
    );
  }
}

class _KindDialog extends StatelessWidget {
  const _KindDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return SimpleDialog(
        backgroundColor: c.menu,
        title: Text('Add calendar', style: TextStyle(color: c.text)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, CalendarSourceKind.ha),
            child: ListTile(
              leading: Icon(Icons.home, color: c.textSecondary),
              title: Text('Home Assistant calendar',
                  style: TextStyle(color: c.text)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, CalendarSourceKind.ics),
            child: ListTile(
              leading: Icon(Icons.link, color: c.textSecondary),
              title: Text('ICS URL', style: TextStyle(color: c.text)),
            ),
          ),
        ],
      );
  }
}

/// The palette as tappable swatches, plus [selected] when it is not in it.
class CalendarColorPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const CalendarColorPicker(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = [
      ...calendarPalette,
      if (!calendarPalette.contains(selected)) selected,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in colors)
          GestureDetector(
            key: ValueKey('swatch-${calendarColorHex(c)}'),
            onTap: () => onChanged(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(c), // theme-exempt: data color
                shape: BoxShape.circle,
                border: Border.all(
                    color: c == selected
                        ? context.hearthColors.ink
                        : Colors.transparent,
                    width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _nameField(HearthColors c, TextEditingController controller) =>
    TextField(
      key: const ValueKey('calendar-name'),
      controller: controller,
      style: TextStyle(color: c.text),
      decoration: InputDecoration(
          labelText: 'Name', labelStyle: TextStyle(color: c.textMuted)),
    );

Widget _colorRow(
        HearthColors c, int selected, ValueChanged<int> onChanged) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Colour', style: TextStyle(color: c.textMuted)),
        const SizedBox(height: 6),
        CalendarColorPicker(selected: selected, onChanged: onChanged),
      ],
    );

/// The optional owner, from the People registry.
Widget _ownerRow(
        HearthColors c, List<Person> people, String personId, ValueChanged<String> onChanged) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Belongs to', style: TextStyle(color: c.textMuted)),
        DropdownButton<String>(
          key: const ValueKey('calendar-owner'),
          value: personById(people, personId) == null ? '' : personId,
          isExpanded: true,
          dropdownColor: c.menu,
          style: TextStyle(color: c.text),
          items: [
            const DropdownMenuItem(value: '', child: Text('No one')),
            for (final p in people)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );

/// [personId] when it is still someone in [people], else ''.
String _owner(List<Person> people, String personId) =>
    personById(people, personId) == null ? '' : personId;

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

class _AddHaDialog extends ConsumerStatefulWidget {
  const _AddHaDialog();

  @override
  ConsumerState<_AddHaDialog> createState() => _AddHaDialogState();
}

class _AddHaDialogState extends ConsumerState<_AddHaDialog> {
  final _name = TextEditingController();
  HaEntity? _entity;
  late int _color;
  bool _colorPicked = false;
  String _personId = '';

  @override
  void initState() {
    super.initState();
    _color = nextPaletteColor(ref.read(hubConfigProvider).calendarSources);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _select(HaEntity entity) async {
    setState(() {
      _entity = entity;
      _name.text = entity.name;
    });
    final defaults =
        await ref.read(calendarHaDefaultsProvider)(entity.entityId);
    if (!mounted || _entity != entity) return;
    setState(() {
      if (defaults.name != null) _name.text = defaults.name!;
      if (defaults.color != null && !_colorPicked) _color = defaults.color!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final added = {
      for (final s in ref.read(hubConfigProvider).calendarSources) s.entityId
    };
    final entities = ref
        .read(homeAssistantServiceProvider)
        .entities
        .values
        .where((e) => e.domain == 'calendar' && !added.contains(e.entityId))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final entity = _entity;
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    return _dialog(
      context,
      title: 'Add Home Assistant calendar',
      action: 'Add',
      onAction: entity == null
          ? null
          : () {
              final name = _name.text.trim();
              Navigator.of(context).pop(CalendarSource(
                id: haSourceId(entity.entityId),
                kind: CalendarSourceKind.ha,
                entityId: entity.entityId,
                name: name.isEmpty ? entity.name : name,
                color: _color,
                personId: _owner(people, _personId),
              ));
            },
      children: [
        if (entities.isEmpty)
          Text(
            'No calendars to add. Is Home Assistant connected, and does it '
            'have calendar entities?',
            style: TextStyle(color: c.textSecondary),
          )
        else
          DropdownButton<HaEntity>(
            key: const ValueKey('calendar-entity'),
            value: entity,
            isExpanded: true,
            hint: Text('Calendar entity', style: TextStyle(color: c.textMuted)),
            dropdownColor: c.menu,
            style: TextStyle(color: c.text),
            items: [
              for (final e in entities)
                DropdownMenuItem(
                    value: e, child: Text('${e.name} (${e.entityId})')),
            ],
            onChanged: (e) {
              if (e != null) _select(e);
            },
          ),
        _nameField(c, _name),
        _ownerRow(c, people, _personId, (id) => setState(() => _personId = id)),
        _colorRow(c, _color, (c) => setState(() {
              _color = c;
              _colorPicked = true;
            })),
      ],
    );
  }
}

class _AddIcsDialog extends ConsumerStatefulWidget {
  const _AddIcsDialog();

  @override
  ConsumerState<_AddIcsDialog> createState() => _AddIcsDialogState();
}

class _AddIcsDialogState extends ConsumerState<_AddIcsDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  late int _color;
  bool _colorPicked = false;

  /// The URL the last test fetched; saving needs a test of the current one.
  String? _tested;
  bool _testing = false;
  String? _result;
  bool _failed = false;
  String _personId = '';

  @override
  void initState() {
    super.initState();
    _color = nextPaletteColor(ref.read(hubConfigProvider).calendarSources);
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _url.text.trim();
    final invalid = validateIcsUrl(url);
    if (invalid != null) {
      setState(() {
        _result = invalid;
        _failed = true;
        _tested = null;
      });
      return;
    }
    setState(() => _testing = true);
    try {
      final probe = await ref.read(calendarIcsProbeProvider)(url);
      if (!mounted) return;
      setState(() {
        final name = probe.name;
        _result = '${name == null ? 'Calendar' : '“$name”'} · '
            '${probe.eventCount} event${probe.eventCount == 1 ? '' : 's'}';
        _failed = false;
        if (_name.text.trim().isEmpty && name != null) _name.text = name;
        final color = parseCalendarColor(probe.color);
        if (color != null && !_colorPicked) _color = color;
      });
    } on IcsProbeException catch (e) {
      if (!mounted) return;
      setState(() {
        _result = e.message;
        _failed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
          if (validateIcsUrl(url) == null) _tested = url;
        });
      }
    }
  }

  void _save() {
    final url = _url.text.trim();
    final name = _name.text.trim();
    Navigator.of(context).pop(CalendarSource(
      id: newIcsSourceId(),
      kind: CalendarSourceKind.ics,
      url: url,
      name: name.isEmpty ? icsFallbackName(url) : name,
      color: _color,
      personId: _owner(ref.read(hubConfigProvider).people, _personId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final tested = _tested != null && _tested == _url.text.trim();
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    return _dialog(
      context,
      title: 'Add ICS URL',
      action: tested ? 'Add' : 'Test',
      onAction: _testing || _url.text.trim().isEmpty
          ? null
          : (tested ? _save : _test),
      children: [
        TextField(
          key: const ValueKey('calendar-url'),
          controller: _url,
          style: TextStyle(color: c.text),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'URL',
            hintText: 'https:// or webcal://…',
            labelStyle: TextStyle(color: c.textMuted),
            hintStyle: TextStyle(color: c.inkAt(0.24)),
          ),
        ),
        if (_testing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Fetching…', style: TextStyle(color: c.textMuted)),
          )
        else if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _result!,
              key: const ValueKey('calendar-test-result'),
              style: TextStyle(
                  color: _failed ? c.warning : c.textSecondary),
            ),
          ),
        _nameField(c, _name),
        _ownerRow(c, people, _personId, (id) => setState(() => _personId = id)),
        _colorRow(c, _color, (c) => setState(() {
              _color = c;
              _colorPicked = true;
            })),
      ],
    );
  }
}

class _EditSourceDialog extends ConsumerStatefulWidget {
  final CalendarSource source;
  const _EditSourceDialog({required this.source});

  @override
  ConsumerState<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends ConsumerState<_EditSourceDialog> {
  late final _name = TextEditingController(text: widget.source.name);
  late int _color = widget.source.color;
  late bool _enabled = widget.source.enabled;
  late String _personId = widget.source.personId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final source = widget.source;
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    return _dialog(
      context,
      title: 'Edit calendar',
      action: 'Save',
      onAction: () {
        final name = _name.text.trim();
        if (name.isEmpty) return;
        Navigator.of(context).pop(source.copyWith(
            name: name,
            color: _color,
            enabled: _enabled,
            personId: _owner(people, _personId)));
      },
      children: [
        Text(
          source.kind == CalendarSourceKind.ha
              ? 'Home Assistant · ${source.entityId}'
              : 'ICS feed',
          style: TextStyle(color: c.textSecondary),
        ),
        Text(
          'To change the calendar itself, delete it and add it again.',
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        _nameField(c, _name),
        _ownerRow(c, people, _personId, (id) => setState(() => _personId = id)),
        _colorRow(c, _color, (c) => setState(() => _color = c)),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('calendar-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text('Enabled', style: TextStyle(color: c.text)),
          value: _enabled,
          activeThumbColor: c.accent,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ],
    );
  }
}
