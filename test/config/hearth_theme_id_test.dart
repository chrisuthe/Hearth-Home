import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hearth_theme_id.dart';

void main() {
  test('fromWire reads known values', () {
    expect(HearthThemeId.fromWire('bright'), HearthThemeId.bright);
    expect(HearthThemeId.fromWire('warm'), HearthThemeId.warm);
  });

  test('unknown and null load as classic', () {
    expect(HearthThemeId.fromWire('nope'), HearthThemeId.classic);
    expect(HearthThemeId.fromWire(null), HearthThemeId.classic);
  });

  test('wire and label', () {
    expect(HearthThemeId.warm.wire, 'warm');
    expect(HearthThemeId.bright.label, 'Bright');
  });

  test('wire round-trips for all 12', () {
    for (final id in HearthThemeId.values) {
      expect(HearthThemeId.fromWire(id.wire), id, reason: id.name);
    }
  });

  test('wire values are the persisted strings', () {
    expect(HearthThemeId.values.map((t) => t.wire).toList(), [
      'classic',
      'bright',
      'warm',
      'memories',
      'catppuccin_latte',
      'catppuccin_frappe',
      'catppuccin_macchiato',
      'catppuccin_mocha',
      'tokyonight_night',
      'tokyonight_storm',
      'tokyonight_moon',
      'tokyonight_day',
    ]);
  });

  test('labels', () {
    expect(HearthThemeId.catppuccinFrappe.label, 'Catppuccin Frappé');
    expect(HearthThemeId.tokyoNight.label, 'Tokyo Night');
  });

  test('old configs load', () {
    expect(HearthThemeId.fromWire('bright'), HearthThemeId.bright);
    expect(HearthThemeId.fromWire('Catppuccin'), HearthThemeId.classic);
  });
}
