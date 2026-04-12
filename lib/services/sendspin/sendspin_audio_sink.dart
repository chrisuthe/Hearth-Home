import 'package:flutter/services.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import '../../utils/logger.dart';

/// Platform channel interface to native audio output (WASAPI / PulseAudio).
class SendspinAudioSink implements AudioSink {
  static const _channel = MethodChannel('com.hearth/sendspin_audio');

  bool _initialized = false;

  SendspinAudioSink() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
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

  @override
  Future<void> start() async {
    if (!_initialized) return;
    await _channel.invokeMethod('start');
  }

  @override
  Future<void> stop() async {
    if (!_initialized) return;
    await _channel.invokeMethod('stop');
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setVolume', {'volume': volume});
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setMuted', {'muted': muted});
  }

  @override
  Future<void> writeSamples(Uint8List samples) async {
    if (!_initialized) return;
    await _channel.invokeMethod('writeSamples', {'data': samples});
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    if (_initialized) {
      await _channel.invokeMethod('dispose');
      _initialized = false;
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    Log.w('Sendspin', 'AudioSink: unknown native call ${call.method}');
    return null;
  }
}
