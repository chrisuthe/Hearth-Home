/// What sits behind the active screens.
///
/// Persisted as [wire] in `HubConfig.screenBackground`.
enum ScreenBackground {
  solid,
  blurred;

  /// Anything unrecognised loads as [solid].
  static ScreenBackground fromWire(String? value) {
    for (final b in ScreenBackground.values) {
      if (b.wire == value) return b;
    }
    return ScreenBackground.solid;
  }

  String get wire => name;

  String get label => switch (this) {
        ScreenBackground.solid => 'Solid',
        ScreenBackground.blurred => 'Blurred photo',
      };
}
