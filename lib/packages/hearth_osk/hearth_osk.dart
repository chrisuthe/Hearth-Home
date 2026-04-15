/// A self-contained on-screen keyboard for Flutter apps on platforms that
/// lack a system IME (e.g. flutter-pi on Raspberry Pi).
///
/// This package is designed to be extracted to a standalone Dart package.
/// It does not depend on any host-app code; host apps inject their own
/// theme and configuration via [HearthOskTheme] and [HearthOskControl].
///
/// Usage:
/// ```dart
/// void main() {
///   runApp(
///     MaterialApp(
///       builder: (context, child) => HearthOskScope(
///         control: HearthOskControl.install(),
///         theme: const HearthOskTheme(),
///         child: child!,
///       ),
///       home: ...,
///     ),
///   );
/// }
/// ```
library hearth_osk;

export 'src/layouts/builtin_layouts.dart';
export 'src/layouts/keyboard_layout.dart';
export 'src/osk_control.dart';
export 'src/osk_scope.dart';
export 'src/osk_theme.dart';
