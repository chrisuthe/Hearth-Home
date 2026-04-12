import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:sendspin_dart/sendspin_dart.dart';

import '../../utils/logger.dart';

// ---------------------------------------------------------------------------
// ALSA C function signatures
// ---------------------------------------------------------------------------

// snd_pcm_open(snd_pcm_t**, name, stream, mode) -> int
typedef _SndPcmOpenC = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Utf8>, Int32, Int32);
typedef _SndPcmOpenDart = int Function(
    Pointer<Pointer<Void>>, Pointer<Utf8>, int, int);

// snd_pcm_set_params(pcm, format, access, channels, rate, soft_resample, latency_us) -> int
typedef _SndPcmSetParamsC = Int32 Function(
    Pointer<Void>, Int32, Int32, Uint32, Uint32, Int32, Uint32);
typedef _SndPcmSetParamsDart = int Function(
    Pointer<Void>, int, int, int, int, int, int);

// snd_pcm_writei(pcm, buffer, frames) -> snd_pcm_sframes_t (long)
typedef _SndPcmWriteiC = IntPtr Function(
    Pointer<Void>, Pointer<Void>, IntPtr);
typedef _SndPcmWriteiDart = int Function(Pointer<Void>, Pointer<Void>, int);

// snd_pcm_recover(pcm, err, silent) -> int
typedef _SndPcmRecoverC = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _SndPcmRecoverDart = int Function(Pointer<Void>, int, int);

// snd_pcm_drain(pcm) -> int
typedef _SndPcmDrainC = Int32 Function(Pointer<Void>);
typedef _SndPcmDrainDart = int Function(Pointer<Void>);

// snd_pcm_drop(pcm) -> int
typedef _SndPcmDropC = Int32 Function(Pointer<Void>);
typedef _SndPcmDropDart = int Function(Pointer<Void>);

// snd_pcm_close(pcm) -> int
typedef _SndPcmCloseC = Int32 Function(Pointer<Void>);
typedef _SndPcmCloseDart = int Function(Pointer<Void>);

// ALSA constants
const int _sndPcmStreamPlayback = 0;
const int _sndPcmFormatS16Le = 2;
const int _sndPcmFormatS24Le = 6;
const int _sndPcmFormatS32Le = 10;
const int _sndPcmAccessRwInterleaved = 3;

// ---------------------------------------------------------------------------
// Messages passed between main isolate and ALSA isolate
// ---------------------------------------------------------------------------

class _InitMsg {
  final int sampleRate;
  final int channels;
  final int bitDepth;
  const _InitMsg(this.sampleRate, this.channels, this.bitDepth);
}

class _WriteMsg {
  final Uint8List data;
  const _WriteMsg(this.data);
}

class _VolumeMsg {
  final double volume;
  final bool muted;
  const _VolumeMsg(this.volume, this.muted);
}

enum _Cmd { stop, dispose }

// ---------------------------------------------------------------------------
// ALSA Audio Sink (main isolate interface)
// ---------------------------------------------------------------------------

/// Audio output via ALSA, with blocking I/O in a background isolate.
///
/// Drop-in replacement for [SendspinAudioSink] on Linux systems that use
/// ALSA directly (e.g. Raspberry Pi with flutter-pi, no PulseAudio).
class AlsaAudioSink implements AudioSink {
  SendPort? _cmdPort;
  Isolate? _isolate;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) async {
    await dispose();

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _alsaIsolateEntry,
      receivePort.sendPort,
    );

    // First message from isolate is its command port.
    _cmdPort = await receivePort.first as SendPort;

    _cmdPort!.send(_InitMsg(sampleRate, channels, bitDepth));
    _initialized = true;
    Log.i('Sendspin', 'ALSA sink initialized: '
        '${sampleRate}Hz ${channels}ch ${bitDepth}bit');
  }

  @override
  Future<void> start() async {
    // ALSA starts on first write; nothing to do.
  }

  @override
  Future<void> stop() async {
    if (!_initialized) return;
    _cmdPort?.send(_Cmd.stop);
  }

  @override
  Future<void> writeSamples(Uint8List samples) async {
    if (!_initialized || _cmdPort == null) return;
    _cmdPort!.send(_WriteMsg(samples));
  }

  @override
  Future<void> setVolume(double volume) async {
    _cmdPort?.send(_VolumeMsg(volume, false));
  }

  @override
  Future<void> setMuted(bool muted) async {
    _cmdPort?.send(_VolumeMsg(-1, muted));
  }

  @override
  Future<void> dispose() async {
    if (_isolate != null) {
      _cmdPort?.send(_Cmd.dispose);
      _isolate!.kill(priority: Isolate.beforeNextEvent);
      _isolate = null;
      _cmdPort = null;
      _initialized = false;
    }
  }
}

// ---------------------------------------------------------------------------
// ALSA isolate (runs blocking I/O off the main thread)
// ---------------------------------------------------------------------------

void _alsaIsolateEntry(SendPort mainPort) {
  final cmdPort = ReceivePort();
  mainPort.send(cmdPort.sendPort);

  late final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open('libasound.so.2');
  } catch (_) {
    try {
      lib = DynamicLibrary.open('libasound.so');
    } catch (e) {
      // Can't log from isolate easily, just exit.
      return;
    }
  }

  final pcmOpen =
      lib.lookupFunction<_SndPcmOpenC, _SndPcmOpenDart>('snd_pcm_open');
  final pcmSetParams =
      lib.lookupFunction<_SndPcmSetParamsC, _SndPcmSetParamsDart>(
          'snd_pcm_set_params');
  final pcmWritei =
      lib.lookupFunction<_SndPcmWriteiC, _SndPcmWriteiDart>('snd_pcm_writei');
  final pcmRecover =
      lib.lookupFunction<_SndPcmRecoverC, _SndPcmRecoverDart>(
          'snd_pcm_recover');
  final pcmDrain =
      lib.lookupFunction<_SndPcmDrainC, _SndPcmDrainDart>('snd_pcm_drain');
  final pcmDrop =
      lib.lookupFunction<_SndPcmDropC, _SndPcmDropDart>('snd_pcm_drop');
  final pcmClose =
      lib.lookupFunction<_SndPcmCloseC, _SndPcmCloseDart>('snd_pcm_close');

  Pointer<Void> pcm = nullptr;
  int bytesPerFrame = 4; // 2 channels * 16-bit
  double volume = 1.0;
  bool muted = false;

  void cleanup() {
    if (pcm != nullptr) {
      pcmDrop(pcm);
      pcmClose(pcm);
      pcm = nullptr;
    }
  }

  cmdPort.listen((msg) {
    if (msg is _InitMsg) {
      cleanup();

      final pcmPtr = calloc<Pointer<Void>>();
      final namePtr = 'default'.toNativeUtf8();

      int err =
          pcmOpen(pcmPtr, namePtr, _sndPcmStreamPlayback, 0);
      calloc.free(namePtr);

      if (err < 0) {
        calloc.free(pcmPtr);
        return;
      }
      pcm = pcmPtr.value;
      calloc.free(pcmPtr);

      int format;
      switch (msg.bitDepth) {
        case 24:
          format = _sndPcmFormatS24Le;
        case 32:
          format = _sndPcmFormatS32Le;
        default:
          format = _sndPcmFormatS16Le;
      }

      // 200ms latency target matches the WASAPI/PulseAudio implementations.
      err = pcmSetParams(
        pcm,
        format,
        _sndPcmAccessRwInterleaved,
        msg.channels,
        msg.sampleRate,
        1, // soft resample
        200000, // latency in µs
      );

      if (err < 0) {
        pcmClose(pcm);
        pcm = nullptr;
        return;
      }

      bytesPerFrame = msg.channels * (msg.bitDepth ~/ 8);
    } else if (msg is _WriteMsg) {
      if (pcm == nullptr) return;

      final data = msg.data;
      if (data.isEmpty) return;

      // Apply software volume (matching the PulseAudio C implementation).
      Uint8List processed;
      if (muted || volume <= 0.0) {
        processed = Uint8List(data.length); // zeros = silence
      } else if (volume < 1.0) {
        processed = Uint8List(data.length);
        final src = ByteData.sublistView(data);
        final dst = ByteData.sublistView(processed);
        final sampleCount = data.length ~/ 2;
        for (int i = 0; i < sampleCount; i++) {
          final sample = src.getInt16(i * 2, Endian.little);
          dst.setInt16(
              i * 2, (sample * volume).toInt(), Endian.little);
        }
      } else {
        processed = data;
      }

      final frames = processed.length ~/ bytesPerFrame;
      final nativeBuf = calloc<Uint8>(processed.length);
      nativeBuf.asTypedList(processed.length).setAll(0, processed);

      int written = 0;
      while (written < frames) {
        final result = pcmWritei(
          pcm,
          (nativeBuf + written * bytesPerFrame).cast(),
          frames - written,
        );
        if (result < 0) {
          // Recover from underrun (-EPIPE) or suspend (-ESTRPIPE).
          pcmRecover(pcm, result, 1);
          break;
        }
        written += result;
      }

      calloc.free(nativeBuf);
    } else if (msg is _VolumeMsg) {
      if (msg.volume >= 0) volume = msg.volume.clamp(0.0, 1.0);
      muted = msg.muted;
    } else if (msg == _Cmd.stop) {
      if (pcm != nullptr) {
        pcmDrain(pcm);
      }
    } else if (msg == _Cmd.dispose) {
      cleanup();
      cmdPort.close();
    }
  });
}
