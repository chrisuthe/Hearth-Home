import 'package:flutter/material.dart';

import 'hearth_colors.dart';

/// Pins its subtree to [HearthColors.classic], whatever theme is active.
///
/// Home stays Classic in every theme. [HearthColors] is the only theme
/// extension, so replacing the extensions list drops nothing else.
class ClassicThemeScope extends StatelessWidget {
  const ClassicThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(extensions: [HearthColors.classic]),
        child: child,
      );
}
