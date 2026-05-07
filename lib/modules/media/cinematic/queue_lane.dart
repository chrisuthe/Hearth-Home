import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';

/// Queue lane below the transport row. Phase 1 renders the horizontal
/// "cards" variant per the design (130×130 art + title + artist). The
/// list variant and drag-to-reorder are deferred to later phases.
///
/// Queue items are fetched once on mount via `getQueueItems`; we don't
/// yet re-subscribe to `queue_updated` events to keep this lightweight
/// in Phase 1. Stale-while-track-changes is acceptable until Phase 5
/// addresses reactive refresh.
class QueueLane extends ConsumerStatefulWidget {
  final String playerId;
  final String? currentQueueItemId;

  const QueueLane({
    super.key,
    required this.playerId,
    this.currentQueueItemId,
  });

  @override
  ConsumerState<QueueLane> createState() => _QueueLaneState();
}

class _QueueLaneState extends ConsumerState<QueueLane> {
  late Future<List<MaQueueItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant QueueLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playerId != oldWidget.playerId) {
      _future = _fetch();
    }
  }

  Future<List<MaQueueItem>> _fetch() {
    final music = ref.read(musicAssistantServiceProvider);
    return music.getQueueItems(widget.playerId, limit: 25);
  }

  void _playItem(MaQueueItem item) {
    if (item.queueItemId.isEmpty) return;
    ref.read(musicAssistantServiceProvider).playQueueItem(
          widget.playerId,
          item.queueItemId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(),
        const SizedBox(height: HearthSpacing.x3),
        SizedBox(
          height: 178,
          child: FutureBuilder<List<MaQueueItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  ),
                );
              }
              final items = snap.data ?? const <MaQueueItem>[];
              final upcoming = _upcomingFromQueue(items);
              if (upcoming.isEmpty) {
                return const Center(
                  child: Text(
                    'Nothing queued',
                    style: TextStyle(
                      fontSize: HearthFont.caption,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: upcoming.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _QueueCard(
                  item: upcoming[i],
                  onTap: () => _playItem(upcoming[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Drop the currently-playing item from the queue list. The queue
  /// returned by MA includes the playing item; the design's queue lane
  /// is "Up Next", so anything after the current track is what we
  /// want. Falls back to skipping the first item when no current id.
  List<MaQueueItem> _upcomingFromQueue(List<MaQueueItem> items) {
    if (items.isEmpty) return const [];
    final currentId = widget.currentQueueItemId;
    if (currentId != null) {
      final idx = items.indexWhere((it) => it.queueItemId == currentId);
      if (idx >= 0) return items.skip(idx + 1).toList();
    }
    return items.skip(1).toList();
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text(
          'UP NEXT',
          style: TextStyle(
            fontSize: HearthFont.caption,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends StatelessWidget {
  final MaQueueItem item;
  final VoidCallback onTap;

  const _QueueCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MediaRadii.smallArt),
      child: SizedBox(
        width: 130,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.04),
              borderRadius: BorderRadius.circular(MediaRadii.smallArt),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.imageUrl == null
                ? const Center(
                    child: Icon(
                      Icons.music_note,
                      size: HearthSpacing.x8,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  )
                : Image.network(
                    item.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 260,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image,
                      size: HearthSpacing.x8,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: HearthFont.label,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w500,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.meta),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
