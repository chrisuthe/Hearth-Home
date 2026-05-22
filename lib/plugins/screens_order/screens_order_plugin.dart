import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../modules/module_registry.dart';
import '../../widgets/module_placement_tile.dart';
import '../../widgets/module_reorder_list.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Screens & Order plugin — first device-category plugin.
///
/// Owns module placement (where each module appears: swipe / menu1 / menu2)
/// and the swipe-PageView reorder list. Both surfaces are bespoke widgets:
/// no [SettingField] primitive fits cleanly.
///
/// Surface differences:
///   * On-device: full UI — placement chips per module plus drag-reorder
///     list. Community modules are separated under their own subheader.
///   * Web portal: read-only hand-off note. Multi-select chips and drag
///     reorder don't map to the HTML primitives the framework offers today.
///
/// Status: always [PluginConfigStatus.configured] — every module ships with
/// a sane default placement, so there's nothing the user must fill in.
class ScreensOrderPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.screens_order';

  @override
  String get name => 'Screens & Order';

  @override
  IconData get icon => Icons.swap_horiz;

  @override
  PluginCategory get category => PluginCategory.device;

  @override
  int get order => 10;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return const _ScreensOrderPanel();
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    return '''
<div class="field">
  <label>Screens &amp; Order</label>
  <div class="hint" style="color:#888;font-style:italic;padding:12px;background:#161618;border-radius:6px">
    Configure module placement and order from the on-device Settings screen.
  </div>
</div>
''';
  }
}

class _ScreensOrderPanel extends ConsumerWidget {
  const _ScreensOrderPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final allModules = ref.watch(allModulesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...allModules.where((m) => !m.isCommunity).map(
              (m) => ModulePlacementTile(module: m, config: config),
            ),
        if (allModules.any((m) => m.isCommunity)) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: HearthSpacing.x2,
                top: HearthSpacing.x3,
                bottom: HearthSpacing.x1),
            child: Text(
              'Community Contributed',
              style: TextStyle(
                fontSize: HearthFont.caption,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
            child: Text(
              'Modules contributed by the community. Disabled by default — enable at your own discretion.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: HearthFont.caption,
              ),
            ),
          ),
          const SizedBox(height: HearthSpacing.x1),
          ...allModules.where((m) => m.isCommunity).map(
                (m) => ModulePlacementTile(module: m, config: config),
              ),
        ],
        const SizedBox(height: HearthSpacing.x3),
        ModuleReorderList(
          config: config,
          modules: allModules,
          onReorder: (newOrder) {
            ref.read(hubConfigProvider.notifier).update(
                  (c) => c.copyWith(moduleOrder: newOrder),
                );
          },
          onReset: () {
            ref.read(hubConfigProvider.notifier).update(
                  (c) => c.copyWith(moduleOrder: const []),
                );
          },
        ),
      ],
    );
  }
}
