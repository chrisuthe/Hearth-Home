import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearth_plugin.dart';
import '../plugin_registry.dart';

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
    final plugins = ref.watch(allPluginsProvider);
    final features = plugins.where((p) => p.category == PluginCategory.feature).toList();
    final devices = plugins.where((p) => p.category == PluginCategory.device).toList();

    return Container(
      width: 240,
      color: const Color(0xFF080808),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF666666),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: selected ? const Color(0xFF1d2233) : Colors.transparent,
        child: Row(
          children: [
            Icon(plugin.icon,
                color: selected ? const Color(0xFF99EEBB) : Colors.white70,
                size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plugin.name,
                style: TextStyle(
                  color: selected ? const Color(0xFF99EEBB) : Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
            if (plugin.isCommunity)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('community',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 9)),
              ),
          ],
        ),
      ),
    );
  }
}
