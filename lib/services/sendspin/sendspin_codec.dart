import 'package:flutter/foundation.dart';

export 'sendspin_codec_native.dart'
    if (dart.library.js_interop) 'sendspin_codec_stub.dart';

abstract class SendspinCodec {
  List<int> decode(Uint8List encodedData);
  void reset();
}

class PcmCodec implements SendspinCodec {
  final int bitDepth;
  final int channels;
  final int sampleRate;

  PcmCodec({required this.bitDepth, required this.channels, required this.sampleRate});

  @override
  List<int> decode(Uint8List encodedData) {
    if (encodedData.isEmpty) return const [];
    final view = ByteData.view(encodedData.buffer, encodedData.offsetInBytes, encodedData.lengthInBytes);

    switch (bitDepth) {
      case 16:
        final sampleCount = encodedData.length ~/ 2;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          samples[i] = view.getInt16(i * 2, Endian.little);
        }
        return samples;
      case 24:
        final sampleCount = encodedData.length ~/ 3;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          final offset = i * 3;
          var value = encodedData[offset] | (encodedData[offset + 1] << 8) | (encodedData[offset + 2] << 16);
          if (value & 0x800000 != 0) value |= 0xFF000000;
          samples[i] = value;
        }
        return samples;
      case 32:
        final sampleCount = encodedData.length ~/ 4;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          samples[i] = view.getInt32(i * 4, Endian.little);
        }
        return samples;
      default:
        throw ArgumentError('Unsupported bit depth: $bitDepth');
    }
  }

  @override
  void reset() {}
}
