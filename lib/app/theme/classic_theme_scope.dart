import 'package:flutter/material.dart';

import 'hearth_colors.dart';

/// Pins its subtree to [HearthColors.classic], whatever theme is active.
///
/// Home stays Classic in every theme. [HearthColors] is the only theme
/// extension, so replacing the extensions list drops nothing else.
///
/// With [pinned] false the scope passes the ambient theme through. It still
/// builds the same [Theme] node, so a subtree whose pin switches at runtime
/// keeps its element and state.
class ClassicThemeScope extends StatelessWidget {
  const ClassicThemeScope({super.key, required this.child, this.pinned = true});

  final Widget child;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: pinned ? base.copyWith(extensions: [HearthColors.classic]) : base,
      child: child,
    );
  }
}
