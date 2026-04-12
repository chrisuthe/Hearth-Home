import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../utils/logger.dart';
import 'flac_ffi.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

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
  Int16List decode(Uint8List encodedData) {
    if (encodedData.isEmpty) return Int16List(0);

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
      Log.e('FlacCodec', 'decode error (code=$sampleCount)');
      return Int16List(0);
    }

    // FLAC output is Int32 — truncate to Int16 for the audio pipeline.
    final int32Samples = _outputBuf.asTypedList(sampleCount);
    final result = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      result[i] = int32Samples[i];
    }
    return result;
  }

  @override
  void reset() {
    _ffi.reset(_decoder);
  }

  @override
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
