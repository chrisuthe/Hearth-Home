import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/config/hearth_theme_id.dart';

double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double contrast(Color a, Color b) {
  final x = luminance(a), y = luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// sRGB-space compositing, as Flutter paints.
Color flatten(Color top, Color under) => Color.alphaBlend(top, under);

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

void main() {
  for (final id in HearthThemeId.values) {
    final c = HearthColors.forTheme(id);

    final solids = <String, Color>{
      'canvas': c.canvas,
      'surface': c.surface,
      'card': c.card,
      'menu': c.menu,
      'raised': c.raised,
    };
    final tinted = <String, Color>{
      for (final s in TintStrength.values) ...{
        'photoTint(${s.name}) over black': flatten(c.photoTint(s), _black),
        'photoTint(${s.name}) over white': flatten(c.photoTint(s), _white),
      },
      'blurTint over black': flatten(c.blurTint, _black),
      'blurTint over white': flatten(c.blurTint, _white),
    };
    final all = {...solids, ...tinted};

    group('${id.name} contrast', () {
      final fg = <String, Color>{
        'text': c.text,
        'textSecondary': c.textSecondary,
        'textMuted': c.textMuted,
        'accentText': c.accentText,
        'danger': c.danger,
        'success': c.success,
        'warning': c.warning,
      };
      test('text roles reach 4.5:1 on every background', () {
        final fails = <String>[];
        fg.forEach((role, color) {
          all.forEach((bgName, bg) {
            final r = contrast(flatten(color, bg), bg);
            if (r < 4.5) {
              fails.add('${id.name} $role on $bgName: ${r.toStringAsFixed(2)}');
            }
          });
        });
        expect(fails, isEmpty);
      });

      test('onAccent on accentFill reaches 4.5:1', () {
        final r = contrast(c.onAccent, c.accentFill);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${id.name} onAccent on accentFill: $r');
      });

      test('accent reaches 3:1 on solid backgrounds', () {
        final fails = <String>[];
        solids.forEach((bgName, bg) {
          final r = contrast(c.accent, bg);
          if (r < 3.0) {
            fails.add('${id.name} accent on $bgName: ${r.toStringAsFixed(2)}');
          }
        });
        expect(fails, isEmpty);
      });

      test('calendar text reaches 4.5:1', () {
        final cal = c.calendar;
        final bgs = <String, Color>{
          'canvas': c.canvas,
          'sheet': cal.sheet,
          'blurTint over black': flatten(c.blurTint, _black),
          'blurTint over white': flatten(c.blurTint, _white),
        };
        final roles = <String, Color>{
          'text': cal.text,
          'textMuted': cal.textMuted,
          'textDim': cal.textDim,
          'textFaint': cal.textFaint,
          'pillOffText': cal.pillOffText,
          'sheetSecondary': cal.sheetSecondary,
          'bannerDetail': cal.bannerDetail,
          'accentText': cal.accentText,
          'error': cal.error,
        };
        final fails = <String>[];
        roles.forEach((role, color) {
          bgs.forEach((bgName, bg) {
            final r = contrast(flatten(color, bg), bg);
            if (r < 4.5) {
              fails.add(
                  '${id.name} calendar.$role on $bgName: ${r.toStringAsFixed(2)}');
            }
          });
        });
        expect(fails, isEmpty);
      });
    });
  }
}
