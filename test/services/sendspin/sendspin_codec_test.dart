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
      expect(samples, isA<Int16List>());
      expect(samples.length, 4);
      expect(samples[0], 100);
      expect(samples[1], 200);
      expect(samples[2], 300);
      expect(samples[3], 400);
    });

    test('decodes 24-bit little-endian PCM truncated to 16-bit', () {
      final codec = PcmCodec(bitDepth: 24, channels: 2, sampleRate: 48000);
      // Encode two 24-bit samples: 0x100000 (1048576) and 0x200000 (2097152)
      // These truncate to 0x1000 (4096) and 0x2000 (8192) as Int16.
      final bytes = Uint8List(6);
      bytes[0] = 0x00; bytes[1] = 0x00; bytes[2] = 0x10; // 0x100000
      bytes[3] = 0x00; bytes[4] = 0x00; bytes[5] = 0x20; // 0x200000
      final samples = codec.decode(bytes);
      expect(samples, isA<Int16List>());
      expect(samples.length, 2);
      expect(samples[0], 0x1000);
      expect(samples[1], 0x2000);
    });

    test('reset does nothing for PCM (stateless)', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      codec.reset();
    });

    test('returns empty Int16List for empty input', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      final samples = codec.decode(Uint8List(0));
      expect(samples, isA<Int16List>());
      expect(samples, isEmpty);
    });
  });

  group('createCodec', () {
    test('creates PcmCodec for pcm codec string', () {
      final codec = createCodec(codec: 'pcm', bitDepth: 16, channels: 2, sampleRate: 48000);
      expect(codec, isA<PcmCodec>());
    });

    test('creates FlacCodec for flac codec string (requires native library)', () {
      // FlacCodec loads a native shared library via FFI, so instantiation will
      // throw in the test environment where the library isn't available.
      // This test verifies the factory routes 'flac' to FlacCodec construction
      // (which fails loading the DLL) rather than throwing 'Unsupported codec'.
      expect(
        () => createCodec(codec: 'flac', bitDepth: 16, channels: 2, sampleRate: 48000),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('sendspin_flac'),
          ),
        ),
      );
    });

    test('throws for unsupported codec', () {
      expect(
        () => createCodec(codec: 'opus', bitDepth: 16, channels: 2, sampleRate: 48000),
        throwsArgumentError,
      );
    });
  });
}
