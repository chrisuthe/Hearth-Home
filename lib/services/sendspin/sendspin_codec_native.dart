import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'flac_ffi.dart';
import 'sendspin_codec.dart';

/// Native FlacCodec using dart:ffi and libFLAC.
class FlacCodec implements SendspinCodec {
  final int bitDepth;
  final int channels;
  final int sampleRate;

  static final FlacFfi _ffi = FlacFfi();
  late final Pointer<Void> _decoder;

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
