import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/immich_album.dart';
import '../../models/immich_person.dart';
import '../../services/immich_service.dart';

/// Settings section for choosing which Immich sources feed the ambient
/// carousel. Three independently-toggleable sources: Memories, Album,
/// People. Album and People expose pickers populated from Immich.
class PhotoSourcesSection extends ConsumerStatefulWidget {
  const PhotoSourcesSection({super.key});

  @override
  ConsumerState<PhotoSourcesSection> createState() =>
      _PhotoSourcesSectionState();
}

class _PhotoSourcesSectionState extends ConsumerState<PhotoSourcesSection> {
  Future<List<ImmichAlbum>>? _albumsFuture;
  Future<List<ImmichPerson>>? _peopleFuture;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(immichServiceProvider);
    _albumsFuture = svc.listAlbums();
    _peopleFuture = svc.listNamedPeople();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider).photoSources;
    final notifier = ref.read(hubConfigProvider.notifier);

    void update(PhotoSourcesConfig next) {
      notifier.update((c) => c.copyWith(photoSources: next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Photo sources',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ),
        SwitchListTile(
          title: const Text('Memories ("On This Day")'),
          value: config.memoriesEnabled,
          onChanged: (v) => update(config.copyWith(memoriesEnabled: v)),
        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AlbumDropdown(
              future: _albumsFuture!,
              selectedId: config.albumId,
              onChanged: (id) => update(config.copyWith(albumId: id)),
            ),
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _PeopleChips(
              future: _peopleFuture!,
              selectedIds: config.personIds,
              onChanged: (ids) => update(config.copyWith(personIds: ids)),
            ),
          ),
      ],
    );
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
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading albums…'),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
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
