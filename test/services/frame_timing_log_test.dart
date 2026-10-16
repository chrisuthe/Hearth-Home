import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/frame_timing_log.dart';

FrameTiming _frame(int buildMs, int rasterMs) => FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: buildMs * 1000,
      rasterStart: buildMs * 1000,
      rasterFinish: (buildMs + rasterMs) * 1000,
      rasterFinishWallTime: (buildMs + rasterMs) * 1000,
    );

void main() {
  test('summarizes build and raster percentiles (nearest rank)', () {
    final timings = [for (var i = 1; i <= 20; i++) _frame(2, i)];
    expect(
      summarizeFrameTimings(timings),
      'frames=20 build p50=2.0 p95=2.0 raster p50=10.0 p95=19.0',
    );
  });

  test('empty list does not throw', () {
    expect(summarizeFrameTimings([]),
        'frames=0 build p50=0.0 p95=0.0 raster p50=0.0 p95=0.0');
  });

  test('registers nothing unless HEARTH_FRAME_TIMING=1', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(installFrameTimingLog(environment: {}), isFalse);
    expect(installFrameTimingLog(environment: {'HEARTH_FRAME_TIMING': '0'}),
        isFalse);
    expect(installFrameTimingLog(environment: {'HEARTH_FRAME_TIMING': '1'}),
        isTrue);
  });
}
