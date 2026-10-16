import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearth_plugin.dart';
import '../plugin_registry.dart';
import '../../app/theme/hearth_colors.dart';

/// Sidebar widget listing all registered plugins grouped by category.
///
/// The selected plugin is owned by the caller via [selectedId]; sidebar
/// fires [onSelected] when the user taps a row.
class PluginSidebar extends ConsumerWidget {
  /// Currently-selected plugin ID.
  final String selectedId;

  /// Fires when the user selects a different sidebar entry.
  final void Function(String id) onSelected;

  const PluginSidebar({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final plugins = ref.watch(visiblePluginsProvider);
    final features = plugins.where((p) => p.category == PluginCategory.feature).toList();
    final devices = plugins.where((p) => p.category == PluginCategory.device).toList();

    // 240 on every canvas the panel ships at; only a portrait panel at a large
    // UI scale is narrow enough for the cap to bite and hand width back to the
    // settings panel.
    final width = math.min(240.0, MediaQuery.sizeOf(context).width * 0.36);

    return Container(
      width: width,
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          if (features.isNotEmpty) ...[
            const _CategoryHeader(label: 'FEATURES'),
            for (final p in features) _Row(
              plugin: p,
              selected: p.id == selectedId,
              onTap: () => onSelected(p.id),
            ),
          ],
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _CategoryHeader(label: 'DEVICE'),
            for (final p in devices) _Row(
              plugin: p,
              selected: p.id == selectedId,
              onTap: () => onSelected(p.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String label;
  const _CategoryHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: c.textMuted,
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  final HearthPlugin plugin;
  final bool selected;
  final VoidCallback onTap;

  const _Row({required this.plugin, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: selected ? c.accent.withValues(alpha: 0.18) : Colors.transparent,
        child: Row(
          children: [
            Icon(plugin.icon,
                color: selected ? c.accentText : c.textSecondary,
                size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plugin.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.accentText : c.text,
                  fontSize: 13,
                ),
              ),
            ),
            if (plugin.isCommunity)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('community',
                    style: TextStyle(color: c.textMuted, fontSize: 9)),
              ),
          ],
        ),
      ),
    );
  }
}
