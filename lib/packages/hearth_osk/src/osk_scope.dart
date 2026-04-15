import 'package:flutter/material.dart';

import 'osk_control.dart';
import 'osk_theme.dart';
import 'osk_widgets.dart';

/// Wraps an app (usually via `MaterialApp.builder`) to mount the on-screen
/// keyboard overlay and override `MediaQuery.viewInsets.bottom` so that
/// dialogs and scrollable contents automatically reserve space for the
/// keyboard without any widget-level changes at call sites.
///
/// Usage:
/// ```dart
/// MaterialApp(
///   builder: (context, child) => HearthOskScope(
///     control: HearthOskControl.install(),
///     theme: const HearthOskTheme(),
///     child: child!,
///   ),
/// )
/// ```
class HearthOskScope extends StatefulWidget {
  final HearthOskControl control;
  final HearthOskTheme theme;
  final Widget child;

  const HearthOskScope({
    super.key,
    required this.control,
    this.theme = const HearthOskTheme(),
    required this.child,
  });

  @override
  State<HearthOskScope> createState() => _HearthOskScopeState();
}

class _HearthOskScopeState extends State<HearthOskScope> {
  @override
  void initState() {
    super.initState();
    widget.control.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.control.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final height = widget.control.visible ? widget.theme.totalHeight : 0.0;
    // Inject the keyboard height as a synthetic bottom viewInset so that
    // any widget that respects viewInsets (Scaffold, AlertDialog, etc.)
    // automatically leaves room for the keyboard.
    final patchedMq = mq.copyWith(
      viewInsets: mq.viewInsets.copyWith(
        bottom: mq.viewInsets.bottom + height,
      ),
    );
    return MediaQuery(
      data: patchedMq,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HearthOskOverlay(
              control: widget.control,
              theme: widget.theme,
            ),
          ),
        ],
      ),
    );
  }
}
