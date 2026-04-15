import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'layouts/builtin_layouts.dart';
import 'layouts/keyboard_layout.dart';

/// Controls a globally-installed on-screen keyboard.
///
/// Installed once at app startup via [HearthOskControl.install]. Extends
/// Flutter's [TextInputControl] to intercept every [TextField] focus and
/// input call app-wide, so existing call sites do not need to change.
///
/// The control holds the current [TextEditingValue] for the focused field,
/// exposes it to [HearthOskOverlay] via a [ValueListenable], and writes
/// edits back through [TextInput.updateEditingValue].
class HearthOskControl extends ChangeNotifier with TextInputControl {
  static HearthOskControl? _instance;

  /// The active singleton, if installed.
  static HearthOskControl? get instance => _instance;

  /// Installs [HearthOskControl] as the global text input handler. Call once
  /// from the host app, typically inside `main()` after `runApp`.
  static HearthOskControl install() {
    final existing = _instance;
    if (existing != null) return existing;
    final control = HearthOskControl._();
    TextInput.setInputControl(control);
    _instance = control;
    return control;
  }

  HearthOskControl._();

  // ---------------------------------------------------------------------------
  // Visibility and layout state (listenable by the overlay widget)
  // ---------------------------------------------------------------------------

  bool _visible = false;
  bool get visible => _visible;

  /// True when Shift is engaged for the next character.
  bool _shifted = false;
  bool get shifted => _shifted;

  /// The layout currently displayed. Defaults to alpha and rotates based on
  /// the focused field's [TextInputType] or an explicit `switchLayout` key.
  KeyboardLayout _layout = BuiltinLayouts.alphaLayout;
  KeyboardLayout get layout => _layout;

  /// The editing value reported by the framework for the focused field.
  /// Writes are folded into this before being sent back via
  /// [TextInput.updateEditingValue].
  TextEditingValue _editingValue = TextEditingValue.empty;
  TextEditingValue get editingValue => _editingValue;

  /// Configuration of the focused field, held so we know which layout to
  /// pick when the field requests the keyboard and so we can honor the
  /// action button kind (done/next/search/etc).
  TextInputConfiguration? _configuration;
  TextInputConfiguration? get configuration => _configuration;

  /// The currently-attached client, used for dispatching performAction so
  /// that `onSubmitted` callbacks fire correctly on Enter. Cleared in [detach].
  TextInputClient? _client;

  /// Global override. When false the control silently no-ops on [show] so
  /// the overlay never appears. Host apps set this based on user preference
  /// or physical-keyboard detection.
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value && _visible) {
      _visible = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // TextInputControl overrides — called by the framework
  // ---------------------------------------------------------------------------

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    _configuration = configuration;
    _layout = _layoutFor(configuration.inputType);
    notifyListeners();
  }

  @override
  void detach(TextInputClient client) {
    if (identical(_client, client)) _client = null;
    _configuration = null;
    if (_visible) {
      _visible = false;
      notifyListeners();
    }
  }

  @override
  void show() {
    if (!_enabled) return;
    if (_configuration != null) {
      _layout = _layoutFor(_configuration!.inputType);
    }
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
  }

  @override
  void hide() {
    if (_visible) {
      _visible = false;
      notifyListeners();
    }
  }

  @override
  void setEditingState(TextEditingValue value) {
    _editingValue = value;
    // No notify — the text field re-reads its value independently. Overlay
    // does not render the value, so this is pure state tracking.
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    _configuration = configuration;
    final next = _layoutFor(configuration.inputType);
    if (next.id != _layout.id) {
      _layout = next;
      _shifted = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Key dispatch — called by the overlay when a key is tapped
  // ---------------------------------------------------------------------------

  /// Dispatches a key press through the framework. Updates [_editingValue]
  /// and pushes the new value to Flutter via [TextInput.updateEditingValue].
  void handleKey(KeyDef key) {
    switch (key.action) {
      case KeyAction.insert:
        final text = key.resolveInsert(shifted: _shifted);
        if (text != null) _insert(text);
        // A single shift press deactivates after the next character.
        if (_shifted) {
          _shifted = false;
          notifyListeners();
        }
      case KeyAction.space:
        _insert(' ');
      case KeyAction.backspace:
        _backspace();
      case KeyAction.enter:
        _handleEnter();
      case KeyAction.shift:
        _shifted = !_shifted;
        notifyListeners();
      case KeyAction.switchLayout:
        final target = key.targetLayout;
        if (target != null) {
          _layout = _layoutById(target);
          _shifted = false;
          notifyListeners();
        }
      case KeyAction.done:
        hide();
      case KeyAction.moveCursorLeft:
        _moveCursor(-1);
      case KeyAction.moveCursorRight:
        _moveCursor(1);
    }
  }

  // ---------------------------------------------------------------------------
  // Editing primitives
  // ---------------------------------------------------------------------------

  void _insert(String text) {
    final current = _editingValue;
    final selection = current.selection;
    // When the framework hasn't yet reported a selection (selection.start < 0)
    // treat the cursor as being at the end of the existing text.
    final start = selection.start >= 0 ? selection.start : current.text.length;
    final end = selection.end >= 0 ? selection.end : current.text.length;
    final before = current.text.substring(0, start);
    final after = current.text.substring(end);
    final newText = '$before$text$after';
    final newOffset = before.length + text.length;
    _pushValue(TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    ));
  }

  void _backspace() {
    final current = _editingValue;
    final selection = current.selection;
    if (current.text.isEmpty) return;
    if (selection.isValid && !selection.isCollapsed) {
      // Delete the selected range.
      final before = current.text.substring(0, selection.start);
      final after = current.text.substring(selection.end);
      _pushValue(TextEditingValue(
        text: '$before$after',
        selection: TextSelection.collapsed(offset: before.length),
      ));
      return;
    }
    final cursor = selection.start >= 0 ? selection.start : current.text.length;
    if (cursor == 0) return;
    final before = current.text.substring(0, cursor - 1);
    final after = current.text.substring(cursor);
    _pushValue(TextEditingValue(
      text: '$before$after',
      selection: TextSelection.collapsed(offset: before.length),
    ));
  }

  void _moveCursor(int delta) {
    final current = _editingValue;
    final cursor = (current.selection.isValid ? current.selection.start : current.text.length) + delta;
    final clamped = cursor.clamp(0, current.text.length);
    _pushValue(current.copyWith(
      selection: TextSelection.collapsed(offset: clamped),
    ));
  }

  void _handleEnter() {
    final config = _configuration;
    if (config == null) return;
    final multiline = config.inputType == TextInputType.multiline;
    if (multiline) {
      _insert('\n');
      return;
    }
    // For single-line fields, fire the configured action (done/next/search/etc)
    // on the attached client so `onSubmitted` callbacks run.
    _client?.performAction(config.inputAction);
  }

  void _pushValue(TextEditingValue value) {
    _editingValue = value;
    TextInput.updateEditingValue(value);
  }

  // ---------------------------------------------------------------------------
  // Layout selection
  // ---------------------------------------------------------------------------

  KeyboardLayout _layoutFor(TextInputType type) {
    if (type == TextInputType.number || type == TextInputType.phone) {
      return BuiltinLayouts.numericLayout;
    }
    if (type == TextInputType.url) {
      return BuiltinLayouts.urlLayout;
    }
    return BuiltinLayouts.alphaLayout;
  }

  KeyboardLayout _layoutById(String id) {
    switch (id) {
      case BuiltinLayouts.alpha:
        return BuiltinLayouts.alphaLayout;
      case BuiltinLayouts.symbols:
        return BuiltinLayouts.symbolsLayout;
      case BuiltinLayouts.url:
        return BuiltinLayouts.urlLayout;
      case BuiltinLayouts.numeric:
        return BuiltinLayouts.numericLayout;
      default:
        return BuiltinLayouts.alphaLayout;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
