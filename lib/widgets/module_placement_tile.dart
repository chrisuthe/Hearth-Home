import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/hearth_colors.dart';
import '../app/tokens/tokens.dart';
import '../config/hub_config.dart';
import '../modules/hearth_module.dart';

/// ListTile that lets the user choose where a module appears: the swipe
/// PageView, the first menu drawer, or the second menu drawer.
///
/// Used by the Screens & Order plugin. Originally a private
/// `_modulePlacementTile` helper in `settings_screen.dart`; extracted so
/// the plugin can render it directly.
class ModulePlacementTile extends ConsumerWidget {
  final HearthModule module;
  final HubConfig config;

  const ModulePlacementTile({
    super.key,
    required this.module,
    required this.config,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placements =
        List<String>.from(config.modulePlacements[module.id] ?? const []);
    final colors = context.hearthColors;
    return ListTile(
      leading: Icon(module.icon, color: colors.textMuted),
      title: Text(module.name),
      subtitle: Wrap(
        spacing: 6,
        children: [
          for (final placement in const ['swipe', 'menu1', 'menu2'])
            FilterChip(
              label: Text(
                placement == 'swipe'
                    ? 'Swipe'
                    : placement == 'menu1'
                        ? 'Menu 1'
                        : 'Menu 2',
                style: const TextStyle(fontSize: HearthFont.caption),
              ),
              selected: placements.contains(placement),
              onSelected: (selected) {
                final updated = Map<String, List<String>>.from(
                    config.modulePlacements);
                final list = List<String>.from(updated[module.id] ?? const []);
                if (selected) {
                  list.add(placement);
                } else {
                  list.remove(placement);
                }
                if (list.isEmpty) {
                  updated.remove(module.id);
                } else {
                  updated[module.id] = list;
                }
                ref.read(hubConfigProvider.notifier).update(
                      (c) => c.copyWith(modulePlacements: updated),
                    );
              },
              selectedColor: colors.accentFill,
              backgroundColor: colors.raised,
              labelStyle: TextStyle(
                color: placements.contains(placement)
                    ? colors.text
                    : colors.textSecondary,
                fontSize: HearthFont.caption,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }
}
