import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart' show kDialogBackground;
import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/glass_panel.dart';
import 'browse_tile.dart';

/// Full-screen browse overlay — search + library shelves. Replaces
/// the regular cinematic stage when `_browseOpen` is true. The
/// MiniBar persists at the bottom (not handled here; see
/// CinematicScreen for layout).
class BrowseOverlay extends ConsumerStatefulWidget {
  final String? playerId;
  final VoidCallback onClose;

  const BrowseOverlay({
    super.key,
    required this.playerId,
    required this.onClose,
  });

  @override
  ConsumerState<BrowseOverlay> createState() => _BrowseOverlayState();
}

enum _Section { albums, artists, playlists, tracks }

class _BrowseOverlayState extends ConsumerState<BrowseOverlay> {
  _Section _section = _Section.albums;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<MaMediaItem>>? _libraryFuture;
  Future<MaSearchResults>? _searchFuture;
  _Section? _libraryFor;

  @override
  void initState() {
    super.initState();
    _libraryFuture = _loadLibrary();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<MaMediaItem>> _loadLibrary() {
    _libraryFor = _section;
    final music = ref.read(musicAssistantServiceProvider);
    return music.getLibraryItems(_typeForApi(_section), limit: 80);
  }

  String _typeForApi(_Section s) {
    return switch (s) {
      _Section.albums => 'albums',
      _Section.artists => 'artists',
      _Section.playlists => 'playlists',
      _Section.tracks => 'tracks',
    };
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _searchFuture = null;
      });
      return;
    }
    setState(() => _query = q);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final music = ref.read(musicAssistantServiceProvider);
      setState(() => _searchFuture = music.searchLibrary(q));
    });
  }

  void _selectSection(_Section s) {
    if (_section == s) return;
    setState(() {
      _section = s;
      _libraryFuture = _loadLibrary();
    });
  }

  void _onTileTap(MaMediaItem item) {
    final id = widget.playerId;
    if (id == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kDialogBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: HearthSpacing.allX4,
              child: Text(
                item.name,
                style: const TextStyle(
                  fontSize: HearthFont.bodyLg,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _ActionTile(
              icon: Icons.play_arrow,
              label: 'Play Now',
              onTap: () => _commitAction(item, 'play'),
            ),
            _ActionTile(
              icon: Icons.skip_next,
              label: 'Play Next',
              onTap: () => _commitAction(item, 'next'),
            ),
            _ActionTile(
              icon: Icons.add_to_queue,
              label: 'Add to Queue',
              onTap: () => _commitAction(item, 'add'),
            ),
            _ActionTile(
              icon: Icons.playlist_remove,
              label: 'Clear Queue & Play',
              onTap: () => _commitAction(item, 'replace'),
            ),
            const SizedBox(height: HearthSpacing.x2),
          ],
        ),
      ),
    );
  }

  void _commitAction(MaMediaItem item, String option) {
    final id = widget.playerId;
    if (id == null) return;
    Navigator.of(context).pop();
    final music = ref.read(musicAssistantServiceProvider);
    music.playMedia(id, item, option: option);
    final label = switch (option) {
      'play' => 'Playing ${item.name}',
      'next' => 'Playing next: ${item.name}',
      'add' => 'Added to queue',
      'replace' => 'Playing ${item.name}',
      _ => 'Queued',
    };
    final icon = switch (option) {
      'next' => Icons.skip_next,
      'add' => Icons.add_to_queue,
      _ => Icons.play_arrow,
    };
    ref.read(toastProvider.notifier).show(label, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: MediaShadows.popover,
        borderRadius: BorderRadius.circular(MediaRadii.shelf),
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(MediaRadii.shelf),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HearthSpacing.x6, HearthSpacing.x5, HearthSpacing.x6, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                onBack: widget.onClose,
              ),
              const SizedBox(height: HearthSpacing.x4),
              _SectionTabs(
                active: _section,
                onSelect: _query.isEmpty ? _selectSection : null,
                searching: _query.isNotEmpty,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _query.isEmpty
                    ? _LibraryGrid(
                        section: _section,
                        future: _libraryFuture,
                        builtFor: _libraryFor,
                        onTileTap: _onTileTap,
                      )
                    : _SearchResults(
                        future: _searchFuture,
                        onTileTap: _onTileTap,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;

  const _Header({
    required this.controller,
    required this.onChanged,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.08),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.12),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(MediaRadii.pill),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: HearthIcon.xs,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    cursorColor: Colors.white,
                    style: const TextStyle(
                      fontSize: HearthFont.label,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search albums, artists, tracks…',
                      hintStyle: TextStyle(
                        fontSize: HearthFont.label,
                        color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                      ),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Material(
          color: const Color.fromRGBO(255, 255, 255, 0.08),
          borderRadius: BorderRadius.circular(MediaRadii.pill),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(MediaRadii.pill),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: HearthIcon.xs, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Back',
                    style: TextStyle(
                      fontSize: HearthFont.caption,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTabs extends StatelessWidget {
  final _Section active;
  final ValueChanged<_Section>? onSelect;
  final bool searching;

  const _SectionTabs({
    required this.active,
    required this.onSelect,
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in _Section.values) ...[
          _Tab(
            label: switch (s) {
              _Section.albums => 'Albums',
              _Section.artists => 'Artists',
              _Section.playlists => 'Playlists',
              _Section.tracks => 'Tracks',
            },
            icon: switch (s) {
              _Section.albums => Icons.album,
              _Section.artists => Icons.person,
              _Section.playlists => Icons.queue_music,
              _Section.tracks => Icons.music_note,
            },
            active: !searching && active == s,
            disabled: searching,
            onTap: onSelect == null ? null : () => onSelect!(s),
          ),
          const SizedBox(width: HearthSpacing.x2),
        ],
        const Spacer(),
        if (searching)
          const Text(
            'Search results',
            style: TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
            ),
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool disabled;
  final VoidCallback? onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = disabled
        ? const Color.fromRGBO(255, 255, 255, 0.30)
        : (active ? Colors.white : const Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow));
    return Material(
      color: active
          ? const Color.fromRGBO(255, 255, 255, 0.16)
          : const Color.fromRGBO(255, 255, 255, 0.04),
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? const Color.fromRGBO(255, 255, 255, 0.20)
                  : const Color.fromRGBO(255, 255, 255, 0.06),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(MediaRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: HearthIcon.xs, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: HearthFont.caption,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  final _Section section;
  final Future<List<MaMediaItem>>? future;
  final _Section? builtFor;
  final ValueChanged<MaMediaItem> onTileTap;

  const _LibraryGrid({
    required this.section,
    required this.future,
    required this.builtFor,
    required this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MaMediaItem>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            builtFor != section) {
          return const Center(
            child: SizedBox(
              width: HearthSpacing.x6,
              height: HearthSpacing.x6,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        final items = snap.data ?? const <MaMediaItem>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No ${_typeLabel(section)} in library',
              style: const TextStyle(
                fontSize: HearthFont.label,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
              ),
            ),
          );
        }
        return _Grid(
          items: items,
          isCircle: section == _Section.artists,
          onTileTap: onTileTap,
        );
      },
    );
  }

  static String _typeLabel(_Section s) => switch (s) {
        _Section.albums => 'albums',
        _Section.artists => 'artists',
        _Section.playlists => 'playlists',
        _Section.tracks => 'tracks',
      };
}

class _SearchResults extends StatelessWidget {
  final Future<MaSearchResults>? future;
  final ValueChanged<MaMediaItem> onTileTap;

  const _SearchResults({required this.future, required this.onTileTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaSearchResults>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: HearthSpacing.x6,
              height: HearthSpacing.x6,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        final r = snap.data;
        if (r == null || r.isEmpty) {
          return const Center(
            child: Text(
              'No results',
              style: TextStyle(
                fontSize: HearthFont.label,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.tracks.isNotEmpty)
                _SearchSection(
                  label: 'Tracks',
                  items: r.tracks,
                  isCircle: false,
                  onTileTap: onTileTap,
                ),
              if (r.albums.isNotEmpty)
                _SearchSection(
                  label: 'Albums',
                  items: r.albums,
                  isCircle: false,
                  onTileTap: onTileTap,
                ),
              if (r.artists.isNotEmpty)
                _SearchSection(
                  label: 'Artists',
                  items: r.artists,
                  isCircle: true,
                  onTileTap: onTileTap,
                ),
              if (r.playlists.isNotEmpty)
                _SearchSection(
                  label: 'Playlists',
                  items: r.playlists,
                  isCircle: false,
                  onTileTap: onTileTap,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchSection extends StatelessWidget {
  final String label;
  final List<MaMediaItem> items;
  final bool isCircle;
  final ValueChanged<MaMediaItem> onTileTap;

  const _SearchSection({
    required this.label,
    required this.items,
    required this.isCircle,
    required this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${label.toUpperCase()} · ${items.length}',
              style: const TextStyle(
                fontSize: HearthFont.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
              ),
            ),
          ),
          _Grid(items: items, isCircle: isCircle, onTileTap: onTileTap),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<MaMediaItem> items;
  final bool isCircle;
  final ValueChanged<MaMediaItem> onTileTap;

  const _Grid({
    required this.items,
    required this.isCircle,
    required this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    final cols = isCircle ? 7 : 5;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: HearthSpacing.x4,
        mainAxisSpacing: 18,
        childAspectRatio: isCircle ? 0.75 : 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => BrowseTile(
        item: items[i],
        isCircle: isCircle,
        onTap: () => onTileTap(items[i]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: HearthFont.body),
      ),
      onTap: onTap,
    );
  }
}
