import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/app.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';

void main() {
  test("classic reproduces today's literals", () {
    expect(HearthColors.classic.raised, kDialogBackground);
    expect(HearthColors.classic.accent, const Color(0xFF646CFF));
    expect(HearthColors.classic.textMuted,
        Colors.white.withValues(alpha: 0.66));
    expect(HearthColors.classic.photoTint(TintStrength.light),
        Colors.black.withValues(alpha: 0.75));
    expect(HearthColors.classic.photoTint(TintStrength.medium),
        Colors.black.withValues(alpha: 0.75));
    expect(HearthColors.classic.photoTint(TintStrength.heavy),
        Colors.black.withValues(alpha: 0.85));
  });

  test('inkAt and canvasAt apply alpha', () {
    expect(HearthColors.classic.inkAt(0.5),
        Colors.white.withValues(alpha: 0.5));
    expect(HearthColors.classic.canvasAt(0.5),
        Colors.black.withValues(alpha: 0.5));
  });

  test('buildHearthTheme(classic) matches the shipped theme', () {
    final theme = buildHearthTheme(HearthColors.classic);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.dialogTheme.backgroundColor, const Color(0xFF1E1E1E));
    expect(theme.extension<HearthColors>(), HearthColors.classic);
  });

  testWidgets('of() falls back to classic without the extension',
      (tester) async {
    late HearthColors found;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(builder: (context) {
        found = context.hearthColors;
        return const SizedBox.shrink();
      }),
    ));
    expect(found, HearthColors.classic);
  });

  testWidgets('dialogs resolve the extension', (tester) async {
    Color? raised;
    await tester.pumpWidget(MaterialApp(
      theme: buildHearthTheme(HearthColors.classic),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) {
              raised = dialogContext.hearthColors.raised;
              return const AlertDialog(content: Text('hi'));
            },
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(raised, const Color(0xFF1E1E1E));
  });

  test('calendar palette rides on HearthColors', () {
    expect(HearthColors.classic.calendar.accent, const Color(0xFF646CFF));
    expect(HearthColors.classic.calendar.textMuted, const Color(0xC7FFFFFF));
  });
}
