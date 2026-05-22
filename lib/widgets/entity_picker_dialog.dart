import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app.dart' show kDialogBackground;
import '../app/tokens/tokens.dart';
import '../config/hub_config.dart';
import '../models/ha_entity.dart';
import '../services/home_assistant_service.dart';

/// Multi-select picker for HA entities used by the Controls screen.
///
/// Reads the current pinned-entity set from [hubConfigProvider] and the
/// available entities from [homeAssistantServiceProvider]. On Save, writes
/// the new selection back to `pinnedEntityIds` via the config notifier.
///
/// Show with `showDialog&lt;List&lt;String&gt;&gt;(context: ..., builder: (_) =>
/// const EntityPickerDialog())`. Returns the saved list (or null on cancel).
class EntityPickerDialog extends ConsumerStatefulWidget {
  const EntityPickerDialog({super.key});

  @override
  ConsumerState<EntityPickerDialog> createState() =>
      _EntityPickerDialogState();
}

class _EntityPickerDialogState extends ConsumerState<EntityPickerDialog> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final config = ref.read(hubConfigProvider);
    _selected = Set<String>.from(config.pinnedEntityIds);
  }

  @override
  Widget build(BuildContext context) {
    final ha = ref.read(homeAssistantServiceProvider);
    final allEntities = ha.entities.values
        .where((e) => const [
              'light',
              'switch',
              'climate',
              'fan',
              'cover',
              'lock',
              'input_boolean',
            ].contains(e.domain))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (allEntities.isEmpty) {
      return AlertDialog(
        backgroundColor: kDialogBackground,
        title: const Text('Select Devices'),
        content: const Text(
          'No entities available. Is Home Assistant connected?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final filtered = allEntities
        .where((e) =>
            e.name.toLowerCase().contains(_search.toLowerCase()) ||
            e.entityId.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: const Text('Select Devices'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search entities...',
                prefixIcon: Icon(Icons.search, color: Colors.white38),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: HearthSpacing.x2),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final HaEntity entity = filtered[i];
                  final isSelected = _selected.contains(entity.entityId);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(
                      entity.name,
                      style: const TextStyle(fontSize: HearthFont.body),
                    ),
                    subtitle: Text(
                      entity.entityId,
                      style: TextStyle(
                        fontSize: HearthFont.caption,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(entity.entityId);
                        } else {
                          _selected.remove(entity.entityId);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final newList = _selected.toList();
            await ref.read(hubConfigProvider.notifier).update(
                  (c) => c.copyWith(pinnedEntityIds: newList),
                );
            if (!context.mounted) return;
            Navigator.pop(context, newList);
          },
          child: Text('Save (${_selected.length})'),
        ),
      ],
    );
  }
}
