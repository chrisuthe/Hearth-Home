import 'package:flutter/material.dart';

import '../../packages/hearth_osk/hearth_osk.dart';

/// Classic on-screen keyboard palette. Matches the indigo `0xFF646CFF`
/// accent and true-black backgrounds used elsewhere in the app.
const classicOskTheme = HearthOskTheme(
  background: Color(0xFF0A0A0A),
  keyFill: Color(0xFF1E1E1E),
  modifierFill: Color(0xFF262626),
  modifierActiveFill: Color(0xFF2F355E),
  accent: Color(0xFF646CFF),
  keyLabel: Colors.white,
  modifierActiveLabel: Colors.white,
  keyHeight: 64,
);
