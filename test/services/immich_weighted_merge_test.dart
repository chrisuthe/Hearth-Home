import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/photo_memory.dart';
import 'package:hearth/services/immich_weighted_merge.dart';

PhotoMemory _photo(String id) => PhotoMemory(
      assetId: id,
      imageUrl: 'https://immich.example/$id.jpg',
      memoryDate: DateTime(2024, 1, 1),
      yearsAgo: 0,
    );

List<PhotoMemory> _pool(String prefix, int count) =>
    List.generate(count, (i) => _photo('$prefix-$i'));

/// Share of [union] contributed by assets whose id starts with [prefix].
double _share(List<PhotoMemory> union, String prefix) =>
    union.where((p) => p.assetId.startsWith(prefix)).length / union.length;

void main() {
  group('allocateWeighted', () {
    test('splits evenly across equal weights and equal pools', () {
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('a', 50), weight: 1),
          WeightedPool(photos: _pool('b', 50), weight: 1),
        ],
        totalSlots: 100,
      );

      expect(_share(union, 'a'), closeTo(0.5, 0.02));
      expect(_share(union, 'b'), closeTo(0.5, 0.02));
    });

    test('honours a 3:1:1 weighting as feed share', () {
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('mem', 50), weight: 3),
          WeightedPool(photos: _pool('alb', 50), weight: 1),
          WeightedPool(photos: _pool('ppl', 50), weight: 1),
        ],
        totalSlots: 150,
      );

      expect(_share(union, 'mem'), closeTo(0.6, 0.03));
      expect(_share(union, 'alb'), closeTo(0.2, 0.03));
      expect(_share(union, 'ppl'), closeTo(0.2, 0.03));
    });

    test('repeats a small pool so its weighted share is still met', () {
      // 6 memories vs 50 album, weighted 3:1 -> memories must still be 75%,
      // which is only reachable by repeating the 6.
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('mem', 6), weight: 3),
          WeightedPool(photos: _pool('alb', 50), weight: 1),
        ],
        totalSlots: 100,
      );

      expect(_share(union, 'mem'), closeTo(0.75, 0.03));
      // All six unique memories are in play, not just one repeated.
      expect(
        union.where((p) => p.assetId.startsWith('mem')).map((p) => p.assetId).toSet(),
        hasLength(6),
      );
    });

    test('caps repetition and shrinks the pool rather than skewing the ratio',
        () {
      // A single-photo source at weight 3 cannot fill 75% of a large feed.
      // The ratio must hold, so the whole union shrinks instead of letting
      // the big pool take over.
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('mem', 1), weight: 3),
          WeightedPool(photos: _pool('alb', 500), weight: 1),
        ],
        totalSlots: 400,
        maxRepeat: 10,
      );

      expect(_share(union, 'mem'), closeTo(0.75, 0.05));
      // 1 photo x 10 repeats is the ceiling for the memories side.
      expect(union.where((p) => p.assetId.startsWith('mem')), hasLength(10));
      expect(union.length, lessThan(20));
    });

    test('never repeats when only one source is enabled', () {
      final union = allocateWeighted(
        [WeightedPool(photos: _pool('a', 8), weight: 1)],
        totalSlots: 50,
      );

      expect(union, hasLength(8));
      expect(union.map((p) => p.assetId).toSet(), hasLength(8));
    });

    test('truncates a single oversized source to the slot budget', () {
      final union = allocateWeighted(
        [WeightedPool(photos: _pool('a', 80), weight: 1)],
        totalSlots: 50,
      );

      expect(union, hasLength(50));
    });

    test('does not inflate the pool beyond what the ratio needs', () {
      // Two small pools at equal weight need only 3:3 to be 50/50. Filling
      // the whole 100-slot budget would mean 20 copies each of 5 photos.
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('a', 3), weight: 1),
          WeightedPool(photos: _pool('b', 2), weight: 1),
        ],
        totalSlots: 100,
      );

      expect(union, hasLength(6));
      expect(_share(union, 'a'), closeTo(0.5, 0.01));
      // Every unique photo from the larger pool is used.
      expect(
        union.where((p) => p.assetId.startsWith('a')).map((p) => p.assetId).toSet(),
        hasLength(3),
      );
    });

    test('ignores pools that returned nothing', () {
      final union = allocateWeighted(
        [
          WeightedPool(photos: _pool('a', 50), weight: 1),
          const WeightedPool(photos: [], weight: 5),
        ],
        totalSlots: 100,
      );

      expect(_share(union, 'a'), 1.0);
    });

    test('returns empty when every pool is empty', () {
      final union = allocateWeighted(
        [const WeightedPool(photos: [], weight: 1)],
        totalSlots: 100,
      );

      expect(union, isEmpty);
    });
  });
}
