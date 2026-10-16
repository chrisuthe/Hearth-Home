import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearth_plugin.dart';
import '../../app/theme/hearth_colors.dart';

/// Renders a single plugin's settings panel: header (name, icon) plus the
/// plugin's `buildSettingsWidget` output.
///
/// Used by the sidebar layout to show the currently-selected plugin's UI.
class PluginPanel extends ConsumerWidget {
  final HearthPlugin plugin;

  const PluginPanel({super.key, required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(plugin.icon, color: c.textSecondary, size: 28),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  plugin.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w300),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          plugin.buildSettingsWidget(ref),
        ],
      ),
    );
  }
}
