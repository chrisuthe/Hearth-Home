import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'flac_ffi.dart';

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

class FlacCodec implements SendspinCodec {
  final int bitDepth;
  final int channels;
  final int sampleRate;

  static final FlacFfi _ffi = FlacFfi();
  late final Pointer<Void> _decoder;

  // Max FLAC block size is 65535 samples; for stereo that's 131070 int32s.
  static const int _maxOutputSamples = 65536 * 2;
  late final Pointer<Int32> _outputBuf;

  FlacCodec(
      {required this.bitDepth,
      required this.channels,
      required this.sampleRate}) {
    _decoder = _ffi.create();
    _outputBuf = calloc<Int32>(_maxOutputSamples);
  }

  @override
  List<int> decode(Uint8List encodedData) {
    if (encodedData.isEmpty) return const [];

    // Copy input to native memory
    final inputBuf = calloc<Uint8>(encodedData.length);
    inputBuf.asTypedList(encodedData.length).setAll(0, encodedData);

    final sampleCount = _ffi.decode(
      _decoder,
      inputBuf,
      encodedData.length,
      _outputBuf,
      _maxOutputSamples,
    );

    calloc.free(inputBuf);

    if (sampleCount < 0) {
      debugPrint('FlacCodec: decode error');
      return const [];
    }

    // Copy from native to Dart
    return _outputBuf.asTypedList(sampleCount).toList();
  }

  @override
  void reset() {
    _ffi.reset(_decoder);
  }

  void dispose() {
    _ffi.free(_decoder);
    calloc.free(_outputBuf);
  }
}

SendspinCodec createCodec(
    {required String codec,
    required int bitDepth,
    required int channels,
    required int sampleRate}) {
  switch (codec) {
    case 'pcm':
      return PcmCodec(
          bitDepth: bitDepth, channels: channels, sampleRate: sampleRate);
    case 'flac':
      return FlacCodec(
          bitDepth: bitDepth, channels: channels, sampleRate: sampleRate);
    default:
      throw ArgumentError('Unsupported codec: $codec');
  }
}
