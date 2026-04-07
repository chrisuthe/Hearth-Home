import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_codec.dart';

void main() {
  group('PcmCodec', () {
    test('decodes 16-bit little-endian stereo PCM', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      final bytes = Uint8List(8);
      final view = ByteData.view(bytes.buffer);
      view.setInt16(0, 100, Endian.little);
      view.setInt16(2, 200, Endian.little);
      view.setInt16(4, 300, Endian.little);
      view.setInt16(6, 400, Endian.little);
      final samples = codec.decode(bytes);
      expect(samples.length, 4);
      expect(samples[0], 100);
      expect(samples[1], 200);
      expect(samples[2], 300);
      expect(samples[3], 400);
    });

    test('decodes 24-bit little-endian PCM', () {
      final codec = PcmCodec(bitDepth: 24, channels: 2, sampleRate: 48000);
      final bytes = Uint8List(6);
      bytes[0] = 0xE8; bytes[1] = 0x03; bytes[2] = 0x00; // 1000
      bytes[3] = 0xD0; bytes[4] = 0x07; bytes[5] = 0x00; // 2000
      final samples = codec.decode(bytes);
      expect(samples.length, 2);
      expect(samples[0], 1000);
      expect(samples[1], 2000);
    });

    test('reset does nothing for PCM (stateless)', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      codec.reset();
    });

    test('returns empty list for empty input', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      final samples = codec.decode(Uint8List(0));
      expect(samples, isEmpty);
    });
  });

  group('createCodec', () {
    test('creates PcmCodec for pcm codec string', () {
      final codec = createCodec(codec: 'pcm', bitDepth: 16, channels: 2, sampleRate: 48000);
      expect(codec, isA<PcmCodec>());
    });

    test('throws for unsupported codec', () {
      expect(
        () => createCodec(codec: 'opus', bitDepth: 16, channels: 2, sampleRate: 48000),
        throwsArgumentError,
      );
    });
  });
}
