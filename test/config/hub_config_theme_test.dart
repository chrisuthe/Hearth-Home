import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  test('theme and background default to classic and solid', () {
    const c = HubConfig();
    expect(c.theme, 'classic');
    expect(c.screenBackground, 'solid');
    final fromEmpty = HubConfig.fromJson({});
    expect(fromEmpty.theme, 'classic');
    expect(fromEmpty.screenBackground, 'solid');
  });

  test('theme and background survive a JSON round trip', () {
    final c = const HubConfig().copyWith(theme: 'warm', screenBackground: 'blurred');
    final back = HubConfig.fromJson(c.toJson());
    expect(back.theme, 'warm');
    expect(back.screenBackground, 'blurred');
  });

  test('unknown wire values load as the defaults', () {
    final c = HubConfig.fromJson({'theme': 'neon', 'screenBackground': 42});
    expect(c.theme, 'classic');
    expect(c.screenBackground, 'solid');
  });
}
