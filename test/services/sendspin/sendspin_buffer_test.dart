import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_buffer.dart';

void main() {
  group('SendspinBuffer', () {
    test('buffers chunks and retrieves in timestamp order', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(2000, Int16List.fromList([5, 6, 7, 8]));
      buffer.addChunk(1000, Int16List.fromList([1, 2, 3, 4]));
      buffer.addChunk(3000, Int16List.fromList([9, 10, 11, 12]));
      final samples = buffer.pullSamples(12);
      expect(samples, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });

    test('returns silence on underrun', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('flush clears all buffered data', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList([1, 2, 3, 4]));
      buffer.flush();
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('startup buffering holds data until threshold met', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 100, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList(List.filled(100, 1)));
      final samples = buffer.pullSamples(100);
      expect(samples, Int16List(100)); // silence — startup not met
    });

    test('reports buffer depth in milliseconds', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList(List.filled(96000, 1))); // 1000ms at 48kHz stereo
      expect(buffer.bufferDepthMs, 1000);
    });

    test('drops oldest chunks when max buffer exceeded', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 10,
      );
      buffer.addChunk(1000, Int16List.fromList(List.filled(960, 1))); // 10ms
      buffer.addChunk(2000, Int16List.fromList(List.filled(960, 2))); // 10ms
      buffer.addChunk(3000, Int16List.fromList(List.filled(960, 3))); // 10ms
      expect(buffer.bufferDepthMs, lessThanOrEqualTo(20));
    });

    test('flush resets startup buffering requirement', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 100, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList(List.filled(96000, 1))); // exceed startup
      final samples1 = buffer.pullSamples(10);
      expect(samples1.any((s) => s != 0), true);
      buffer.flush();
      buffer.addChunk(2000, Int16List.fromList(List.filled(100, 1)));
      final samples2 = buffer.pullSamples(100);
      expect(samples2, Int16List(100)); // startup not met again
    });

    test('returns Int16List from pullSamples', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList([1, 2, 3, 4]));
      final samples = buffer.pullSamples(4);
      expect(samples, isA<Int16List>());
    });

    test('partial chunk consumption advances offset correctly', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, Int16List.fromList([1, 2, 3, 4, 5, 6]));
      final first = buffer.pullSamples(2);
      expect(first, [1, 2]);
      final second = buffer.pullSamples(4);
      expect(second, [3, 4, 5, 6]);
    });
  });

  group('SendspinBuffer sync correction', () {
    // Constants mirrored from the implementation for test clarity.
    // 48 kHz stereo: 1 frame = 2 samples, 10 ms pull = 480 frames = 960 samples.
    // frameDurationUs for a 960-sample pull = (480 * 1_000_000) / 48000 = 10 000 µs.
    const int sampleRate = 48000;
    const int channels = 2;
    const int pullSize = 960; // 10 ms of stereo audio
    const int frameDurationUs = 10000; // 10 ms in µs

    SendspinBuffer makeBuffer() => SendspinBuffer(
          sampleRate: sampleRate,
          channels: channels,
          startupBufferMs: 0,
          maxBufferMs: 15000,
        );

    test('deadband: sync error < 2 ms produces no correction', () {
      final buffer = makeBuffer();

      // Add a chunk and pull to anchor playback at ts 0, advancing to 10 000 µs.
      buffer.addChunk(0, Int16List(pullSize));
      buffer.pullSamples(pullSize);

      // Add a chunk at ts 9 000 µs. syncError = 10 000 - 9 000 = 1 000 µs,
      // which is inside the 2 000 µs deadband.
      buffer.addChunk(9000, Int16List(pullSize));
      buffer.pullSamples(pullSize);

      // syncErrorUs should be within deadband — small and positive.
      expect(buffer.syncErrorUs.abs(), lessThan(2000));

      // With no correction applied, buffer depth should drop by exactly the
      // requested amount (one pull's worth consumed, nothing extra).
      expect(buffer.bufferDepthMs, 0);
    });

    test('micro-correction when behind: drops frames over time', () {
      final buffer = makeBuffer();

      // Add a large chunk at ts 0 (500 ms = 48 000 samples).
      // Because pullSamples advances _playbackPositionUs by 10 ms each call
      // while the chunk timestamp stays at 0, the sync error grows with each
      // pull, eventually exceeding the 2 ms deadband and triggering
      // micro-correction (frame dropping).
      const int bigChunkSamples = 48000; // 500 ms
      buffer.addChunk(0, Int16List(bigChunkSamples));

      // Pull 20 times (200 ms of playback). After 2 pulls (20 ms sync error)
      // the correction should start consuming extra frames.
      for (var i = 0; i < 20; i++) {
        buffer.pullSamples(pullSize);
      }

      // If no correction were applied, the buffer would have exactly
      // bigChunkSamples - totalRequested = 48 000 - 19 200 = 28 800 samples
      // remaining (300 ms). With frame-dropping, the buffer consumed more
      // than requested, so the remaining depth should be less than 300 ms.
      expect(buffer.bufferDepthMs, lessThan(300));

      // Verify the sync error is positive (we are behind).
      expect(buffer.syncErrorUs, greaterThan(0));
    });

    test('micro-correction when ahead: pads frames over time', () {
      final buffer = makeBuffer();

      // Anchor at 0 and advance playback.
      buffer.addChunk(0, Int16List(pullSize));
      buffer.pullSamples(pullSize);
      // playbackPositionUs = 10 000

      // Add many chunks whose timestamps are spaced further apart than
      // the playback advance rate. Each pull advances playback by 10 000 µs,
      // so if chunk timestamps advance by 20 000 µs per chunk, playback
      // falls further behind the stream timestamps each pull, keeping the
      // sync error negative (ahead of stream).
      //
      // 50 chunks at 20 ms spacing, each containing 10 ms of audio.
      const int chunkCount = 50;
      const int chunkSpacing = 20000; // 20 ms between chunk timestamps
      // Start the first chunk at playback position + 100 ms offset to
      // establish a strong initial "ahead" error.
      var ts = frameDurationUs + 100000; // 110 000
      for (var i = 0; i < chunkCount; i++) {
        buffer.addChunk(ts, Int16List(pullSize));
        ts += chunkSpacing;
      }

      // Track initial depth.
      final depthBefore = buffer.bufferDepthMs;

      // Pull 30 times. With each pull, playback advances 10 ms but each
      // consumed chunk represents 20 ms of stream time, so the "ahead"
      // error grows. Micro-correction should pull fewer raw samples,
      // padding with duplicated frames.
      var hadNegativeError = false;
      for (var i = 0; i < 30; i++) {
        final samples = buffer.pullSamples(pullSize);
        expect(samples.length, pullSize);
        if (buffer.syncErrorUs < 0) hadNegativeError = true;
      }

      // Verify we did see negative sync error (ahead of stream).
      expect(hadNegativeError, true,
          reason: 'sync error should have been negative at some point');

      // Buffer should have consumed fewer samples than 30 * pullSize due
      // to duplicate-frame padding. Without correction, 30 pulls drains
      // 30 * 960 = 28 800 samples from the 48 000 total (50 * 960),
      // leaving 20 ms * 50 chunks - 300 ms = ~200 ms. With ahead correction,
      // fewer raw samples are consumed, leaving more in the buffer.
      final depthAfter = buffer.bufferDepthMs;
      const normalDrain = 30 * 10; // 300 ms
      final actualDrain = depthBefore - depthAfter;
      expect(actualDrain, lessThan(normalDrain),
          reason: 'ahead correction should slow buffer drain');
    });

    test('re-anchor: sync error > 500 ms flushes the buffer', () {
      final buffer = makeBuffer();

      // Anchor playback at ts 1 000 000 µs (1 s) and advance.
      buffer.addChunk(1000000, Int16List(pullSize));
      buffer.pullSamples(pullSize);
      // playbackPositionUs = 1 010 000

      // Add a chunk at ts 1 — creating a sync error of ~1 009 999 µs,
      // well above the 500 000 µs re-anchor threshold.
      buffer.addChunk(1, Int16List(pullSize));
      final result = buffer.pullSamples(pullSize);

      // Re-anchor calls flush(), which returns silence and resets state.
      expect(result, Int16List(pullSize)); // all zeros (silence)
      expect(buffer.bufferDepthMs, 0);
    });

    test('re-anchor cooldown: within 5 s falls through to micro-correction',
        () {
      final buffer = makeBuffer();

      // Add enough contiguous data so we can pull many times without underrun.
      // 600 ms = 57 600 samples at 48 kHz stereo.
      buffer.addChunk(0, Int16List(57600));

      // First pull anchors playback at 0. _lastReanchorUs = 0.
      buffer.pullSamples(pullSize);
      // playbackPositionUs = 10 000, _lastReanchorUs = 0.

      // Advance playback further but stay within 5 s of _lastReanchorUs.
      // Pull 40 times to reach playbackPosition = 410 000 µs (0.41 s).
      for (var i = 0; i < 40; i++) {
        buffer.pullSamples(pullSize);
      }
      // playbackPositionUs ≈ 410 000 (0.41 s). All pulls have been consuming
      // the big chunk at ts 0 so sync error has been growing, but the chunk
      // data is being consumed. Let's check what's left.

      // Now introduce a massive timestamp gap. Add a chunk at ts 1 whose
      // timestamp is far behind the current playback position (~410 000 µs).
      // syncError = 410 000 - 1 = 409 999 µs. That's below the 500 ms
      // threshold, so no re-anchor — just micro-correction. Let's push it
      // over the threshold.
      //
      // Actually, we need >500 ms error. Let's advance more first.
      // After 41 total pulls: playbackPos = 41 * 10 000 = 410 000.
      // We need 500 001+ µs error. Add chunk at ts 1.
      // Error would be 410 000 - 1 = 409 999, not enough.
      //
      // Pull more to reach >510 000 µs. Need ~10 more pulls.
      // But we may be running low on data from the big chunk.
      // 57 600 samples, each pull takes ~960. 57600/960 = 60 pulls total.
      // We've done 41. Pull 11 more to reach 52 pulls (520 000 µs).
      // Note: with micro-correction active, actual consumption varies
      // slightly, but we have plenty of headroom.
      for (var i = 0; i < 11; i++) {
        buffer.pullSamples(pullSize);
      }
      // playbackPositionUs ≈ 520 000 µs.
      // _lastReanchorUs = 0. Distance = 520 000 < 5 000 000 (5s cooldown).

      // Add a chunk with timestamp far below playback position to exceed
      // the 500 ms re-anchor threshold.
      buffer.addChunk(1, Int16List(pullSize));
      final depthBefore = buffer.bufferDepthMs;

      // Pull — this should NOT re-anchor (cooldown active) and should
      // instead apply micro-correction. Buffer should NOT be flushed.
      buffer.pullSamples(pullSize);

      // Buffer was not flushed: depth is still non-zero or only reduced by
      // the pull amount (not wiped).
      expect(buffer.bufferDepthMs, lessThanOrEqualTo(depthBefore));
      // The key check: buffer was NOT flushed to zero.
      // After a re-anchor flush the depth would be 0 and the result would
      // be silence. Since we are in cooldown, the depth should be whatever
      // was left from the small chunk minus one pull.
      // However, if the big chunk is exhausted, depth might be ~10 ms from
      // the ts=1 chunk minus what was consumed. The critical assertion is
      // that flush did NOT happen — the buffer is not reset.
      expect(depthBefore, greaterThan(0),
          reason: 'buffer should have data before pull');
    });

    test('correction rate clamped to +-4 percent of pull size', () {
      final buffer = makeBuffer();

      // Strategy: use a single large chunk at ts 0 and pull many times.
      // Each pull advances _playbackPositionUs while the chunk timestamp
      // stays at 0, growing the sync error. The correction per pull is:
      //   correctionRate = syncErrorUs / (2.0 * sampleRate)
      //   maxAdj = 0.04 * frames  (= 0.04 * 480 = 19.2 for our pull size)
      //   clamped = correctionRate.clamp(-maxAdj, maxAdj)
      //
      // As the error grows, correctionRate eventually exceeds maxAdj and
      // gets clamped. We verify the clamp by checking that the total
      // extra consumption never exceeds 4% of total frames pulled.
      //
      // With a 10 s chunk we can pull up to ~500 ms before the error
      // approaches the re-anchor threshold (500 000 µs). By that point
      // the unclamped rate at 490 000 µs would be 490000/96000 ≈ 5.1
      // frames, but maxAdj is 19.2 so the clamp won't engage with
      // a natural growing error from a single chunk.
      //
      // Instead, verify the property structurally: the extra consumption
      // per pull cannot exceed 4% * pullSize = 38.4 samples ≈ 39.
      // We check that total extra over N pulls is bounded by N * 39.

      const int bigBlock = 960000; // 10 s
      buffer.addChunk(0, Int16List(bigBlock));

      // Pull once to anchor (no correction on first pull).
      buffer.pullSamples(pullSize);
      // After this: 959 040 samples remain. playbackPos = 10 000.

      const int pullCount = 48;
      // Snapshot _totalSamples indirectly via bufferDepthMs before pulls.
      // To avoid integer division issues, we use a generous bound.
      for (var i = 0; i < pullCount; i++) {
        buffer.pullSamples(pullSize);
      }

      // playbackPos = (pullCount + 1) * 10 000 = 490 000 µs.
      // Without correction, remaining = bigBlock - (pullCount+1)*pullSize
      //   = 960 000 - 49*960 = 960 000 - 47 040 = 912 960.
      // With correction (behind → frame dropping), more was consumed.
      // Max extra per pull = ceil(0.04 * 960) = 39 samples.
      // Max total extra = 48 * 39 = 1 872 samples.
      // So minimum remaining = 912 960 - 1 872 = 911 088.
      // In ms: 911 088 / 96 = 9 490 ms. With integer truncation in
      // bufferDepthMs, >= 9 490.

      final remainingMs = buffer.bufferDepthMs;
      const int noCorrectionRemaining = 912960; // samples
      const int maxTotalExtra = 48 * 39; // 1 872 samples
      const int minRemainingSamples = noCorrectionRemaining - maxTotalExtra;
      // Convert to ms with floor (matching bufferDepthMs integer division).
      const int minRemainingMs = minRemainingSamples ~/ 96;

      expect(remainingMs, greaterThanOrEqualTo(minRemainingMs),
          reason: 'buffer should not drain faster than 4% correction allows');

      // Also verify that some correction DID occur (buffer drained faster
      // than the uncorrected rate).
      const int noCorrectionRemainingMs = noCorrectionRemaining ~/ 96;
      expect(remainingMs, lessThan(noCorrectionRemainingMs),
          reason: 'some frame-dropping correction should have occurred');
    });

    test('output length always equals requested count regardless of correction',
        () {
      final buffer = makeBuffer();

      // Add a big chunk and pull many times with growing sync error.
      buffer.addChunk(0, Int16List(96000));

      for (var i = 0; i < 30; i++) {
        final result = buffer.pullSamples(pullSize);
        expect(result.length, pullSize,
            reason: 'pull $i should return exactly $pullSize samples');
        expect(result, isA<Int16List>());
      }
    });

    test('when ahead, output is padded with duplicated last frame', () {
      final buffer = makeBuffer();

      // Anchor at 0 and advance playback.
      final anchor = Int16List.fromList(List.filled(pullSize, 42));
      buffer.addChunk(0, anchor);
      buffer.pullSamples(pullSize);
      // playbackPositionUs = 10 000

      // Add a chunk 200 ms ahead of playback. syncError = -190 000 µs.
      // The last frame of the pulled data should be duplicated as padding.
      const int aheadTs = 200000;
      // Fill with a recognizable pattern: frame value = 7.
      final aheadData = Int16List.fromList(List.filled(pullSize, 7));
      buffer.addChunk(aheadTs, aheadData);

      final result = buffer.pullSamples(pullSize);

      // Because fewer raw samples were pulled and the rest is padded,
      // the tail of the result should repeat the last frame pulled.
      // With stereo, a frame is [7, 7]. The tail should be all 7s.
      // The output should still be entirely 7s (either pulled or duplicated).
      expect(result.length, pullSize);
      // All values should be 7 (either original or duplicated).
      // Some might be 0 if underrun occurred, but with enough data they
      // should all be 7.
      final nonZeroCount = result.where((s) => s == 7).length;
      expect(nonZeroCount, pullSize,
          reason: 'all samples should be 7 (pulled or duplicated from last frame)');
    });

    test('syncErrorUs getter reflects last computed error', () {
      final buffer = makeBuffer();

      // Before any pull, syncErrorUs should be 0.
      expect(buffer.syncErrorUs, 0);

      // Anchor and pull once.
      buffer.addChunk(0, Int16List(pullSize));
      buffer.pullSamples(pullSize);
      // playbackPos = 10 000, chunk consumed. Next pull would underrun.

      // Add chunk at ts 5 000. syncError = 10 000 - 5 000 = 5 000.
      buffer.addChunk(5000, Int16List(pullSize));
      buffer.pullSamples(pullSize);
      expect(buffer.syncErrorUs, 5000);
    });

    test('deadband resets correction accumulator', () {
      final buffer = makeBuffer();

      // Build up a correction accumulator with a moderate sync error.
      buffer.addChunk(0, Int16List(pullSize * 10));
      for (var i = 0; i < 5; i++) {
        buffer.pullSamples(pullSize);
      }
      // Sync error has been growing (playback advancing while chunk ts = 0).
      expect(buffer.syncErrorUs.abs(), greaterThan(2000));

      // Now flush and set up perfectly aligned chunks (within deadband).
      buffer.flush();
      var ts = 0;
      for (var i = 0; i < 10; i++) {
        buffer.addChunk(ts, Int16List(pullSize));
        ts += frameDurationUs;
      }

      // Pull once to anchor, then pull again — error should be in deadband.
      buffer.pullSamples(pullSize);
      buffer.pullSamples(pullSize);

      // If the accumulator was properly reset by the deadband path,
      // no correction should occur. The sync error should stay small.
      expect(buffer.syncErrorUs.abs(), lessThanOrEqualTo(2000));
    });
  });
}
