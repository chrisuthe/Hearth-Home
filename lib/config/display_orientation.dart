import 'package:flutter/services.dart' show DeviceOrientation;

/// Which way up the panel is mounted.
///
/// Persisted as [wire] in `HubConfig.displayOrientation`. The Pi has no
/// orientation sensor, so [auto] there means "as the panel reports itself";
/// on Android it follows the tablet's sensor.
enum DisplayOrientation {
  auto,
  landscape,
  portrait,
  landscapeFlipped,
  portraitFlipped;

  /// Anything unrecognised loads as [auto] so a bad config never rotates the
  /// kiosk into an unusable state.
  static DisplayOrientation fromWire(String? value) {
    for (final o in DisplayOrientation.values) {
      if (o.wire == value) return o;
    }
    return DisplayOrientation.auto;
  }

  String get wire => name;

  String get label => switch (this) {
        DisplayOrientation.auto => 'Auto',
        DisplayOrientation.landscape => 'Landscape',
        DisplayOrientation.portrait => 'Portrait',
        DisplayOrientation.landscapeFlipped => 'Landscape (flipped)',
        DisplayOrientation.portraitFlipped => 'Portrait (flipped)',
      };

  /// Clockwise degrees for flutter-pi's `--rotation`. Must stay in step with
  /// the table in `scripts/hearth-launch.sh`, which is what actually applies it.
  int get piRotationDegrees => switch (this) {
        DisplayOrientation.auto => 0,
        DisplayOrientation.landscape => 0,
        DisplayOrientation.portrait => 90,
        DisplayOrientation.landscapeFlipped => 180,
        DisplayOrientation.portraitFlipped => 270,
      };

  /// Argument for `SystemChrome.setPreferredOrientations` on Android.
  List<DeviceOrientation> get androidOrientations => switch (this) {
        DisplayOrientation.auto => DeviceOrientation.values,
        DisplayOrientation.landscape => const [DeviceOrientation.landscapeLeft],
        DisplayOrientation.portrait => const [DeviceOrientation.portraitUp],
        DisplayOrientation.landscapeFlipped => const [
            DeviceOrientation.landscapeRight
          ],
        DisplayOrientation.portraitFlipped => const [
            DeviceOrientation.portraitDown
          ],
      };
}
