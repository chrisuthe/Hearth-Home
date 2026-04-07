import 'dart:typed_data';

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

SendspinCodec createCodec({required String codec, required int bitDepth, required int channels, required int sampleRate}) {
  switch (codec) {
    case 'pcm':
      return PcmCodec(bitDepth: bitDepth, channels: channels, sampleRate: sampleRate);
    case 'flac':
      throw ArgumentError('FLAC codec not yet implemented');
    default:
      throw ArgumentError('Unsupported codec: $codec');
  }
}
