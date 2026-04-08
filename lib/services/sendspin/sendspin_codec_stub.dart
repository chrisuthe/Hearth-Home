import 'package:flutter/foundation.dart';

import 'sendspin_codec.dart';

/// Stub FlacCodec for platforms without dart:ffi (web).
class FlacCodec implements SendspinCodec {
  FlacCodec({required int bitDepth, required int channels, required int sampleRate}) {
    throw UnsupportedError('FLAC decoding is not supported on this platform');
  }

  @override
  List<int> decode(Uint8List encodedData) => throw UnsupportedError('FLAC not supported');

  @override
  void reset() {}

  void dispose() {}
}

SendspinCodec createCodec({
  required String codec,
  required int bitDepth,
  required int channels,
  required int sampleRate,
}) {
  switch (codec) {
    case 'pcm':
      return PcmCodec(bitDepth: bitDepth, channels: channels, sampleRate: sampleRate);
    case 'flac':
      return FlacCodec(bitDepth: bitDepth, channels: channels, sampleRate: sampleRate);
    default:
      throw ArgumentError('Unsupported codec: $codec');
  }
}
