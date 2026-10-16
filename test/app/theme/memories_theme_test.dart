import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/page_visibility.dart';
import 'package:hearth/app/theme/classic_theme_scope.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/memories_accent_scope.dart';
import 'package:hearth/app/theme/memories_accent_scope_widget.dart';
import 'package:hearth/app/theme/theme_providers.dart';
import 'package:hearth/app/tokens/calendar_tokens.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/ambient/photo_carousel.dart' show PhotoFrame;
import 'package:hearth/services/immich_service.dart' show kCenterFocalPoint;
import 'package:hearth/services/memories_accent.dart';
import 'package:hearth/services/photo_providers.dart';

import '../../portrait/module_support.dart';

/// Stands in for the real page visibility, so a test can hide the photo.
final _visible = StateProvider<bool>((ref) => true);

const PhotoFrame _red = (path: '/photos/red.jpg', focal: kCenterFocalPoint);
const PhotoFrame _green = (path: '/photos/green.jpg', focal: kCenterFocalPoint);

/// Has no seed (no usable color), so it takes the fallback accent.
const PhotoFrame _grey = (path: '/photos/grey.jpg', focal: kCenterFocalPoint);
const _seeds = {
  '/photos/red.jpg': Color(0xFFD32F2F),
  '/photos/green.jpg': Color(0xFF2E7D32),
};

final _redAccent = deriveMemoriesAccent(_seeds[_red.path]);
final _greenAccent = deriveMemoriesAccent(_seeds[_green.path]);

// What the probes saw on their last build, and how often they built.
Color? _accent;
CalendarColors? _calendar;
Color? _classicAccent;
int _accentBuilds = 0;
int _plainBuilds = 0;
int _themeBuilds = 0;
int _classicBuilds = 0;

Future<ProviderContainer> _pump(WidgetTester tester,
    {String theme = 'memories'}) async {
  final c = ProviderContainer(overrides: [
    hubConfigProvider
        .overrideWith((ref) => MemoryConfigNotifier(HubConfig(theme: theme))),
    photoVisibleProvider.overrideWith((ref) => ref.watch(_visible)),
    memoriesSeedProvider.overrideWith((ref) async {
      final frame = ref.watch(displayedPhotoProvider);
      return frame == null ? null : (frame: frame, seed: _seeds[frame.path]);
    }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const _App()),
  );
  return c;
}

/// Shows [frame] and lets the seed resolve, so the fade has just started.
Future<void> _show(
    WidgetTester tester, ProviderContainer c, PhotoFrame frame) async {
  c.read(displayedPhotoProvider.notifier).state = frame;
  await tester.pump();
  await tester.pump();
}

/// Mirrors `HearthApp`: the theme from the provider, the host in the builder.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: buildHearthTheme(ref.watch(hearthColorsProvider)),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MemoriesAccentHost(child: child!),
      home: const Column(children: [
        _AccentProbe(),
        _PlainProbe(),
        _ThemeProbe(),
        ClassicThemeScope(child: _ClassicProbe()),
        _Stateful(),
      ]),
    );
  }
}

class _AccentProbe extends StatelessWidget {
  const _AccentProbe();

  @override
  Widget build(BuildContext context) {
    _accentBuilds++;
    _accent = context.hearthColors.accent;
    _calendar = CalendarColors.of(context);
    return const SizedBox.shrink();
  }
}

/// Reads no colors at all.
class _PlainProbe extends StatelessWidget {
  const _PlainProbe();

  @override
  Widget build(BuildContext context) {
    _plainBuilds++;
    return const SizedBox.shrink();
  }
}

/// Reads the Material theme but not HearthColors: it rebuilds only if the
/// app's ThemeData does.
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) {
    _themeBuilds++;
    Theme.of(context).colorScheme.primary;
    return const SizedBox.shrink();
  }
}

class _ClassicProbe extends StatelessWidget {
  const _ClassicProbe();

  @override
  Widget build(BuildContext context) {
    _classicBuilds++;
    _classicAccent = context.hearthColors.accent;
    return const SizedBox.shrink();
  }
}

class _Stateful extends StatefulWidget {
  const _Stateful();

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _StatefulState extends State<_Stateful> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() {
    _accent = null;
    _calendar = null;
    _classicAccent = null;
    _accentBuilds = _plainBuilds = _themeBuilds = _classicBuilds = 0;
  });

  testWidgets('accent fades with the photo', (tester) async {
    final c = await _pump(tester);
    await _show(tester, c, _red);

    await tester.pump(const Duration(milliseconds: 750));
    final fallback = kMemoriesFallback.accent;
    final red = _redAccent.accent;
    // Strictly between, channel by channel, wherever the two differ.
    for (final channel in <double Function(Color)>[
      (x) => x.r,
      (x) => x.g,
      (x) => x.b,
    ]) {
      final a = channel(fallback), b = channel(red), at = channel(_accent!);
      if (a == b) continue;
      expect(at, greaterThan(a < b ? a : b));
      expect(at, lessThan(a < b ? b : a));
    }
    expect(_accent, isNot(fallback));
    expect(_accent, isNot(red));

    await tester.pump(const Duration(milliseconds: 850));
    expect(_accent, red);
  });

  testWidgets('a fade publishes only colors that changed', (tester) async {
    final c = await _pump(tester);
    final notifier = tester
        .widget<MemoriesAccentScope>(find.byType(MemoriesAccentScope))
        .notifier!;
    var published = 0;
    notifier.addListener(() => published++);
    // The fade starts at t = 0, which is the palette already on screen.
    await _show(tester, c, _red);
    expect(published, 0);

    await tester.pump(const Duration(milliseconds: 100));
    expect(published, greaterThan(0));
  });

  testWidgets('holds while hidden', (tester) async {
    final c = await _pump(tester);
    c.read(_visible.notifier).state = false;
    await tester.pump();

    await _show(tester, c, _green);
    await tester.pump(const Duration(seconds: 2));
    expect(_accent, kMemoriesFallback.accent);

    c.read(_visible.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(_accent, _greenAccent.accent);
  });

  testWidgets('a new photo mid-fade continues from where the fade was',
      (tester) async {
    final c = await _pump(tester);
    await _show(tester, c, _red);
    await tester.pump(const Duration(milliseconds: 500));
    final midRed = _accent!;
    expect(midRed, isNot(kMemoriesFallback.accent));
    expect(midRed, isNot(_redAccent.accent));

    await _show(tester, c, _green);
    await tester.pump(const Duration(milliseconds: 16));
    for (final channel in <double Function(Color)>[
      (x) => x.r,
      (x) => x.g,
      (x) => x.b,
    ]) {
      expect(channel(_accent!), closeTo(channel(midRed), 0.03));
    }

    await tester.pump(const Duration(milliseconds: 1600));
    expect(_accent, _greenAccent.accent);
  });

  testWidgets('a colorless photo returns to the pre-fade palette',
      (tester) async {
    final c = await _pump(tester);
    final before = _calendar!;
    expect(_accent, kMemoriesFallback.accent);

    await _show(tester, c, _red);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(_accent, _redAccent.accent);

    await _show(tester, c, _grey);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(_accent, kMemoriesFallback.accent);
    expect(_calendar!.accentText, before.accentText);
    expect(_calendar!.todayTint, before.todayTint);
    expect(_calendar!.nowTint, before.nowTint);
    expect(_calendar!.emptyDisc, before.emptyDisc);
  });

  testWidgets('home stays classic under memories', (tester) async {
    final c = await _pump(tester);
    expect(_classicAccent, HearthColors.classic.accent);

    await _show(tester, c, _red);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(_classicAccent, HearthColors.classic.accent);
    }
    expect(_accent, _redAccent.accent);
    // Pinned Classic never depends on the scope, so the fade never rebuilds it.
    expect(_classicBuilds, 1);
  });

  testWidgets('only scope dependents rebuild', (tester) async {
    final c = await _pump(tester);
    expect(_plainBuilds, 1);
    expect(_themeBuilds, 1);
    final before = _accentBuilds;

    await _show(tester, c, _red);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_accent, _redAccent.accent);
    expect(_accentBuilds, greaterThan(before + 5));
    expect(_plainBuilds, 1);
    // The app's ThemeData is not rebuilt per frame either.
    expect(_themeBuilds, 1);
  });

  testWidgets('calendar tints follow memories accent', (tester) async {
    final c = await _pump(tester);
    await _show(tester, c, _red);
    await tester.pump(const Duration(milliseconds: 1600));

    expect(_accent, _redAccent.accent);
    expect(_calendar!.accent, _accent);
    expect(_calendar!.accentText, _redAccent.accentText);
    expect(_calendar!.todayTint, _accent!.withValues(alpha: 0.13));
    expect(_calendar!.nowTint, _accent!.withValues(alpha: 0.30));
    expect(_calendar!.emptyDisc, _accent!.withValues(alpha: 0.14));
  });

  testWidgets('theme switch mid-fade', (tester) async {
    final c = await _pump(tester);
    await _show(tester, c, _red);
    await tester.pump(const Duration(milliseconds: 500));

    await c
        .read(hubConfigProvider.notifier)
        .update((cfg) => cfg.copyWith(theme: 'classic'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_accent, HearthColors.classic.accent);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('no photo → fallback', (tester) async {
    await _pump(tester);
    await tester.pump();
    expect(_accent, kMemoriesFallback.accent);
  });

  testWidgets('switching into and out of memories keeps the app state',
      (tester) async {
    final c = await _pump(tester, theme: 'classic');
    final state = tester.state(find.byType(_Stateful));

    Future<void> setTheme(String theme) async {
      await c
          .read(hubConfigProvider.notifier)
          .update((cfg) => cfg.copyWith(theme: theme));
      await tester.pumpAndSettle();
    }

    await setTheme('memories');
    expect(identical(tester.state(find.byType(_Stateful)), state), isTrue);
    await setTheme('classic');
    expect(identical(tester.state(find.byType(_Stateful)), state), isTrue);
  });
}
