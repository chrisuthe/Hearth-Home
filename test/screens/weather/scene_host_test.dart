import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/weather/scenes/scene_host.dart';
import 'package:hearth/screens/weather/wx_cond.dart';

void main() {
  for (final cond in WxCond.values) {
    testWidgets('SceneHost renders $cond without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SceneHost(cond: cond)),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'scene threw for $cond');
    });
  }
}
