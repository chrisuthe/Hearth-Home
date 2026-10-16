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
}
