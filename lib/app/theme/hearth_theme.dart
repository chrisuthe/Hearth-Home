import 'package:flutter/material.dart';
import 'hearth_colors.dart';

/// The app [ThemeData], with every color taken from [colors].
ThemeData buildHearthTheme(HearthColors colors) => ThemeData(
      brightness: ThemeData.estimateBrightnessForColor(colors.canvas),
      scaffoldBackgroundColor: colors.canvas,
      colorSchemeSeed: colors.accent,
      useMaterial3: true,
      fontFamily: 'Roboto',
      dialogTheme: DialogThemeData(backgroundColor: colors.raised),
      extensions: [colors],
    );
