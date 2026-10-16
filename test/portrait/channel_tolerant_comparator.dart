import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// A golden comparator that passes when every RGBA channel of every pixel is
/// within [tolerance] of the baseline. The tolerance absorbs float-alpha
/// rounding (`inkAt(0.12)` against `white12`'s `0x1F`) and nothing larger.
class ChannelTolerantComparator extends LocalFileComparator {
  ChannelTolerantComparator(super.testFile, {this.tolerance = 2});

  final int tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenFile = File.fromUri(basedir.resolveUri(golden));
    if (!goldenFile.existsSync()) {
      throw TestFailure('Golden missing: ${goldenFile.path}');
    }
    final actual = await _decode(imageBytes);
    final expected = await _decode(await goldenFile.readAsBytes());

    if (actual.width != expected.width || actual.height != expected.height) {
      await _writeActual(goldenFile, imageBytes);
      throw TestFailure(
        'Golden size differs: ${actual.width}x${actual.height} vs '
        '${expected.width}x${expected.height} (${goldenFile.path})',
      );
    }

    var differing = 0;
    final a = actual.bytes;
    final e = expected.bytes;
    for (var i = 0; i < a.length; i += 4) {
      for (var ch = 0; ch < 4; ch++) {
        if ((a[i + ch] - e[i + ch]).abs() > tolerance) {
          differing++;
          break;
        }
      }
    }
    if (differing == 0) return true;

    await _writeActual(goldenFile, imageBytes);
    throw TestFailure(
      '$differing pixels differ by more than $tolerance per channel '
      '(${goldenFile.path})',
    );
  }

  Future<void> _writeActual(File goldenFile, Uint8List bytes) async {
    final path = goldenFile.path;
    final base = path.endsWith('.png')
        ? path.substring(0, path.length - 4)
        : path;
    await File('$base.actual.png').writeAsBytes(bytes);
  }

  Future<({int width, int height, Uint8List bytes})> _decode(
    Uint8List png,
  ) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (
      width: image.width,
      height: image.height,
      bytes: data!.buffer.asUint8List(),
    );
    image.dispose();
    codec.dispose();
    return result;
  }
}
