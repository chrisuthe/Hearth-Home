import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_stores.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

void main() {
  late Directory dir;
  Future<String> path() async => dir.path;

  setUp(() => dir = Directory.systemTemp.createTempSync('sendspin_stores'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('FileSendspinIdentityStore', () {
    test('has no key before one is saved', () async {
      expect(
          await FileSendspinIdentityStore(directory: path).loadPrivateKey(),
          isNull);
    });

    test('a new store instance reads back the saved key', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      await FileSendspinIdentityStore(directory: path).savePrivateKey(key);
      expect(
          await FileSendspinIdentityStore(directory: path).loadPrivateKey(),
          key);
    });

    test('gives the device one identity across loads', () async {
      final first = await SendspinIdentity.loadOrCreate(
          FileSendspinIdentityStore(directory: path));
      final second = await SendspinIdentity.loadOrCreate(
          FileSendspinIdentityStore(directory: path));
      expect(second.clientId, first.clientId);
    });
  });

  group('FileSendspinPairingStore', () {
    test('has no data before any is saved', () async {
      expect(await FileSendspinPairingStore(directory: path).load(), isNull);
    });

    test('keeps the pairing PSK across loads', () async {
      final first =
          await SendspinPairing.load(FileSendspinPairingStore(directory: path));
      final second =
          await SendspinPairing.load(FileSendspinPairingStore(directory: path));
      expect(second.pairingPsk, first.pairingPsk);
    });

    test('keeps the secrets out of hub_config.json', () async {
      await SendspinPairing.load(FileSendspinPairingStore(directory: path));
      await SendspinIdentity.loadOrCreate(
          FileSendspinIdentityStore(directory: path));
      final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
      expect(names, {
        FileSendspinIdentityStore.fileName,
        FileSendspinPairingStore.fileName,
      });
    });
  });
}
