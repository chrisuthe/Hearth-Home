import 'package:flutter/material.dart';

import 'hearth_colors.dart';

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
