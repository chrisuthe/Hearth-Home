import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../sendspin/sendspin_stores.dart';

/// The kiosk's Sendspin secret files, as a backup carries them: file name to
/// the base64 of its bytes.
///
/// They are kept opaque, because the Pi and Android store them in different
/// formats and a restore only ever puts them back on the platform that wrote
/// them.
abstract class SendspinSecretFiles {
  /// Every secret file that exists. Empty when Sendspin never ran.
  Future<Map<String, String>> read();

  /// Writes the given files, first copying each one it replaces to
  /// `<name>.pre-restore`. Names it does not own are ignored, and files not
  /// in [files] are left alone.
  Future<void> write(Map<String, String> files);
}

/// The Pi and desktop files, written by [FileSendspinIdentityStore] and
/// [FileSendspinPairingStore] beside `hub_config.json`.
class FileSendspinSecretFiles implements SendspinSecretFiles {
  static const names = [
    FileSendspinIdentityStore.fileName,
    FileSendspinPairingStore.fileName,
  ];

  final Future<String> Function() _directory;

  FileSendspinSecretFiles({Future<String> Function()? directory})
      : _directory = directory ?? _supportDirectory;

  static Future<String> _supportDirectory() async =>
      (await getApplicationSupportDirectory()).path;

  @override
  Future<Map<String, String>> read() async {
    final dir = await _directory();
    return {
      for (final name in names)
        if (File('$dir/$name').existsSync())
          name: base64Encode(await File('$dir/$name').readAsBytes()),
    };
  }

  @override
  Future<void> write(Map<String, String> files) async {
    final dir = await _directory();
    for (final name in names) {
      final encoded = files[name];
      if (encoded == null) continue;
      final file = File('$dir/$name');
      if (await file.exists()) await file.copy('${file.path}.pre-restore');
      await file.writeAsBytes(base64Decode(encoded), flush: true);
      // Owner-only, as the stores leave them.
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          await Process.run('chmod', ['600', file.path]);
        } catch (_) {}
      }
    }
  }
}

/// Android's files, which `SendspinSecrets.kt` keeps under `filesDir/sendspin/`
/// and reads and writes natively over `com.hearth/sendspin`.
class AndroidSendspinSecretFiles implements SendspinSecretFiles {
  final MethodChannel _methods;

  AndroidSendspinSecretFiles({MethodChannel? methods})
      : _methods = methods ?? const MethodChannel('com.hearth/sendspin');

  @override
  Future<Map<String, String>> read() async =>
      (await _methods.invokeMapMethod<String, String>('exportSecrets')) ??
      const {};

  @override
  Future<void> write(Map<String, String> files) =>
      _methods.invokeMethod<void>('importSecrets', files);
}
