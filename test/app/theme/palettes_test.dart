import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/palettes/catppuccin.dart';
import 'package:hearth/app/theme/palettes/tokyo_night.dart';
import 'package:hearth/config/hearth_theme_id.dart';

void main() {
  test('catppuccin uses upstream base colors', () {
    // base, mantle, surface0, text, mauve from catppuccin/palette.
    final expected = {
      HearthThemeId.catppuccinLatte: (
        CatppuccinPalettes.latte,
        [0xFFEFF1F5, 0xFFE6E9EF, 0xFFCCD0DA, 0xFF4C4F69, 0xFF8839EF],
      ),
      HearthThemeId.catppuccinFrappe: (
        CatppuccinPalettes.frappe,
        [0xFF303446, 0xFF292C3C, 0xFF414559, 0xFFC6D0F5, 0xFFCA9EE6],
      ),
      HearthThemeId.catppuccinMacchiato: (
        CatppuccinPalettes.macchiato,
        [0xFF24273A, 0xFF1E2030, 0xFF363A4F, 0xFFCAD3F5, 0xFFC6A0F6],
      ),
      HearthThemeId.catppuccinMocha: (
        CatppuccinPalettes.mocha,
        [0xFF1E1E2E, 0xFF181825, 0xFF313244, 0xFFCDD6F4, 0xFFCBA6F7],
      ),
    };
    expected.forEach((id, entry) {
      final (c, v) = entry;
      expect(c.canvas, Color(v[0]), reason: '${id.name} canvas');
      expect(c.surface, Color(v[1]), reason: '${id.name} surface');
      expect(c.card, Color(v[2]), reason: '${id.name} card');
      expect(c.text, Color(v[3]), reason: '${id.name} text');
      expect(c.accent, Color(v[4]), reason: '${id.name} accent');
      expect(identical(HearthColors.forTheme(id), c), isTrue, reason: id.name);
    });
  });

  test('tokyo night uses upstream base colors', () {
    // bg, bg_dark, bg_highlight, fg, blue from folke/tokyonight.nvim.
    final expected = {
      HearthThemeId.tokyoNight: (
        TokyoNightPalettes.night,
        [0xFF1A1B26, 0xFF16161E, 0xFF292E42, 0xFFC0CAF5, 0xFF7AA2F7],
      ),
      HearthThemeId.tokyoNightStorm: (
        TokyoNightPalettes.storm,
        [0xFF24283B, 0xFF1F2335, 0xFF292E42, 0xFFC0CAF5, 0xFF7AA2F7],
      ),
      HearthThemeId.tokyoNightMoon: (
        TokyoNightPalettes.moon,
        [0xFF222436, 0xFF1E2030, 0xFF2F334D, 0xFFC8D3F5, 0xFF82AAFF],
      ),
      HearthThemeId.tokyoNightDay: (
        TokyoNightPalettes.day,
        // Day's text and accent are contrast-forced darker than upstream
        // fg #3760bf and blue #2e7de9.
        [0xFFE1E2E7, 0xFFD0D5E3, 0xFFC4C8DA, 0xFF2E51A0, 0xFF286ECD],
      ),
    };
    expected.forEach((id, entry) {
      final (c, v) = entry;
      expect(c.canvas, Color(v[0]), reason: '${id.name} canvas');
      expect(c.surface, Color(v[1]), reason: '${id.name} surface');
      expect(c.card, Color(v[2]), reason: '${id.name} card');
      expect(c.text, Color(v[3]), reason: '${id.name} text');
      expect(c.accent, Color(v[4]), reason: '${id.name} accent');
      expect(identical(HearthColors.forTheme(id), c), isTrue, reason: id.name);
    });
  });
}
