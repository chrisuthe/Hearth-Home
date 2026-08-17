import '../models/photo_memory.dart';

/// One source's fetched photos plus the weight the user assigned it.
class WeightedPool {
  final List<PhotoMemory> photos;
  final int weight;

  const WeightedPool({required this.photos, required this.weight});
}

/// Build the carousel pool so each source occupies a share of the feed
/// proportional to its weight.
///
/// The carousel cycles this list forever, so a source's share of the list
/// is its share of screen time. A pool smaller than its allotted share is
/// repeated to fill it — that is what lets "mostly Memories" hold on a day
/// with only a handful of memories.
///
/// When a pool is too small to fill its share even at [maxRepeat] copies,
/// the whole union shrinks rather than handing the surplus to the other
/// sources: redistributing would push the mix further from the ratio the
/// user asked for, which is the opposite of the point.
List<PhotoMemory> allocateWeighted(
  List<WeightedPool> pools, {
  required int totalSlots,
  int maxRepeat = 10,
}) {
  final active =
      pools.where((p) => p.photos.isNotEmpty && p.weight > 0).toList();
  if (active.isEmpty) return const [];

  // With one source there is no ratio to honour, so repeating photos would
  // only bloat the pool and the prefetch queue. Keep today's behaviour.
  if (active.length == 1) {
    final photos = List<PhotoMemory>.of(active.single.photos)..shuffle();
    return photos.length > totalSlots ? photos.sublist(0, totalSlots) : photos;
  }

  final totalWeight = active.fold<int>(0, (sum, p) => sum + p.weight);

  // Slots per unit of weight. Three ceilings apply, and the smallest wins:
  //
  //  1. the slot budget;
  //  2. how far the least-stretchable pool reaches before exceeding
  //     maxRepeat copies of itself;
  //  3. the point past which every pool is already fully used — growing
  //     beyond that just adds copies without adding variety.
  var slotsPerWeight = totalSlots / totalWeight;
  var fullyUsed = 0.0;
  for (final p in active) {
    final ceiling = (p.photos.length * maxRepeat) / p.weight;
    if (ceiling < slotsPerWeight) slotsPerWeight = ceiling;
    final exhausts = p.photos.length / p.weight;
    if (exhausts > fullyUsed) fullyUsed = exhausts;
  }
  if (fullyUsed < slotsPerWeight) slotsPerWeight = fullyUsed;

  final union = <PhotoMemory>[];
  for (final p in active) {
    final slots = (slotsPerWeight * p.weight).round();
    for (var i = 0; i < slots; i++) {
      union.add(p.photos[i % p.photos.length]);
    }
  }
  union.shuffle();
  return union;
}
