import 'dart:async';
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

// snd_pcm_prepare(pcm) -> int
typedef _SndPcmPrepareC = Int32 Function(Pointer<Void>);
typedef _SndPcmPrepareDart = int Function(Pointer<Void>);

// snd_pcm_delay(pcm, snd_pcm_sframes_t* delayp) -> int
typedef _SndPcmDelayC = Int32 Function(Pointer<Void>, Pointer<IntPtr>);
typedef _SndPcmDelayDart = int Function(Pointer<Void>, Pointer<IntPtr>);

// clock_gettime(clockid, struct timespec*) -> int
final class _Timespec extends Struct {
  @IntPtr()
  external int tvSec;
  @IntPtr()
  external int tvNsec;
}

typedef _ClockGettimeC = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGettimeDart = int Function(int, Pointer<_Timespec>);

const int _clockMonotonic = 1;

_ClockGettimeDart? _clockGettime;
Pointer<_Timespec>? _timespec;

/// `CLOCK_MONOTONIC` in microseconds.
///
/// The ALSA isolate and the main isolate each have their own [Stopwatch]
/// epoch, so a time taken in one means nothing in the other. This clock is
/// the same in both, which is what lets a delay measured in the isolate be
/// placed on the main isolate's timeline.
int monotonicUs() {
  final clockGettime = _clockGettime ??= DynamicLibrary.process()
      .lookupFunction<_ClockGettimeC, _ClockGettimeDart>('clock_gettime');
  final ts = _timespec ??= calloc<_Timespec>();
  clockGettime(_clockMonotonic, ts);
  return ts.ref.tvSec * 1000000 + ts.ref.tvNsec ~/ 1000;
}

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
  final String device;
  const _InitMsg(this.sampleRate, this.channels, this.bitDepth, this.device);
}

class _WriteMsg {
  final Uint8List data;
  const _WriteMsg(this.data);
}

/// Sent from isolate -> main after handling _InitMsg. [error] is null
/// on success; otherwise carries a human-readable failure reason so
/// upstream callers (and logs) can see WHY the sink didn't open.
class _InitAck {
  final String? error;
  const _InitAck({this.error});
  bool get ok => error == null;
}

class _VolumeMsg {
  final double volume;
  final bool muted;
  const _VolumeMsg(this.volume, this.muted);
}

/// Local-only duck attenuation. Multiplied with [_VolumeMsg.volume] inside
/// the isolate to compute the effective output level. Used by the voice
/// ducker to dim sendspin while a voice exchange is active without
/// reporting the volume change back to the Sendspin server (which would
/// also dim other rooms in a multi-room group).
class _DuckMsg {
  final double factor; // 0.0–1.0
  const _DuckMsg(this.factor);
}

enum _Cmd { stop, flush, dispose }

/// The output's progress, measured in the ALSA isolate straight after a
/// write: how many of the frames sent so far it has taken, how many were
/// queued in the device at that moment, and when that was.
class AlsaProgress {
  /// Frames taken from the main isolate since the sink was opened, whether
  /// they reached the device or were lost to a failed write.
  final int framesProcessed;

  /// `snd_pcm_delay`: frames queued between the last write and the speaker.
  final int delayFrames;

  /// When the two figures above were read, on [monotonicUs].
  final int monotonicUs;

  /// True when the queue was just emptied by a flush or an underrun
  /// recovery, so the output delay stepped instead of drifting.
  final bool discontinuity;

  const AlsaProgress({
    required this.framesProcessed,
    required this.delayFrames,
    required this.monotonicUs,
    required this.discontinuity,
  });
}

// ---------------------------------------------------------------------------
// ALSA Audio Sink (main isolate interface)
// ---------------------------------------------------------------------------

/// Audio output via ALSA, with blocking I/O in a background isolate.
///
/// Drop-in replacement for [SendspinAudioSink] on Linux systems that use
/// ALSA directly (e.g. Raspberry Pi with flutter-pi, no PulseAudio).
class AlsaAudioSink implements AudioSink {
  final String device;

  /// Called on the main isolate after each write the ALSA isolate
  /// completes, and after a flush.
  void Function(AlsaProgress progress)? onProgress;

  SendPort? _cmdPort;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  bool _initialized = false;

  /// Constructs a sink that opens the named ALSA device. The default
  /// `'default'` resolves to the PipeWire ALSA bridge on the kiosk
  /// (and to the system default elsewhere). PipeWire then routes to
  /// whatever WirePlumber has selected as the default sink (HDMI on
  /// the Pi 5).
  AlsaAudioSink({this.device = 'default'});

  @override
  Future<void> initialize({
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) async {
    await dispose();

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _isolate = await Isolate.spawn(
      _alsaIsolateEntry,
      receivePort.sendPort,
    );

    // The isolate sends its command SendPort first, then an _InitAck for the
    // _InitMsg, then an AlsaProgress after every write for as long as it
    // lives.
    final portReady = Completer<SendPort>();
    final initAck = Completer<_InitAck>();
    receivePort.listen((msg) {
      if (msg is SendPort) {
        portReady.complete(msg);
      } else if (msg is _InitAck) {
        initAck.complete(msg);
      } else if (msg is AlsaProgress) {
        onProgress?.call(msg);
      }
    });

    _cmdPort = await portReady.future;
    _cmdPort!.send(_InitMsg(sampleRate, channels, bitDepth, device));
    final ack = await initAck.future;
    if (!ack.ok) {
      Log.e('Sendspin',
          'ALSA sink init failed: device=$device — ${ack.error}');
      await dispose();
      throw StateError(
          'ALSA sink init failed: device=$device — ${ack.error}');
    }

    _initialized = true;
    Log.i('Sendspin', 'ALSA sink initialized: device=$device '
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

  /// Throws away everything queued in the device, so audio stops now
  /// instead of when the queue runs out. Writes sent before this are
  /// discarded with it; writes sent after it play normally.
  void flush() {
    if (!_initialized) return;
    _cmdPort?.send(_Cmd.flush);
  }

  /// Local-only attenuation (0.0–1.0). Independent of [setVolume]; doesn't
  /// round-trip to the Sendspin server. Used by the voice ducker.
  Future<void> setDuckFactor(double factor) async {
    _cmdPort?.send(_DuckMsg(factor.clamp(0.0, 1.0)));
  }

  @override
  Future<void> dispose() async {
    if (_isolate != null) {
      // The isolate drops the queued audio, closes the device and then exits
      // by itself. Killing it here would race that and leak the PCM handle,
      // which matters now that a sink is opened per stream.
      _cmdPort?.send(_Cmd.dispose);
      _isolate = null;
      _cmdPort = null;
      _receivePort?.close();
      _receivePort = null;
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
      // libasound isn't installed. Surface this so the main thread sees
      // the failure on the *next* _InitMsg attempt instead of hanging.
      cmdPort.listen((msg) {
        if (msg is _InitMsg) {
          mainPort.send(const _InitAck(
              error: 'libasound.so.2 / libasound.so not available'));
        }
      });
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
  final pcmPrepare = lib
      .lookupFunction<_SndPcmPrepareC, _SndPcmPrepareDart>('snd_pcm_prepare');
  final pcmDelay =
      lib.lookupFunction<_SndPcmDelayC, _SndPcmDelayDart>('snd_pcm_delay');

  Pointer<Void> pcm = nullptr;
  final delayPtr = calloc<IntPtr>();
  int framesProcessed = 0;
  int bytesPerFrame = 4; // 2 channels * 16-bit
  double volume = 1.0;
  double duckFactor = 1.0;
  bool muted = false;

  void cleanup() {
    if (pcm != nullptr) {
      pcmDrop(pcm);
      pcmClose(pcm);
      pcm = nullptr;
    }
  }

  // Tells the main isolate where the output stands. The delay and the time
  // are read back to back, so the pair stays true however long the message
  // takes to arrive.
  void reportProgress({required bool discontinuity}) {
    // An error here means the device is in underrun: nothing is queued.
    final queued = pcmDelay(pcm, delayPtr) < 0 ? 0 : delayPtr.value;
    mainPort.send(AlsaProgress(
      framesProcessed: framesProcessed,
      delayFrames: queued < 0 ? 0 : queued,
      monotonicUs: monotonicUs(),
      discontinuity: discontinuity,
    ));
  }

  cmdPort.listen((msg) {
    if (msg is _InitMsg) {
      cleanup();

      final pcmPtr = calloc<Pointer<Void>>();
      final namePtr = msg.device.toNativeUtf8();

      int err =
          pcmOpen(pcmPtr, namePtr, _sndPcmStreamPlayback, 0);
      calloc.free(namePtr);

      if (err < 0) {
        calloc.free(pcmPtr);
        mainPort.send(_InitAck(
            error: 'snd_pcm_open("${msg.device}") returned $err'));
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
        mainPort.send(_InitAck(error:
            'snd_pcm_set_params returned $err '
            '(${msg.sampleRate}Hz ${msg.channels}ch ${msg.bitDepth}bit)'));
        return;
      }

      bytesPerFrame = msg.channels * (msg.bitDepth ~/ 8);
      framesProcessed = 0;
      mainPort.send(const _InitAck());
    } else if (msg is _WriteMsg) {
      if (pcm == nullptr) return;

      final data = msg.data;
      if (data.isEmpty) return;

      // Effective software volume: server-reported user volume × local
      // duck factor. Server volume is what the user / multi-room group
      // expects; duck factor is a transient local-only attenuation set
      // by the voice ducker so other rooms aren't affected.
      final effective = volume * duckFactor;

      // Apply software volume (matching the PulseAudio C implementation).
      Uint8List processed;
      if (muted || effective <= 0.0) {
        processed = Uint8List(data.length); // zeros = silence
      } else if (effective < 1.0) {
        processed = Uint8List(data.length);
        final src = ByteData.sublistView(data);
        final dst = ByteData.sublistView(processed);
        final sampleCount = data.length ~/ 2;
        for (int i = 0; i < sampleCount; i++) {
          final sample = src.getInt16(i * 2, Endian.little);
          dst.setInt16(
              i * 2, (sample * effective).toInt(), Endian.little);
        }
      } else {
        processed = data;
      }

      final frames = processed.length ~/ bytesPerFrame;
      final nativeBuf = calloc<Uint8>(processed.length);
      nativeBuf.asTypedList(processed.length).setAll(0, processed);

      int written = 0;
      var recovered = false;
      while (written < frames) {
        final result = pcmWritei(
          pcm,
          (nativeBuf + written * bytesPerFrame).cast(),
          frames - written,
        );
        if (result < 0) {
          // Recover from underrun (-EPIPE) or suspend (-ESTRPIPE).
          pcmRecover(pcm, result, 1);
          recovered = true;
          break;
        }
        written += result;
      }

      calloc.free(nativeBuf);

      // Counted in full even when a failed write lost the tail: the main
      // isolate counts what it sent, and the two must not drift apart.
      framesProcessed += frames;
      reportProgress(discontinuity: recovered);
    } else if (msg is _VolumeMsg) {
      if (msg.volume >= 0) volume = msg.volume.clamp(0.0, 1.0);
      muted = msg.muted;
    } else if (msg is _DuckMsg) {
      duckFactor = msg.factor.clamp(0.0, 1.0);
    } else if (msg == _Cmd.stop) {
      if (pcm != nullptr) {
        pcmDrain(pcm);
      }
    } else if (msg == _Cmd.flush) {
      if (pcm != nullptr) {
        pcmDrop(pcm);
        pcmPrepare(pcm);
        reportProgress(discontinuity: true);
      }
    } else if (msg == _Cmd.dispose) {
      cleanup();
      calloc.free(delayPtr);
      cmdPort.close();
    }
  });
}
