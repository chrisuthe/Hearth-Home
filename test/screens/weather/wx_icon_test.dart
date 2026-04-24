import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/weather/icons/wx_icon.dart';
import 'package:hearth/screens/weather/wx_cond.dart';

void main() {
  testWidgets('every WxCond renders without throwing', (tester) async {
    for (final cond in WxCond.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: WxIcon(cond: cond, size: 64))),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'failed to paint $cond');
    }
  });

  testWidgets('partly-cloudy night variant renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WxIcon(cond: WxCond.partlyCloudy, night: true)),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
