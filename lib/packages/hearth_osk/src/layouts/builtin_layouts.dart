import 'package:flutter/material.dart';

import 'keyboard_layout.dart';

/// Built-in layouts that ship with the package. Host apps can also construct
/// their own [KeyboardLayout] instances for specialized input surfaces.
class BuiltinLayouts {
  BuiltinLayouts._();

  static const String alpha = 'alpha';
  static const String symbols = 'symbols';
  static const String numeric = 'numeric';
  static const String url = 'url';

  /// Standard QWERTY alpha layout with number row, shift, symbols toggle,
  /// space, backspace, enter, and done. Designed to be the default.
  static const KeyboardLayout alphaLayout = KeyboardLayout(
    id: alpha,
    rows: [
      [
        KeyDef.letter('1'),
        KeyDef.letter('2'),
        KeyDef.letter('3'),
        KeyDef.letter('4'),
        KeyDef.letter('5'),
        KeyDef.letter('6'),
        KeyDef.letter('7'),
        KeyDef.letter('8'),
        KeyDef.letter('9'),
        KeyDef.letter('0'),
      ],
      [
        KeyDef.letter('q', shifted: 'Q'),
        KeyDef.letter('w', shifted: 'W'),
        KeyDef.letter('e', shifted: 'E'),
        KeyDef.letter('r', shifted: 'R'),
        KeyDef.letter('t', shifted: 'T'),
        KeyDef.letter('y', shifted: 'Y'),
        KeyDef.letter('u', shifted: 'U'),
        KeyDef.letter('i', shifted: 'I'),
        KeyDef.letter('o', shifted: 'O'),
        KeyDef.letter('p', shifted: 'P'),
      ],
      [
        KeyDef.letter('a', shifted: 'A', flex: 1.05),
        KeyDef.letter('s', shifted: 'S'),
        KeyDef.letter('d', shifted: 'D'),
        KeyDef.letter('f', shifted: 'F'),
        KeyDef.letter('g', shifted: 'G'),
        KeyDef.letter('h', shifted: 'H'),
        KeyDef.letter('j', shifted: 'J'),
        KeyDef.letter('k', shifted: 'K'),
        KeyDef.letter('l', shifted: 'L', flex: 1.05),
      ],
      [
        KeyDef(action: KeyAction.shift, icon: Icons.arrow_upward, flex: 1.6),
        KeyDef.letter('z', shifted: 'Z'),
        KeyDef.letter('x', shifted: 'X'),
        KeyDef.letter('c', shifted: 'C'),
        KeyDef.letter('v', shifted: 'V'),
        KeyDef.letter('b', shifted: 'B'),
        KeyDef.letter('n', shifted: 'N'),
        KeyDef.letter('m', shifted: 'M'),
        KeyDef.letter('.', shifted: ','),
        KeyDef(action: KeyAction.backspace, icon: Icons.backspace_outlined, flex: 1.6),
      ],
      [
        KeyDef(
          action: KeyAction.switchLayout,
          label: '!#?',
          targetLayout: symbols,
          flex: 1.6,
        ),
        KeyDef.letter('-'),
        KeyDef.letter('_'),
        KeyDef(action: KeyAction.space, label: 'space', flex: 4.5),
        KeyDef.letter('@'),
        KeyDef.letter('/'),
        KeyDef(action: KeyAction.enter, icon: Icons.keyboard_return, flex: 1.6),
        KeyDef(action: KeyAction.done, icon: Icons.keyboard_hide_outlined, flex: 1.6),
      ],
    ],
  );

  /// Symbol / punctuation layout. No shift — symbols do not have paired
  /// uppercase variants.
  static const KeyboardLayout symbolsLayout = KeyboardLayout(
    id: symbols,
    supportsShift: false,
    rows: [
      [
        KeyDef.letter('1'),
        KeyDef.letter('2'),
        KeyDef.letter('3'),
        KeyDef.letter('4'),
        KeyDef.letter('5'),
        KeyDef.letter('6'),
        KeyDef.letter('7'),
        KeyDef.letter('8'),
        KeyDef.letter('9'),
        KeyDef.letter('0'),
      ],
      [
        KeyDef.letter('!'),
        KeyDef.letter('@'),
        KeyDef.letter('#'),
        KeyDef.letter(r'$'),
        KeyDef.letter('%'),
        KeyDef.letter('^'),
        KeyDef.letter('&'),
        KeyDef.letter('*'),
        KeyDef.letter('('),
        KeyDef.letter(')'),
      ],
      [
        KeyDef.letter('-'),
        KeyDef.letter('_'),
        KeyDef.letter('='),
        KeyDef.letter('+'),
        KeyDef.letter('['),
        KeyDef.letter(']'),
        KeyDef.letter('{'),
        KeyDef.letter('}'),
        KeyDef.letter(';'),
        KeyDef.letter(':'),
      ],
      [
        KeyDef(action: KeyAction.switchLayout, label: 'abc', targetLayout: alpha, flex: 1.6),
        KeyDef.letter('/'),
        KeyDef.letter('\\'),
        KeyDef.letter('|'),
        KeyDef.letter('<'),
        KeyDef.letter('>'),
        KeyDef.letter(','),
        KeyDef.letter('.'),
        KeyDef.letter('?'),
        KeyDef(action: KeyAction.backspace, icon: Icons.backspace_outlined, flex: 1.6),
      ],
      [
        KeyDef.letter('~'),
        KeyDef.letter('`'),
        KeyDef.letter('"'),
        KeyDef(action: KeyAction.space, label: 'space', flex: 4),
        KeyDef.letter('\''),
        KeyDef.letter('*'),
        KeyDef(action: KeyAction.enter, icon: Icons.keyboard_return, flex: 1.6),
        KeyDef(action: KeyAction.done, icon: Icons.keyboard_hide_outlined, flex: 1.6),
      ],
    ],
  );

  /// URL-optimized alpha layout. Replaces space with `.com` / `/` / `:`
  /// and drops the spacebar since URLs cannot contain spaces.
  static const KeyboardLayout urlLayout = KeyboardLayout(
    id: url,
    rows: [
      [
        KeyDef.letter('1'),
        KeyDef.letter('2'),
        KeyDef.letter('3'),
        KeyDef.letter('4'),
        KeyDef.letter('5'),
        KeyDef.letter('6'),
        KeyDef.letter('7'),
        KeyDef.letter('8'),
        KeyDef.letter('9'),
        KeyDef.letter('0'),
      ],
      [
        KeyDef.letter('q', shifted: 'Q'),
        KeyDef.letter('w', shifted: 'W'),
        KeyDef.letter('e', shifted: 'E'),
        KeyDef.letter('r', shifted: 'R'),
        KeyDef.letter('t', shifted: 'T'),
        KeyDef.letter('y', shifted: 'Y'),
        KeyDef.letter('u', shifted: 'U'),
        KeyDef.letter('i', shifted: 'I'),
        KeyDef.letter('o', shifted: 'O'),
        KeyDef.letter('p', shifted: 'P'),
      ],
      [
        KeyDef.letter('a', shifted: 'A', flex: 1.05),
        KeyDef.letter('s', shifted: 'S'),
        KeyDef.letter('d', shifted: 'D'),
        KeyDef.letter('f', shifted: 'F'),
        KeyDef.letter('g', shifted: 'G'),
        KeyDef.letter('h', shifted: 'H'),
        KeyDef.letter('j', shifted: 'J'),
        KeyDef.letter('k', shifted: 'K'),
        KeyDef.letter('l', shifted: 'L', flex: 1.05),
      ],
      [
        KeyDef(action: KeyAction.shift, icon: Icons.arrow_upward, flex: 1.6),
        KeyDef.letter('z', shifted: 'Z'),
        KeyDef.letter('x', shifted: 'X'),
        KeyDef.letter('c', shifted: 'C'),
        KeyDef.letter('v', shifted: 'V'),
        KeyDef.letter('b', shifted: 'B'),
        KeyDef.letter('n', shifted: 'N'),
        KeyDef.letter('m', shifted: 'M'),
        KeyDef.letter('-'),
        KeyDef(action: KeyAction.backspace, icon: Icons.backspace_outlined, flex: 1.6),
      ],
      [
        KeyDef(
          action: KeyAction.switchLayout,
          label: '!#?',
          targetLayout: symbols,
          flex: 1.4,
        ),
        KeyDef.letter(':'),
        KeyDef.letter('/'),
        KeyDef(action: KeyAction.insert, insertText: '.com', label: '.com', flex: 2),
        KeyDef.letter('.', flex: 1.2),
        KeyDef(action: KeyAction.enter, icon: Icons.keyboard_return, flex: 1.6),
        KeyDef(action: KeyAction.done, icon: Icons.keyboard_hide_outlined, flex: 1.6),
      ],
    ],
  );

  /// Numeric keypad for [TextInputType.number]. Four rows instead of five;
  /// the fifth row is an empty filler so the keyboard height stays constant
  /// across layouts and content doesn't jump.
  static const KeyboardLayout numericLayout = KeyboardLayout(
    id: numeric,
    supportsShift: false,
    rows: [
      [KeyDef.letter('1', flex: 2), KeyDef.letter('2', flex: 2), KeyDef.letter('3', flex: 2)],
      [KeyDef.letter('4', flex: 2), KeyDef.letter('5', flex: 2), KeyDef.letter('6', flex: 2)],
      [KeyDef.letter('7', flex: 2), KeyDef.letter('8', flex: 2), KeyDef.letter('9', flex: 2)],
      [
        KeyDef.letter('.', flex: 2),
        KeyDef.letter('0', flex: 2),
        KeyDef(action: KeyAction.backspace, icon: Icons.backspace_outlined, flex: 2),
      ],
      [
        KeyDef(action: KeyAction.enter, icon: Icons.keyboard_return, flex: 3),
        KeyDef(action: KeyAction.done, icon: Icons.keyboard_hide_outlined, flex: 3),
      ],
    ],
  );
}
