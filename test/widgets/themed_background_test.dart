import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/widgets/themed_background.dart';

Color? _materialColor(WidgetTester t) => t
    .widget<Material>(
        find.descendant(
            of: find.byType(ThemedBackground), matching: find.byType(Material)))
    .color;

Future<void> _pump(WidgetTester t, Widget w) =>
    t.pumpWidget(MaterialApp(home: w));

void main() {
  testWidgets('screen paints canvas', (t) async {
    await _pump(t, const ThemedBackground.screen(child: SizedBox()));
    expect(_materialColor(t), Colors.black);
  });

  for (final (s, a) in [
    (TintStrength.light, 0.75),
    (TintStrength.medium, 0.75),
    (TintStrength.heavy, 0.85),
  ]) {
    testWidgets('photo ${s.name} paints black at $a', (t) async {
      await _pump(t, ThemedBackground.photo(strength: s, child: const SizedBox()));
      expect(_materialColor(t), Colors.black.withValues(alpha: a));
    });
  }
}
