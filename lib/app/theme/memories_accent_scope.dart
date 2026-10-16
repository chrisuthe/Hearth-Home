import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hearth_theme_id.dart';
import '../../services/memories_accent.dart';
import '../../services/photo_providers.dart';
import '../page_visibility.dart';
import 'hearth_colors.dart';
import 'theme_providers.dart';

/// Fades the Memories accent with the memory photo.
///
/// Sits in `MaterialApp.builder`, above every route. Under Memories it
/// follows the photo whose crossfade has started ([displayedPhotoProvider]):
/// once that photo's seed is ready it fades the accent roles to it over the
/// photo's own 1500 ms. While the photo is hidden ([photoVisibleProvider]) it
/// only records the photo's accent, and fades to it once the photo shows.
///
/// The fade never rebuilds the app's [ThemeData]: each tick builds one
/// [HearthColors] into a [ValueNotifier], and only widgets that read
/// [HearthColors] under Memories depend on it. Under any other theme the host
/// is idle and nothing depends on it. It always builds the same scope, so a
/// theme change keeps the app's state.
class MemoriesAccentHost extends ConsumerStatefulWidget {
  const MemoriesAccentHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MemoriesAccentHost> createState() =>
      _MemoriesAccentHostState();
}

class _MemoriesAccentHostState extends ConsumerState<MemoriesAccentHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..addListener(_tick);

  final _colors = ValueNotifier<HearthColors>(HearthColors.memories);

  bool _active = false;

  /// The running fade goes from [_from] to [_to]; [_target] is the accent of
  /// the photo on screen, which [_to] catches up to once the photo shows.
  MemoriesAccent _from = kMemoriesFallback;
  MemoriesAccent _to = kMemoriesFallback;
  MemoriesAccent _target = kMemoriesFallback;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      hearthThemeIdProvider.select((id) => id == HearthThemeId.memories),
      (_, memories) => _setActive(memories),
      fireImmediately: true,
    );
    ref.listenManual(displayedPhotoProvider, (_, _) => _resolveTarget());
    ref.listenManual(memoriesSeedProvider, (_, _) => _resolveTarget());
    ref.listenManual(photoVisibleProvider, (_, visible) {
      if (visible) _fadeToTarget();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _colors.dispose();
    super.dispose();
  }

  void _setActive(bool active) {
    _active = active;
    _controller.stop();
    _from = _to = _target = kMemoriesFallback;
    _colors.value = HearthColors.memories;
    if (active) _resolveTarget();
  }

  /// Takes the target from the displayed photo's seed, once it is ready.
  void _resolveTarget() {
    if (!_active) return;
    final frame = ref.read(displayedPhotoProvider);
    if (frame == null) return;
    final seeded = ref.read(memoriesSeedProvider).valueOrNull;
    // Not ready yet, or still the previous photo's: its listener comes back.
    if (seeded == null || seeded.frame != frame) return;
    _target = deriveMemoriesAccent(seeded.seed);
    if (ref.read(photoVisibleProvider)) _fadeToTarget();
  }

  void _fadeToTarget() {
    if (!_active || _target == _to) return;
    _from = _current();
    _to = _target;
    _controller.forward(from: 0);
  }

  MemoriesAccent _current() {
    final t = _controller.value;
    if (t >= 1) return _to;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return (
      accent: mix(_from.accent, _to.accent),
      accentText: mix(_from.accentText, _to.accentText),
      accentFill: mix(_from.accentFill, _to.accentFill),
      onAccent: mix(_from.onAccent, _to.onAccent),
    );
  }

  void _tick() =>
      _colors.value = HearthColors.memories.withMemoriesAccent(_current());

  @override
  Widget build(BuildContext context) =>
      MemoriesAccentScope(notifier: _colors, child: widget.child);
}

/// Carries the Memories palette as it fades. Read it through
/// [HearthColors.of], which depends on it only under Memories.
class MemoriesAccentScope
    extends InheritedNotifier<ValueNotifier<HearthColors>> {
  const MemoriesAccentScope({
    super.key,
    required ValueNotifier<HearthColors> super.notifier,
    required super.child,
  });

  /// The faded palette, registering [context] to rebuild with it. With no
  /// scope above (a test, the app builder itself) it is the theme's own
  /// extension: Memories with the fallback accent.
  static HearthColors colorsOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MemoriesAccentScope>();
    return scope?.notifier?.value ??
        Theme.of(context).extension<HearthColors>() ??
        HearthColors.memories;
  }
}
