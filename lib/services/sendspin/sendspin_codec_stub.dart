import 'dart:typed_data';

import 'package:sendspin_dart/sendspin_dart.dart';

/// Stub FlacCodec for platforms without dart:ffi (web).
class FlacCodec implements SendspinCodec {
  FlacCodec({required int bitDepth, required int channels, required int sampleRate}) {
    throw UnsupportedError('FLAC decoding is not supported on this platform');
  }

  @override
  Int16List decode(Uint8List encodedData) => throw UnsupportedError('FLAC not supported');

  @override
  void reset() {}

  @override
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
