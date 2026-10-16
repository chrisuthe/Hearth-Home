import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hearth_theme_id.dart';
import '../../config/hub_config.dart';
import '../../config/screen_background.dart';
import 'hearth_colors.dart';

/// The theme the config selects, following `HubConfig.theme` live.
final hearthThemeIdProvider = Provider<HearthThemeId>((ref) {
  final wire = ref.watch(hubConfigProvider.select((c) => c.theme));
  return HearthThemeId.fromWire(wire);
});

/// The palette the app wears, following `HubConfig.theme` live.
final hearthColorsProvider = Provider<HearthColors>((ref) {
  return HearthColors.forTheme(ref.watch(hearthThemeIdProvider));
});

/// What sits behind the active screens, following `HubConfig.screenBackground`.
final screenBackgroundProvider = Provider<ScreenBackground>((ref) {
  final wire = ref.watch(hubConfigProvider.select((c) => c.screenBackground));
  return ScreenBackground.fromWire(wire);
});
