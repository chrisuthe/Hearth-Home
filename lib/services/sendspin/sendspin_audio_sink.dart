import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel interface to native audio output.
///
/// Implementations: WASAPI (Windows), PulseAudio (Linux/Pi).
/// Audio is pull-based: native side requests samples via a callback,
/// Dart responds with PCM data from the jitter buffer.
class SendspinAudioSink {
  static const _channel = MethodChannel('com.hearth/sendspin_audio');

  /// Callback invoked when native audio thread needs more samples.
  void Function(int frameCount)? onSamplesRequested;

  bool _initialized = false;

  SendspinAudioSink() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> initialize({
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) async {
    await _channel.invokeMethod('initialize', {
      'sampleRate': sampleRate,
      'channels': channels,
      'bitDepth': bitDepth,
    });
    _initialized = true;
  }

  Future<void> start() async {
    if (!_initialized) return;
    await _channel.invokeMethod('start');
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _channel.invokeMethod('stop');
  }

  Future<void> setVolume(double volume) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setVolume', {'volume': volume});
  }

  Future<void> setMuted(bool muted) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setMuted', {'muted': muted});
  }

  Future<void> writeSamples(Uint8List samples) async {
    if (!_initialized) return;
    await _channel.invokeMethod('writeSamples', {'data': samples});
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    if (_initialized) {
      await _channel.invokeMethod('dispose');
      _initialized = false;
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSamplesRequested':
        final frameCount = call.arguments['frameCount'] as int;
        onSamplesRequested?.call(frameCount);
        return null;
      default:
        debugPrint('SendspinAudioSink: unknown native call ${call.method}');
        return null;
    }
  }
}
