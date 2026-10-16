/// Which palette the app wears.
///
/// Persisted as [wire] in `HubConfig.theme`.
enum HearthThemeId {
  classic,
  bright,
  warm;

  /// Anything unrecognised loads as [classic].
  static HearthThemeId fromWire(String? value) {
    for (final t in HearthThemeId.values) {
      if (t.wire == value) return t;
    }
    return HearthThemeId.classic;
  }

  String get wire => name;

  String get label => switch (this) {
        HearthThemeId.classic => 'Classic',
        HearthThemeId.bright => 'Bright',
        HearthThemeId.warm => 'Warm',
      };
}
