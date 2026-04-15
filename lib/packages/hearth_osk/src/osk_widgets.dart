import 'package:flutter/material.dart';

import 'layouts/keyboard_layout.dart';
import 'osk_control.dart';
import 'osk_theme.dart';

/// A single key. Renders as either an icon or a text label depending on
/// [KeyDef.icon]. Highlights when active (shift engaged).
class HearthOskKey extends StatefulWidget {
  final KeyDef keyDef;
  final HearthOskTheme theme;
  final bool shifted;
  final bool active;
  final VoidCallback onPressed;

  const HearthOskKey({
    super.key,
    required this.keyDef,
    required this.theme,
    required this.shifted,
    required this.active,
    required this.onPressed,
  });

  @override
  State<HearthOskKey> createState() => _HearthOskKeyState();
}

class _HearthOskKeyState extends State<HearthOskKey> {
  bool _pressed = false;

  bool get _isModifier {
    switch (widget.keyDef.action) {
      case KeyAction.insert:
      case KeyAction.space:
        return false;
      case KeyAction.shift:
      case KeyAction.backspace:
      case KeyAction.enter:
      case KeyAction.done:
      case KeyAction.switchLayout:
      case KeyAction.moveCursorLeft:
      case KeyAction.moveCursorRight:
        return true;
    }
  }

  Color _fill() {
    if (widget.active) return widget.theme.modifierActiveFill;
    if (_isModifier) return widget.theme.modifierFill;
    return widget.theme.keyFill;
  }

  Color _labelColor() {
    if (widget.active) return widget.theme.modifierActiveLabel;
    return widget.theme.keyLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final label = widget.keyDef.action == KeyAction.insert && widget.shifted
        ? (widget.keyDef.shiftLabel ?? widget.keyDef.label)
        : widget.keyDef.label;
    final icon = widget.keyDef.icon;
    final fill = _fill();
    final pressedFill = Color.lerp(fill, theme.accent, 0.25) ?? fill;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: _pressed ? pressedFill : fill,
          borderRadius: theme.keyRadius,
          border: widget.active
              ? Border.all(color: theme.accent, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: _labelColor(), size: theme.keyLabelSize)
            : Text(
                label ?? '',
                style: TextStyle(
                  color: _labelColor(),
                  fontSize: label != null && label.length > 1
                      ? theme.keyLabelSize * 0.65
                      : theme.keyLabelSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

/// Renders a [KeyboardLayout] as a column of [Row]s of [HearthOskKey]s.
class HearthOskGrid extends StatelessWidget {
  final KeyboardLayout layout;
  final HearthOskTheme theme;
  final bool shifted;
  final ValueChanged<KeyDef> onKey;

  const HearthOskGrid({
    super.key,
    required this.layout,
    required this.theme,
    required this.shifted,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final rows = layout.rows;
    return Padding(
      padding: theme.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            SizedBox(
              height: theme.keyHeight,
              child: Row(
                children: [
                  for (int j = 0; j < rows[i].length; j++) ...[
                    Expanded(
                      flex: (rows[i][j].flex * 100).round(),
                      child: HearthOskKey(
                        keyDef: rows[i][j],
                        theme: theme,
                        shifted: shifted,
                        active: rows[i][j].action == KeyAction.shift && shifted,
                        onPressed: () => onKey(rows[i][j]),
                      ),
                    ),
                    if (j < rows[i].length - 1) SizedBox(width: theme.keySpacing),
                  ],
                ],
              ),
            ),
            if (i < rows.length - 1) SizedBox(height: theme.keySpacing),
          ],
        ],
      ),
    );
  }
}

/// The overlay that slides the keyboard up from the bottom of the screen.
///
/// Intended to be mounted by [HearthOskScope] — host apps don't place this
/// directly. Listens to [HearthOskControl] and animates based on
/// `control.visible`.
class HearthOskOverlay extends StatefulWidget {
  final HearthOskControl control;
  final HearthOskTheme theme;

  const HearthOskOverlay({
    super.key,
    required this.control,
    required this.theme,
  });

  @override
  State<HearthOskOverlay> createState() => _HearthOskOverlayState();
}

class _HearthOskOverlayState extends State<HearthOskOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: widget.theme.animationDuration,
      value: widget.control.visible ? 1 : 0,
    );
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    widget.control.addListener(_onControlChange);
  }

  @override
  void didUpdateWidget(covariant HearthOskOverlay old) {
    super.didUpdateWidget(old);
    if (old.control != widget.control) {
      old.control.removeListener(_onControlChange);
      widget.control.addListener(_onControlChange);
    }
  }

  @override
  void dispose() {
    widget.control.removeListener(_onControlChange);
    _anim.dispose();
    super.dispose();
  }

  void _onControlChange() {
    if (!mounted) return;
    if (widget.control.visible) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final control = widget.control;
    return IgnorePointer(
      ignoring: !control.visible && _anim.value == 0,
      child: SlideTransition(
        position: _slide,
        child: Container(
          color: theme.background,
          child: SafeArea(
            top: false,
            child: HearthOskGrid(
              layout: control.layout,
              theme: theme,
              shifted: control.shifted,
              onKey: control.handleKey,
            ),
          ),
        ),
      ),
    );
  }
}
