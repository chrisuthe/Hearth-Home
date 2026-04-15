import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/packages/hearth_osk/hearth_osk.dart';

/// Unit tests for HearthOskControl's editing primitives. Runs in pure Dart
/// without a widget tree; we exercise the control in isolation by calling
/// `setEditingState` + `handleKey` and reading back `editingValue`.
void main() {
  // TextInput.setInputControl touches a MethodChannel so the test binding
  // must be initialized before HearthOskControl.install() is called.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HearthOskControl editing', () {
    late HearthOskControl control;

    setUp(() {
      HearthOskControl.resetForTest();
      control = HearthOskControl.install();
    });

    tearDown(() {
      HearthOskControl.resetForTest();
    });

    test('insert appends at cursor', () {
      control.setEditingState(const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 3),
      ));
      control.handleKey(const KeyDef.letter('d'));
      expect(control.editingValue.text, 'abcd');
      expect(control.editingValue.selection.baseOffset, 4);
    });

    test('insert at middle cursor splits text', () {
      control.setEditingState(const TextEditingValue(
        text: 'abd',
        selection: TextSelection.collapsed(offset: 2),
      ));
      control.handleKey(const KeyDef.letter('c'));
      expect(control.editingValue.text, 'abcd');
      expect(control.editingValue.selection.baseOffset, 3);
    });

    test('insert replaces selected range', () {
      control.setEditingState(const TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      ));
      control.handleKey(const KeyDef.letter('there', flex: 1));
      expect(control.editingValue.text, 'hello there');
      expect(control.editingValue.selection.baseOffset, 11);
    });

    test('shift engages uppercase for next character then releases', () {
      control.setEditingState(const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ));
      expect(control.shifted, isFalse);
      control.handleKey(const KeyDef(action: KeyAction.shift));
      expect(control.shifted, isTrue);
      control.handleKey(const KeyDef.letter('a', shifted: 'A'));
      expect(control.editingValue.text, 'A');
      expect(control.shifted, isFalse);
      control.handleKey(const KeyDef.letter('b', shifted: 'B'));
      expect(control.editingValue.text, 'Ab');
    });

    test('backspace removes char before cursor', () {
      control.setEditingState(const TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 4),
      ));
      control.handleKey(const KeyDef(action: KeyAction.backspace));
      expect(control.editingValue.text, 'abc');
      expect(control.editingValue.selection.baseOffset, 3);
    });

    test('backspace removes selected range when not collapsed', () {
      control.setEditingState(const TextEditingValue(
        text: 'abcdef',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      ));
      control.handleKey(const KeyDef(action: KeyAction.backspace));
      expect(control.editingValue.text, 'aef');
      expect(control.editingValue.selection.baseOffset, 1);
    });

    test('backspace at start of text is a no-op', () {
      control.setEditingState(const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 0),
      ));
      control.handleKey(const KeyDef(action: KeyAction.backspace));
      expect(control.editingValue.text, 'abc');
    });

    test('space inserts a space character', () {
      control.setEditingState(const TextEditingValue(
        text: 'hi',
        selection: TextSelection.collapsed(offset: 2),
      ));
      control.handleKey(const KeyDef(action: KeyAction.space));
      expect(control.editingValue.text, 'hi ');
    });

    test('switchLayout changes the active layout and clears shift', () {
      control.handleKey(const KeyDef(action: KeyAction.shift));
      expect(control.shifted, isTrue);
      control.handleKey(const KeyDef(
        action: KeyAction.switchLayout,
        targetLayout: BuiltinLayouts.symbols,
      ));
      expect(control.layout.id, BuiltinLayouts.symbols);
      expect(control.shifted, isFalse);
    });

    test('done key hides the overlay', () {
      // Manually surface the keyboard as if a TextField had focused.
      control.show();
      expect(control.visible, isTrue);
      control.handleKey(const KeyDef(action: KeyAction.done));
      expect(control.visible, isFalse);
    });

    test('enabled=false blocks show', () {
      control.enabled = false;
      control.show();
      expect(control.visible, isFalse);
      control.enabled = true;
      control.show();
      expect(control.visible, isTrue);
    });

    test('layout auto-selects from TextInputConfiguration.inputType', () {
      // ignore: invalid_use_of_protected_member
      control.attach(
        _NoopClient(),
        const TextInputConfiguration(inputType: TextInputType.number),
      );
      expect(control.layout.id, BuiltinLayouts.numeric);
      // ignore: invalid_use_of_protected_member
      control.attach(
        _NoopClient(),
        const TextInputConfiguration(inputType: TextInputType.url),
      );
      expect(control.layout.id, BuiltinLayouts.url);
    });
  });
}

/// Minimal stub — the control only stores the reference, it doesn't call
/// into it unless Enter is pressed.
class _NoopClient implements TextInputClient {
  @override
  noSuchMethod(Invocation invocation) => null;
}
