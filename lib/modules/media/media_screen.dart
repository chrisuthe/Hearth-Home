import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../../services/sendspin/sendspin_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../config/hub_config.dart';
import '../../services/toast_service.dart';

const _accent = Color(0xFF646CFF);

/// Full media playback screen -- swipe left from Home to reach it.
///
/// Split layout: left panel shows now-playing controls, right panel
/// shows queue and library browser. Defaults to the local Sendspin
/// player when it's available.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    final allPlayers = ref.watch(maAllPlayersProvider).valueOrNull ?? const {};

    final config = ref.watch(hubConfigProvider);
    final manualSelection = ref.watch(selectedPlayerProvider);

    // Filter out empty keys and unavailable players.
    final validPlayers = Map.fromEntries(
        allPlayers.entries.where((e) => e.key.isNotEmpty && e.value.available));

    // Pick the active player: explicit selection, then shared default logic
    final playerId =
        manualSelection ?? pickDefaultPlayer(validPlayers, config);

    final state = playerId != null ? validPlayers[playerId] : null;

    return !music.isConnected
        ? Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: _NoMusic(
              isConnected: false,
              isConfigured: config.musicAssistantUrl.isNotEmpty,
            ),
          )
        : _AlbumArtBackdrop(
            imageUrl: state?.currentTrack?.imageUrl,
            child: Row(
              children: [
                // Left panel: now playing
                SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _ZonePicker(
                          allPlayers: validPlayers,
                          selectedPlayerId: playerId,
                          onZoneSelected: (id) =>
                              ref.read(selectedPlayerProvider.notifier).state = id,
                        ),
                        Expanded(
                          child: (state != null && state.hasTrack)
                              ? _NowPlaying(
                                  state: state,
                                  playerId: playerId!,
                                  onPlayPause: () =>
                                      music.playPause(playerId),
                                  onNext: () => music.nextTrack(playerId),
                                  onPrevious: () =>
                                      music.previousTrack(playerId),
                                  onVolumeChanged: (v) =>
                                      music.setVolume(playerId, v),
                                  onShuffleToggle: () => music.setShuffle(
                                      playerId, !state.shuffle),
                                  onRepeatToggle: () => music.setRepeat(
                                    playerId,
                                    switch (state.repeatMode) {
                                      'off' => 'all',
                                      'all' => 'one',
                                      _ => 'off',
                                    },
                                  ),
                                )
                              : const _NoMusic(isConnected: true),
                        ),
                      ],
                    ),
                  ),
                ),

                // Divider
                Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.1),
                ),

                // Right panel: queue & library
                Expanded(
                  child: _BrowsePanel(
                    playerId: playerId,
                    music: music,
                  ),
                ),
              ],
            ),
          );
  }

}

// =============================================================================
// Blurred album art backdrop for the left panel
// =============================================================================

/// Renders the current album art as a blurred, darkened background with a
/// gradient overlay. Falls back to plain black when no art is available.
class _AlbumArtBackdrop extends StatelessWidget {
  final String? imageUrl;
  final Widget child;

  const _AlbumArtBackdrop({required this.imageUrl, required this.child});

  /// Cached blur filter — always sigma 60/60 with decal tile mode, so no need
  /// to recreate on every build.
  static final ui.ImageFilter _blurFilter = ui.ImageFilter.blur(
    sigmaX: 60,
    sigmaY: 60,
    tileMode: TileMode.decal,
  );

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred album art layer
          if (imageUrl != null)
            ImageFiltered(
              imageFilter: _blurFilter,
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                // Decode at 200px wide — the heavy blur makes higher
                // resolution pointless and this saves GPU texture memory.
                cacheWidth: 200,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),

          // Dark gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),

          // Actual content
          child,
        ],
      ),
    );
  }
}

// =============================================================================
// Right panel: Queue & Library browser
// =============================================================================

class _BrowsePanel extends ConsumerStatefulWidget {
  final String? playerId;
  final MusicAssistantService music;

  const _BrowsePanel({required this.playerId, required this.music});

  @override
  ConsumerState<_BrowsePanel> createState() => _BrowsePanelState();
}

class _BrowsePanelState extends ConsumerState<_BrowsePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MaQueueItem> _queueItems = [];
  bool _queueLoading = false;

  // Library state
  List<MaMediaItem> _libraryItems = [];
  bool _libraryLoading = false;
  String _libraryType = 'artists';
  bool _albumArtistsOnly = false;
  bool _libraryHasMore = true;
  static const int _libraryPageSize = 100;
  final ScrollController _libraryScrollController = ScrollController();

  // Search state
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  MaSearchResults? _searchResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _libraryScrollController.addListener(_onLibraryScroll);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          _loadQueue();
        } else if (_libraryItems.isEmpty && _searchResults == null) {
          _loadLibrary();
        }
      }
    });
    // Load queue on init
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQueue());
  }

  @override
  void didUpdateWidget(covariant _BrowsePanel old) {
    super.didUpdateWidget(old);
    if (old.playerId != widget.playerId) {
      _loadQueue();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _libraryScrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final id = widget.playerId;
    if (id == null) return;
    setState(() => _queueLoading = true);
    try {
      final items = await widget.music.getQueueItems(id);
      if (mounted) setState(() => _queueItems = items);
    } catch (e) {
      // Queue may not be available
    }
    if (mounted) setState(() => _queueLoading = false);
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _libraryItems = [];
      _libraryHasMore = true;
      _libraryLoading = true;
    });
    await _loadLibraryPage(0);
  }

  Future<void> _loadLibraryPage(int offset) async {
    if (!_libraryHasMore && offset > 0) return;
    setState(() => _libraryLoading = true);
    try {
      final effectiveType =
          _libraryType == 'artists' && _albumArtistsOnly
              ? 'album_artists'
              : _libraryType;
      final items = await widget.music.getLibraryItems(
        effectiveType,
        limit: _libraryPageSize,
        offset: offset,
      );
      if (mounted) {
        setState(() {
          if (offset == 0) {
            _libraryItems = items;
          } else {
            _libraryItems = [..._libraryItems, ...items];
          }
          _libraryHasMore = items.length >= _libraryPageSize;
        });
      }
    } catch (e) {
      // Library may not be available
    }
    if (mounted) setState(() => _libraryLoading = false);
  }

  void _onLibraryScroll() {
    if (_libraryLoading || !_libraryHasMore) return;
    final pos = _libraryScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadLibraryPage(_libraryItems.length);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await widget.music.searchLibrary(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searching = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _playItem(MaMediaItem item) {
    final id = widget.playerId;
    if (id == null) return;
    widget.music.playMedia(id, item);
    ref.read(toastProvider.notifier).show(
      'Playing ${item.name}',
      icon: Icons.play_arrow,
    );
  }

  void _showItemContextMenu(BuildContext context, MaMediaItem item) {
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
              padding: const EdgeInsets.all(16),
              child: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _contextMenuOption(
              icon: Icons.play_arrow,
              label: 'Play Now',
              onTap: () {
                Navigator.of(context).pop();
                widget.music.playMedia(id, item, option: 'play');
                ref.read(toastProvider.notifier).show(
                  'Playing ${item.name}',
                  icon: Icons.play_arrow,
                );
              },
            ),
            _contextMenuOption(
              icon: Icons.skip_next,
              label: 'Play Next',
              onTap: () {
                Navigator.of(context).pop();
                widget.music.playMedia(id, item, option: 'next');
                ref.read(toastProvider.notifier).show(
                  'Playing next: ${item.name}',
                  icon: Icons.skip_next,
                );
              },
            ),
            _contextMenuOption(
              icon: Icons.add_to_queue,
              label: 'Add to Queue',
              onTap: () {
                Navigator.of(context).pop();
                widget.music.playMedia(id, item, option: 'add');
                ref.read(toastProvider.notifier).show(
                  'Added to queue',
                  icon: Icons.add_to_queue,
                );
              },
            ),
            _contextMenuOption(
              icon: Icons.playlist_remove,
              label: 'Clear Queue & Play',
              onTap: () {
                Navigator.of(context).pop();
                widget.music.playMedia(id, item, option: 'replace');
                ref.read(toastProvider.notifier).show(
                  'Playing ${item.name}',
                  icon: Icons.play_arrow,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _contextMenuOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _accent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          color: Colors.white.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            indicatorColor: _accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'Queue'),
              Tab(text: 'Library'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildQueueTab(),
              _buildLibraryTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Queue tab
  // ---------------------------------------------------------------------------

  Widget _buildQueueTab() {
    if (_queueLoading && _queueItems.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    if (_queueItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music,
                size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text('Queue is empty',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 15)),
          ],
        ),
      );
    }

    // Find the current track index by checking playerState
    final playerState = widget.playerId != null
        ? widget.music.playerStates[widget.playerId]
        : null;
    final currentTitle = playerState?.currentTrack?.title;

    return RefreshIndicator(
      onRefresh: _loadQueue,
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _queueItems.length,
        itemBuilder: (context, index) {
          final item = _queueItems[index];
          final isCurrent = currentTitle != null && item.title == currentTitle;
          return _QueueItemTile(
            item: item,
            isCurrent: isCurrent,
            onTap: () {
              final id = widget.playerId;
              if (id != null && item.queueItemId.isNotEmpty) {
                widget.music.playQueueItem(id, item.queueItemId);
              }
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Library tab
  // ---------------------------------------------------------------------------

  Widget _buildLibraryTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white54, size: 20),
              hintText: 'Search library...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              filled: true,
              fillColor: kDialogBackground,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Show search results or library browser
        Expanded(
          child: _searchResults != null
              ? _buildSearchResults()
              : _buildLibraryBrowser(),
        ),
      ],
    );
  }

  Widget _buildLibraryBrowser() {
    return Column(
      children: [
        // Type selector chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final type in const [
                  ('artists', 'Artists'),
                  ('albums', 'Albums'),
                  ('playlists', 'Playlists'),
                  ('tracks', 'Tracks'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(type.$2),
                      selected: _libraryType == type.$1,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _libraryType = type.$1);
                          _loadLibrary();
                        }
                      },
                      selectedColor: _accent,
                      backgroundColor: kDialogBackground,
                      labelStyle: TextStyle(
                        color: _libraryType == type.$1
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 12,
                      ),
                      side: BorderSide.none,
                    ),
                  ),
                if (_libraryType == 'artists')
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: FilterChip(
                      label: const Text('Album Artists Only'),
                      selected: _albumArtistsOnly,
                      onSelected: (selected) {
                        setState(() => _albumArtistsOnly = selected);
                        _loadLibrary();
                      },
                      selectedColor: _accent,
                      backgroundColor: kDialogBackground,
                      labelStyle: TextStyle(
                        color: _albumArtistsOnly
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 12,
                      ),
                      side: BorderSide.none,
                      avatar: Icon(
                        Icons.album,
                        size: 16,
                        color: _albumArtistsOnly
                            ? Colors.white
                            : Colors.white54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Items list
        Expanded(
          child: _libraryLoading && _libraryItems.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: _accent))
              : _libraryItems.isEmpty
                  ? Center(
                      child: Text('No items found',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5))))
                  : ListView.builder(
                      controller: _libraryScrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount:
                          _libraryItems.length + (_libraryHasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _libraryItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: _accent,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final item = _libraryItems[index];
                        return _LibraryItemTile(
                          item: item,
                          onTap: () => _playItem(item),
                          onLongPress: () =>
                              _showItemContextMenu(context, item),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searching) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    final results = _searchResults!;
    if (results.isEmpty) {
      return Center(
        child: Text('No results',
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.5))),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (results.artists.isNotEmpty) ...[
          _sectionHeader('Artists'),
          for (final item in results.artists)
            _LibraryItemTile(
                item: item,
                onTap: () => _playItem(item),
                onLongPress: () => _showItemContextMenu(context, item)),
        ],
        if (results.albums.isNotEmpty) ...[
          _sectionHeader('Albums'),
          for (final item in results.albums)
            _LibraryItemTile(
                item: item,
                onTap: () => _playItem(item),
                onLongPress: () => _showItemContextMenu(context, item)),
        ],
        if (results.tracks.isNotEmpty) ...[
          _sectionHeader('Tracks'),
          for (final item in results.tracks)
            _LibraryItemTile(
                item: item,
                onTap: () => _playItem(item),
                onLongPress: () => _showItemContextMenu(context, item)),
        ],
        if (results.playlists.isNotEmpty) ...[
          _sectionHeader('Playlists'),
          for (final item in results.playlists)
            _LibraryItemTile(
                item: item,
                onTap: () => _playItem(item),
                onLongPress: () => _showItemContextMenu(context, item)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// =============================================================================
// Tile widgets
// =============================================================================

class _QueueItemTile extends StatelessWidget {
  final MaQueueItem item;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _QueueItemTile({
    required this.item,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isCurrent ? _accent.withValues(alpha: 0.15) : null,
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: SizedBox(
          width: 40,
          height: 40,
          child: item.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(item.imageUrl!, fit: BoxFit.cover),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.music_note,
                      color: Colors.white24, size: 20),
                ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
            color: isCurrent ? Colors.white : Colors.white70,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.artist,
          style: TextStyle(
              fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isCurrent
            ? const Icon(Icons.equalizer, color: _accent, size: 18)
            : Text(
                _formatDuration(item.duration),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
      ),
    );
  }
}

class _LibraryItemTile extends StatelessWidget {
  final MaMediaItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LibraryItemTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isTrack = item.mediaType == 'track';
    final subtitle = item.artist ?? item.albumName ?? item.mediaType;

    return ListTile(
      dense: true,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: item.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(
                    item.mediaType == 'artist' ? 20 : 4),
                child: Image.network(item.imageUrl!, fit: BoxFit.cover),
              )
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(
                      item.mediaType == 'artist' ? 20 : 4),
                ),
                child: Icon(_iconForType(item.mediaType),
                    color: Colors.white24, size: 20),
              ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 13, color: Colors.white70),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
            fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isTrack && item.duration != null
          ? Text(
              _formatDuration(item.duration!),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5)),
            )
          : Icon(Icons.more_vert,
              color: Colors.white.withValues(alpha: 0.5), size: 20),
    );
  }

  static IconData _iconForType(String type) {
    return switch (type) {
      'artist' => Icons.person,
      'album' => Icons.album,
      'playlist' => Icons.playlist_play,
      'radio' => Icons.radio,
      _ => Icons.music_note,
    };
  }
}

// =============================================================================
// Now Playing (left panel)
// =============================================================================

class _NowPlaying extends StatefulWidget {
  final MusicPlayerState state;
  final String playerId;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;

  const _NowPlaying({
    required this.state,
    required this.playerId,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeChanged,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
  });

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  Timer? _ticker;
  Duration _localPosition = Duration.zero;
  Duration _lastServerPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _lastServerPosition = widget.state.position;
    _localPosition = widget.state.position;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _NowPlaying oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the server sends a new position, reset our local tracker.
    if (widget.state.position != _lastServerPosition) {
      _lastServerPosition = widget.state.position;
      _localPosition = widget.state.position;
    }
    // Start or stop the ticker when play state changes.
    if (widget.state.isPlaying != oldWidget.state.isPlaying) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.state.isPlaying) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final track = widget.state.currentTrack;
        if (track == null) return;
        if (_localPosition < track.duration) {
          setState(() {
            _localPosition += const Duration(seconds: 1);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final track = state.currentTrack!;
    final panelWidth = MediaQuery.sizeOf(context).width * 0.4 - 48;
    final artSize = min(panelWidth * 0.75, 260.0);

    // Clamp local position so it never exceeds track duration.
    final elapsed = _localPosition > track.duration
        ? track.duration
        : _localPosition;
    final progress = track.duration.inSeconds > 0
        ? elapsed.inSeconds / track.duration.inSeconds
        : 0.0;

    return Column(
      children: [
        const Spacer(),

        // Album art
        Container(
          width: artSize,
          height: artSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: track.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(track.imageUrl!, fit: BoxFit.cover),
                )
              : const Icon(Icons.album, size: 80, color: Colors.white24),
        ),

        const SizedBox(height: 20),

        // Track info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            track.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${track.artist} \u2014 ${track.album}',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 16),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(Colors.white70),
          ),
        ),

        // Time labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(elapsed),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Text(
                _formatDuration(track.duration),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Transport controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle ? Colors.white : Colors.white38,
                size: 20,
              ),
              onPressed: widget.onShuffleToggle,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 32),
              onPressed: widget.onPrevious,
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 32,
                ),
                onPressed: widget.onPlayPause,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 32),
              onPressed: widget.onNext,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                state.repeatMode == 'one' ? Icons.repeat_one : Icons.repeat,
                color:
                    state.repeatMode != 'off' ? Colors.white : Colors.white38,
                size: 20,
              ),
              onPressed: widget.onRepeatToggle,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Volume slider
        _VolumeSlider(
          serverVolume: state.volume,
          onVolumeChanged: widget.onVolumeChanged,
        ),

        const SizedBox(height: 8),

        // Sendspin sync indicator
        Consumer(builder: (context, ref, _) {
          final ss = ref.watch(sendspinStateProvider);
          return ss.maybeWhen(
            data: (s) {
              if (!s.isActive) return const SizedBox.shrink();
              final IconData icon;
              final String label;
              final Color color;
              switch (s.connectionState) {
                case SendspinConnectionState.streaming:
                  final precisionMs = s.clockOffsetMs;
                  icon = Icons.sensors;
                  label = s.clockSamples < 10
                      ? 'Syncing...'
                      : '\u00B1${precisionMs < 1 ? "<1" : precisionMs}ms';
                  color = s.clockSamples < 10
                      ? Colors.amber
                      : precisionMs < 5
                          ? Colors.green
                          : precisionMs < 20
                              ? Colors.orange
                              : Colors.red;
                case SendspinConnectionState.syncing:
                  icon = Icons.sync;
                  label = s.clockSamples > 0
                      ? 'Syncing (${s.clockSamples} samples)'
                      : 'Syncing';
                  color = Colors.amber;
                default:
                  icon = Icons.link;
                  label = 'Connected';
                  color = Colors.white38;
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          );
        }),

        const Spacer(),
      ],
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================

class _NoMusic extends StatelessWidget {
  final bool isConnected;
  final bool isConfigured;

  const _NoMusic({required this.isConnected, this.isConfigured = true});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            isConnected ? 'No music playing' : 'Music Assistant not connected',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (!isConnected) ...[
            const SizedBox(height: 8),
            Text(
              isConfigured
                  ? 'Will reconnect automatically'
                  : 'Add your MA URL and token in Settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatefulWidget {
  final double serverVolume;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeSlider({
    required this.serverVolume,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _localVolume;
  Timer? _debounce;

  double get _displayVolume => _localVolume ?? widget.serverVolume;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(double value) {
    setState(() => _localVolume = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      widget.onVolumeChanged(value);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _localVolume = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_down, color: Colors.white54, size: 20),
        Expanded(
          child: Slider(
            value: _displayVolume,
            onChanged: _onChanged,
            activeColor: Colors.white70,
            inactiveColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const Icon(Icons.volume_up, color: Colors.white54, size: 20),
      ],
    );
  }
}

class _ZonePicker extends StatelessWidget {
  final Map<String, MusicPlayerState> allPlayers;
  final String? selectedPlayerId;
  final ValueChanged<String> onZoneSelected;

  const _ZonePicker({
    required this.allPlayers,
    required this.selectedPlayerId,
    required this.onZoneSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedName = selectedPlayerId != null
        ? allPlayers[selectedPlayerId]?.activeZoneName ?? selectedPlayerId
        : 'Select zone';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showZonePicker(context),
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.white24,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speaker, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  selectedName!,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 16, color: Colors.white54),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _showZonePicker(BuildContext context) {
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Zone',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: allPlayers.entries.map((e) {
                  final isSelected = e.key == selectedPlayerId;
                  return ListTile(
                    leading: Icon(
                      e.value.isPlaying ? Icons.volume_up : Icons.speaker,
                      color: isSelected ? Colors.white : Colors.white54,
                    ),
                    title: Text(
                      e.value.activeZoneName ?? e.key,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: e.value.isPlaying
                        ? Text(
                            e.value.currentTrack?.title ?? '',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                    onTap: () {
                      onZoneSelected(e.key);
                      Navigator.of(context).pop();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
