import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/immich_album.dart';
import '../../models/immich_person.dart';
import '../../services/immich_service.dart';
import '../../app/tokens/tokens.dart';

/// Debounce delay before a smart-search query keystroke is persisted.
/// Persisting commits to [PhotoSourcesConfig], which re-creates
/// [immichServiceProvider] and fires `POST /api/search/smart` — so we wait
/// until the user stops typing rather than spamming CLIP on every keystroke.
const _smartSearchDebounce = Duration(milliseconds: 600);

/// Settings section for choosing which Immich sources feed the ambient
/// carousel. Four independently-toggleable sources: Memories, Album,
/// People, Smart search. Album and People expose pickers populated from
/// Immich; Smart search takes a free-text CLIP query.
class PhotoSourcesSection extends ConsumerStatefulWidget {
  const PhotoSourcesSection({super.key});

  @override
  ConsumerState<PhotoSourcesSection> createState() =>
      _PhotoSourcesSectionState();
}

class _PhotoSourcesSectionState extends ConsumerState<PhotoSourcesSection> {
  Future<List<ImmichAlbum>>? _albumsFuture;
  Future<List<ImmichPerson>>? _peopleFuture;
  late final TextEditingController _smartSearchController;
  Timer? _smartSearchTimer;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(immichServiceProvider);
    _albumsFuture = svc.listAlbums();
    _peopleFuture = svc.listNamedPeople();
    _smartSearchController = TextEditingController(
      text: ref.read(hubConfigProvider).photoSources.smartSearchQuery,
    );
  }

  @override
  void dispose() {
    _smartSearchTimer?.cancel();
    _smartSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider).photoSources;
    final notifier = ref.read(hubConfigProvider.notifier);

    void update(PhotoSourcesConfig next) {
      notifier.update((c) => c.copyWith(photoSources: next));
    }

    // Weights only matter once two sources compete for the feed.
    final showWeights = config.activeSourceCount >= 2;

    Widget weight(String label, int value, PhotoSourcesConfig Function(int) set) {
      if (!showWeights) return const SizedBox.shrink();
      return _WeightSlider(
        label: label,
        value: value,
        onChanged: (v) => update(set(v)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: HearthSpacing.x2),
          child: Text('Photo sources',
              style: TextStyle(fontSize: HearthFont.title, fontWeight: FontWeight.w500)),
        ),
        SwitchListTile(
          title: const Text('Memories ("On This Day")'),
          value: config.memoriesEnabled,
          onChanged: (v) => update(config.copyWith(memoriesEnabled: v)),
        ),
        if (config.memoriesEnabled)
          weight('Memories', config.memoriesWeight,
              (v) => config.copyWith(memoriesWeight: v)),
        SwitchListTile(
          title: const Text('Album'),
          subtitle: config.albumEnabled && config.albumId.isEmpty
              ? const Text('Pick an album below',
                  style: TextStyle(color: Colors.amber))
              : null,
          value: config.albumEnabled,
          onChanged: (v) => update(config.copyWith(albumEnabled: v)),
        ),
        if (config.albumEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x4),
            child: _AlbumDropdown(
              future: _albumsFuture!,
              selectedId: config.albumId,
              onChanged: (id) => update(config.copyWith(albumId: id)),
            ),
          ),
        if (config.albumEnabled && config.albumId.isNotEmpty)
          weight('Album', config.albumWeight,
              (v) => config.copyWith(albumWeight: v)),
        SwitchListTile(
          title: const Text('People'),
          subtitle: config.peopleEnabled && config.personIds.isEmpty
              ? const Text('Pick at least one person below',
                  style: TextStyle(color: Colors.amber))
              : null,
          value: config.peopleEnabled,
          onChanged: (v) => update(config.copyWith(peopleEnabled: v)),
        ),
        if (config.peopleEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x4, vertical: HearthSpacing.x2),
            child: _PeopleChips(
              future: _peopleFuture!,
              selectedIds: config.personIds,
              onChanged: (ids) => update(config.copyWith(personIds: ids)),
            ),
          ),
        if (config.peopleEnabled && config.personIds.isNotEmpty)
          weight('People', config.peopleWeight,
              (v) => config.copyWith(peopleWeight: v)),
        SwitchListTile(
          title: const Text('Smart search'),
          subtitle: config.smartSearchEnabled && config.smartSearchQuery.isEmpty
              ? const Text('Enter a query below',
                  style: TextStyle(color: Colors.amber))
              : null,
          value: config.smartSearchEnabled,
          onChanged: (v) => update(config.copyWith(smartSearchEnabled: v)),
        ),
        if (config.smartSearchEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.x4, vertical: HearthSpacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _smartSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search query',
                    hintText: 'e.g. beach, sunset, autumn leaves',
                  ),
                  onChanged: (value) => _onSmartSearchChanged(value, update),
                ),
                const SizedBox(height: HearthSpacing.x2),
                const Text(
                  "Works best for visual concepts like 'beach' or 'sunset' — "
                  'searches understand the image content, not filenames.',
                  style: TextStyle(fontSize: HearthFont.caption),
                ),
              ],
            ),
          ),
        if (config.smartSearchEnabled && config.smartSearchQuery.isNotEmpty)
          weight('Smart search', config.smartSearchWeight,
              (v) => config.copyWith(smartSearchWeight: v)),
        if (showWeights)
          const Padding(
            padding: EdgeInsets.symmetric(
                horizontal: HearthSpacing.x4, vertical: HearthSpacing.x2),
            child: Text(
              'Weights set how much of the rotation each source gets, '
              'relative to the others. A source with fewer photos than its '
              'share repeats to fill it.',
              style: TextStyle(fontSize: HearthFont.caption),
            ),
          ),
      ],
    );
  }

  /// Debounce the query: persist ~600ms after the user stops typing rather
  /// than per keystroke, since each commit re-creates the Immich service and
  /// fires a fresh CLIP search.
  void _onSmartSearchChanged(
    String value,
    void Function(PhotoSourcesConfig) update,
  ) {
    _smartSearchTimer?.cancel();
    _smartSearchTimer = Timer(_smartSearchDebounce, () {
      final current = ref.read(hubConfigProvider).photoSources;
      update(current.copyWith(smartSearchQuery: value));
    });
  }
}

class _AlbumDropdown extends StatelessWidget {
  final Future<List<ImmichAlbum>> future;
  final String selectedId;
  final ValueChanged<String> onChanged;

  const _AlbumDropdown({
    required this.future,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImmichAlbum>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: HearthSpacing.x2),
            child: Text('Loading albums…'),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: HearthSpacing.x2),
            child: Text(
              "Couldn't load albums — check the Immich URL above.",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final albums = snap.data ?? const [];
        // Make sure the currently-selected ID is in the list even if it
        // was deleted, so the dropdown doesn't throw.
        final items = [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('— pick one —'),
          ),
          ...albums.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} (${a.assetCount})'),
              )),
        ];
        final hasSelected =
            albums.any((a) => a.id == selectedId) || selectedId.isEmpty;
        return DropdownButton<String>(
          value: hasSelected ? selectedId : '',
          isExpanded: true,
          items: items,
          onChanged: (v) => onChanged(v ?? ''),
        );
      },
    );
  }
}

class _PeopleChips extends StatelessWidget {
  final Future<List<ImmichPerson>> future;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _PeopleChips({
    required this.future,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImmichPerson>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('Loading people…');
        }
        if (snap.hasError) {
          return Text(
            "Couldn't load people — check the Immich URL above.",
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final people = snap.data ?? const [];
        if (people.isEmpty) {
          return const Text(
            'No named people found in Immich. '
            'Tag faces in Immich first.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap to toggle. Showing ${people.length} named.',
                style: const TextStyle(fontSize: HearthFont.caption)),
            const SizedBox(height: HearthSpacing.x2),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: people.map((p) {
                final isSelected = selectedIds.contains(p.id);
                return FilterChip(
                  label: Text('${p.name} (${p.numberOfAssets})'),
                  selected: isSelected,
                  onSelected: (selected) {
                    final next = List<String>.from(selectedIds);
                    if (selected) {
                      if (!next.contains(p.id)) next.add(p.id);
                    } else {
                      next.remove(p.id);
                    }
                    onChanged(next);
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

/// Per-source share control. 1-5, where the number is meaningful only
/// relative to the other enabled sources' weights.
class _WeightSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _WeightSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.x4, vertical: HearthSpacing.x1),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text('$label share',
                style: const TextStyle(fontSize: HearthFont.caption)),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$value',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text('$value',
                style: const TextStyle(fontSize: HearthFont.caption)),
          ),
        ],
      ),
    );
  }
}
