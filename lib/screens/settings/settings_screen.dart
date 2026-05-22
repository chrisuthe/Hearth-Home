import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../plugins/hearth_plugin.dart';
import '../../plugins/plugin_registry.dart';
import '../../plugins/framework/plugin_sidebar.dart';
import '../../plugins/framework/plugin_panel.dart';

/// Settings screen — sidebar of registered plugins on the left, the selected
/// plugin's panel on the right. Each plugin owns its own fields and persists
/// changes via [HubConfigNotifier.update]; there's no global save button.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final plugins = ref.watch(allPluginsProvider);
    final selectedId = _selectedId ?? (plugins.isNotEmpty ? plugins.first.id : '');
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PluginSidebar(
            selectedId: selectedId,
            onSelected: (id) => setState(() => _selectedId = id),
          ),
          Expanded(child: _buildSelectedPanel(plugins, selectedId)),
        ],
      ),
    );
  }

  Widget _buildSelectedPanel(List<HearthPlugin> plugins, String selectedId) {
    if (plugins.isEmpty) return const SizedBox.shrink();
    HearthPlugin plugin = plugins.first;
    for (final p in plugins) {
      if (p.id == selectedId) {
        plugin = p;
        break;
      }
    }
    return PluginPanel(plugin: plugin);
  }
}
