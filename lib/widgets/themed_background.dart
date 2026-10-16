import 'package:flutter/material.dart';

import '../app/theme/hearth_colors.dart';

/// The background behind a screen.
///
/// [ThemedBackground.screen] is the theme's page background;
/// [ThemedBackground.photo] is a scrim that lets the photo behind the kiosk
/// show through. Both root on a [Material] so ink splashes below them work.
class ThemedBackground extends StatelessWidget {
  const ThemedBackground.screen({super.key, required this.child})
      : strength = null;

  const ThemedBackground.photo({
    super.key,
    required TintStrength this.strength,
    required this.child,
  });

  final TintStrength? strength;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final s = strength;
    return Material(color: s == null ? c.canvas : c.photoTint(s), child: child);
  }
}
