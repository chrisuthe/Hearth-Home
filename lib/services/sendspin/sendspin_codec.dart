// Hearth codec factory with FLAC support via platform-conditional export.
//
// Re-exports the library's base types and adds the platform-specific
// createCodec factory that includes FLAC (native) or a stub (web).
export 'package:sendspin_dart/sendspin_dart.dart'
    show SendspinCodec, PcmCodec;

export 'sendspin_codec_native.dart'
    if (dart.library.js_interop) 'sendspin_codec_stub.dart';
