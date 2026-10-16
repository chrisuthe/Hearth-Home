import 'dart:io' show Platform;

import 'package:flutter/scheduler.dart';

import '../utils/logger.dart';

const Duration _reportInterval = Duration(seconds: 10);

/// Logs a build/raster frame-time summary every 10 s when the process runs
/// with `HEARTH_FRAME_TIMING=1`. Off by default; used to check the blurred
/// photo background for dropped frames on a real Pi. Returns whether it
/// registered (the test's only way to tell, as the binding hides its callbacks).
bool installFrameTimingLog({Map<String, String>? environment}) {
  if ((environment ?? Platform.environment)['HEARTH_FRAME_TIMING'] != '1') {
    return false;
  }
  final batch = <FrameTiming>[];
  final clock = Stopwatch()..start();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    batch.addAll(timings);
    if (clock.elapsed < _reportInterval) return;
    Log.i('FrameTiming', summarizeFrameTimings(batch));
    batch.clear();
    clock
      ..reset()
      ..start();
  });
  return true;
}

/// One-line summary of [timings]: frame count plus build and raster p50/p95
/// in milliseconds (nearest-rank percentiles).
String summarizeFrameTimings(List<FrameTiming> timings) {
  final build = [for (final t in timings) t.buildDuration.inMicroseconds]
    ..sort();
  final raster = [for (final t in timings) t.rasterDuration.inMicroseconds]
    ..sort();
  String ms(List<int> sorted, double p) {
    if (sorted.isEmpty) return '0.0';
    final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
    return (sorted[rank - 1] / 1000).toStringAsFixed(1);
  }

  return 'frames=${timings.length} '
      'build p50=${ms(build, 0.5)} p95=${ms(build, 0.95)} '
      'raster p50=${ms(raster, 0.5)} p95=${ms(raster, 0.95)}';
}
