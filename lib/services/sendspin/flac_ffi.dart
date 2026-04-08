import 'dart:ffi';
import 'dart:io';

// Native function signatures (C types)
typedef _SendspinFlacNew = Pointer<Void> Function();
typedef _SendspinFlacDecode = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, IntPtr, Pointer<Int32>, IntPtr);
typedef _SendspinFlacReset = Void Function(Pointer<Void>);
typedef _SendspinFlacFree = Void Function(Pointer<Void>);

// Dart-side signatures
typedef _FlacNew = Pointer<Void> Function();
typedef _FlacDecode = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Int32>, int);
typedef _FlacReset = void Function(Pointer<Void>);
typedef _FlacFree = void Function(Pointer<Void>);

/// Thin wrapper around the sendspin_flac native library via dart:ffi.
class FlacFfi {
  late final _FlacNew _new;
  late final _FlacDecode _decode;
  late final _FlacReset _reset;
  late final _FlacFree _free;

  FlacFfi() {
    final lib = _loadLibrary();
    _new = lib.lookupFunction<_SendspinFlacNew, _FlacNew>('sendspin_flac_new');
    _decode = lib.lookupFunction<_SendspinFlacDecode, _FlacDecode>(
        'sendspin_flac_decode');
    _reset = lib.lookupFunction<_SendspinFlacReset, _FlacReset>(
        'sendspin_flac_reset');
    _free = lib.lookupFunction<_SendspinFlacFree, _FlacFree>(
        'sendspin_flac_free');
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('sendspin_flac.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libsendspin_flac.so');
    }
    throw UnsupportedError(
        'FLAC FFI not supported on ${Platform.operatingSystem}');
  }

  Pointer<Void> create() => _new();

  int decode(Pointer<Void> decoder, Pointer<Uint8> input, int inputLen,
      Pointer<Int32> output, int outputCapacity) {
    return _decode(decoder, input, inputLen, output, outputCapacity);
  }

  void reset(Pointer<Void> decoder) => _reset(decoder);
  void free(Pointer<Void> decoder) => _free(decoder);
}
