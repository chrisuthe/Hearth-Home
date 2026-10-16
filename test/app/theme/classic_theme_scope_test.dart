import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/classic_theme_scope.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/tokens/calendar_tokens.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/home/home_screen.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/timer_service.dart';
import 'package:hearth/services/weather_service.dart';

import '../../portrait/portrait_fixtures.dart';

void main() {
  const red = Color(0xFFFF0000);
  final themed = buildHearthTheme(HearthColors.classic.copyWith(accent: red));

  testWidgets('the scope pins its subtree to Classic', (tester) async {
    late BuildContext outside;
    late BuildContext inside;
    await tester.pumpWidget(MaterialApp(
      theme: themed,
      home: Builder(builder: (c) {
        outside = c;
        return ClassicThemeScope(
          child: Builder(builder: (c) {
            inside = c;
            return const SizedBox.shrink();
          }),
        );
      }),
    ));
    expect(outside.hearthColors.accent, red);
    expect(inside.hearthColors, HearthColors.classic);
    expect(CalendarColors.of(inside), CalendarColors.classic);
  });

  Future<void> pumpHome(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hubConfigProvider
            .overrideWith((ref) => MemoryConfigNotifier(const HubConfig())),
        timerServiceProvider.overrideWith((ref) => TimerService()),
        weatherStateProvider.overrideWith((ref) => const Stream.empty()),
        maAllPlayersProvider.overrideWith((ref) => Stream.value(const {})),
      ],
      // The Scaffold sets the app theme's text defaults, as HubShell's does.
      child: MaterialApp(
          theme: theme, home: const Scaffold(body: HomeScreen())),
    ));
    await tester.pump();
  }

  testWidgets('the pinned scope is a dark theme under Bright', (tester) async {
    late BuildContext inside;
    await tester.pumpWidget(MaterialApp(
      theme: buildHearthTheme(HearthColors.bright),
      home: ClassicThemeScope(
        child: Builder(builder: (c) {
          inside = c;
          return const SizedBox.shrink();
        }),
      ),
    ));
    expect(Theme.of(inside).brightness, Brightness.dark);
  });

  testWidgets('the Home clock is light on the photo under Bright',
      (tester) async {
    await pumpHome(tester, buildHearthTheme(HearthColors.bright));
    final clock = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.fontSize == 96 &&
            w.style?.fontWeight == FontWeight.w100);
    expect(clock, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: clock, matching: find.byType(RichText)));
    final color = paragraph.text.style!.color!;
    expect(color.computeLuminance(), greaterThan(0.7));
    final classic = Theme.of(tester.element(clock)).textTheme.bodyMedium!;
    expect(color, classic.color);
  });

  testWidgets('HomeScreen builds inside a ClassicThemeScope', (tester) async {
    await pumpHome(tester, themed);
    expect(
      find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(ClassicThemeScope),
      ),
      findsOneWidget,
    );
    final homeContext = tester.element(find.byType(HomeScreen));
    expect(homeContext.hearthColors.accent, red);
    final inner = tester.element(find.byType(Stack).first);
    expect(inner.hearthColors, HearthColors.classic);
  });
}
