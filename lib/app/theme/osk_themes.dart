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

/// Bright: white keys on the pale canvas, green accent.
const brightOskTheme = HearthOskTheme(
  background: Color(0xFFF6F8F2),
  keyFill: Color(0xFFFFFFFF),
  modifierFill: Color(0xFFE6ECE0),
  modifierActiveFill: Color(0xFFCFE3D6),
  accent: Color(0xFF2E7D55),
  keyLabel: Color(0xFF1E2922),
  modifierActiveLabel: Color(0xFF1E2922),
  keyHeight: 64,
);

/// Warm: cream keys on the paper canvas, rust accent.
const warmOskTheme = HearthOskTheme(
  background: Color(0xFFF2E7D7),
  keyFill: Color(0xFFFBF5EC),
  modifierFill: Color(0xFFE4D3BC),
  modifierActiveFill: Color(0xFFEBCDB6),
  accent: Color(0xFF9A4A1B),
  keyLabel: Color(0xFF3A2A1D),
  modifierActiveLabel: Color(0xFF3A2A1D),
  keyHeight: 64,
);
