import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

/// Where the kiosk keeps its Sendspin secrets.
///
/// They live in their own files beside `hub_config.json`, not inside it: the
/// config is readable through the web portal and its API, and neither the
/// device's private key nor its pairing credentials should be.
Future<String> _defaultDirectory() async =>
    (await getApplicationSupportDirectory()).path;

/// Restricts [file] to its owner. A no-op where `chmod` does not exist.
Future<void> _ownerOnly(File file) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  try {
    await Process.run('chmod', ['600', file.path]);
  } catch (_) {}
}

/// The device's Sendspin identity: the private half of the Curve25519 key
/// whose public half is its `client_id`. Losing this file makes every server
/// see the kiosk as a new player.
class FileSendspinIdentityStore implements SendspinIdentityStore {
  static const fileName = 'sendspin_identity.key';

  final Future<String> Function() _directory;

  FileSendspinIdentityStore({Future<String> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  Future<File> _file() async => File('${await _directory()}/$fileName');

  @override
  Future<Uint8List?> loadPrivateKey() async {
    final file = await _file();
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> savePrivateKey(Uint8List privateKey) async {
    final file = await _file();
    await file.writeAsBytes(privateKey, flush: true);
    await _ownerOnly(file);
  }
}

/// The device's pairing PSK and the record it holds for each paired server.
class FileSendspinPairingStore implements SendspinPairingStore {
  static const fileName = 'sendspin_pairing.json';

  final Future<String> Function() _directory;

  FileSendspinPairingStore({Future<String> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  Future<File> _file() async => File('${await _directory()}/$fileName');

  @override
  Future<SendspinPairingData?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return SendspinPairingData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>);
  }

  @override
  Future<void> save(SendspinPairingData data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data.toJson()), flush: true);
    await _ownerOnly(file);
  }
}
