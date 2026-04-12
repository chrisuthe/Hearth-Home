import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/utils/alsa_utils.dart';

void main() {
  group('AlsaUtils', () {
    test('setMicMuted completes without error on non-Linux', () async {
      if (!Platform.isLinux) {
        await setMicMuted(true);
        await setMicMuted(false);
      }
    });
  });
}
