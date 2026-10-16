import 'package:flutter/material.dart';

import 'hearth_colors.dart';
import 'hearth_theme.dart';

/// Pins its subtree to the Classic theme, whatever theme is active.
///
/// Home stays Classic in every theme. The scope provides the whole Classic
/// [ThemeData], not just [HearthColors], so text, icons and spinners that
/// take their color from the theme stay light on the photo.
///
/// Text with no color inherits [DefaultTextStyle], which the root Scaffold's
/// Material set from the app theme. The scope re-merges the body text style
/// of the theme it provides. A transparent Material would do that too, but it
/// would also take over ink splashes from the screen's own Material.
///
/// With [pinned] false the scope passes the ambient theme through. It still
/// builds the same widgets, so a subtree whose pin switches at runtime keeps
/// its element and state.
class ClassicThemeScope extends StatelessWidget {
  const ClassicThemeScope({super.key, required this.child, this.pinned = true});

  final Widget child;
  final bool pinned;

  static final _classicTheme = buildHearthTheme(HearthColors.classic);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: pinned ? _classicTheme : Theme.of(context),
      child: Builder(
        builder: (context) => DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium,
          child: child,
        ),
      ),
    );
  }
}
