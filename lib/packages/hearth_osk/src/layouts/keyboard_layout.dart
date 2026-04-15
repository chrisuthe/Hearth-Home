import 'package:flutter/material.dart';

/// The action performed when a key is tapped.
///
/// [insert] pushes [insertText] at the current cursor. The other variants
/// are handled directly by the control.
enum KeyAction {
  insert,
  backspace,
  enter,
  space,
  shift,
  done,
  switchLayout,
  moveCursorLeft,
  moveCursorRight,
}

/// One key on the keyboard.
@immutable
class KeyDef {
  final KeyAction action;

  /// Character inserted when [action] is [KeyAction.insert].
  final String? insertText;

  /// Shown on the key face when the default (lowercase) mode is active.
  final String? label;

  /// Shown on the key face when [shift] mode is active.
  final String? shiftLabel;

  /// Icon shown instead of a text label (shift arrow, backspace, etc.).
  final IconData? icon;

  /// Flex weight for width; 1 = a single letter key, 2 = a wider key.
  final double flex;

  /// If [action] is [KeyAction.switchLayout], the layout id to switch to.
  final String? targetLayout;

  const KeyDef({
    required this.action,
    this.insertText,
    this.label,
    this.shiftLabel,
    this.icon,
    this.flex = 1,
    this.targetLayout,
  });

  /// Convenience constructor for a character key whose label matches the
  /// inserted text, with an optional shifted variant.
  const KeyDef.letter(String char, {String? shifted, double flex = 1})
      : action = KeyAction.insert,
        insertText = char,
        label = char,
        shiftLabel = shifted,
        icon = null,
        flex = flex,
        targetLayout = null;

  /// The character this key will insert given a shift state, or null for
  /// non-insert keys. Useful when rendering and when dispatching inserts.
  String? resolveInsert({required bool shifted}) {
    if (action != KeyAction.insert) return null;
    if (shifted && shiftLabel != null) return shiftLabel;
    return insertText;
  }
}

/// A named set of key rows. A layout is a rectangular grid; each row is a
/// list of [KeyDef]s whose `flex` values determine relative widths.
@immutable
class KeyboardLayout {
  final String id;
  final List<List<KeyDef>> rows;

  /// Whether the shift key toggles a secondary (uppercase) set of labels.
  /// Set false for symbol layouts that don't have a paired shift state.
  final bool supportsShift;

  const KeyboardLayout({
    required this.id,
    required this.rows,
    this.supportsShift = true,
  });
}
