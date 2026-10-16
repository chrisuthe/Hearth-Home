import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/backup/sendspin_secret_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/sendspin');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Object? reply;

  setUp(() {
    calls = [];
    reply = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('read returns the native files', () async {
    reply = {'identity': 'AQID', 'trust.json': 'e30='};
    final files = AndroidSendspinSecretFiles(methods: channel);
    expect(await files.read(), {'identity': 'AQID', 'trust.json': 'e30='});
    expect(calls.single.method, 'exportSecrets');
  });

  test('a null native reply reads as no files', () async {
    expect(await AndroidSendspinSecretFiles(methods: channel).read(), isEmpty);
  });

  test('write hands the files to the native side', () async {
    await AndroidSendspinSecretFiles(methods: channel)
        .write({'identity': 'AQID'});
    expect(calls.single.method, 'importSecrets');
    expect(calls.single.arguments, {'identity': 'AQID'});
  });
}
