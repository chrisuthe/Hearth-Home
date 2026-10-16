import 'package:flutter/material.dart';
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

  testWidgets('HomeScreen builds inside a ClassicThemeScope', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hubConfigProvider
            .overrideWith((ref) => MemoryConfigNotifier(const HubConfig())),
        timerServiceProvider.overrideWith((ref) => TimerService()),
        weatherStateProvider.overrideWith((ref) => const Stream.empty()),
        maAllPlayersProvider.overrideWith((ref) => Stream.value(const {})),
      ],
      child: MaterialApp(theme: themed, home: const HomeScreen()),
    ));
    await tester.pump();
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
