/// Which palette the app wears.
///
/// Persisted as [wire] in `HubConfig.theme`. The wire values are stable
/// once shipped: renaming one would silently reset users' saved theme.
enum HearthThemeId {
  classic('classic', 'Classic'),
  bright('bright', 'Bright'),
  warm('warm', 'Warm'),
  memories('memories', 'Memories'),
  catppuccinLatte('catppuccin_latte', 'Catppuccin Latte'),
  catppuccinFrappe('catppuccin_frappe', 'Catppuccin Frappé'),
  catppuccinMacchiato('catppuccin_macchiato', 'Catppuccin Macchiato'),
  catppuccinMocha('catppuccin_mocha', 'Catppuccin Mocha'),
  tokyoNight('tokyonight_night', 'Tokyo Night'),
  tokyoNightStorm('tokyonight_storm', 'Tokyo Night Storm'),
  tokyoNightMoon('tokyonight_moon', 'Tokyo Night Moon'),
  tokyoNightDay('tokyonight_day', 'Tokyo Night Day');

  const HearthThemeId(this.wire, this.label);

  /// The string persisted in `HubConfig.theme`.
  final String wire;

  /// The name shown in the Display settings.
  final String label;

  /// Anything unrecognised loads as [classic].
  static HearthThemeId fromWire(String? value) {
    for (final t in HearthThemeId.values) {
      if (t.wire == value) return t;
    }
    return HearthThemeId.classic;
  }
}
