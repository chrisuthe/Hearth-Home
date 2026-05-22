import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../modules/module_registry.dart';
import '../../app/tokens/tokens.dart';
import '../../plugins/hearth_plugin.dart';
import '../../plugins/plugin_registry.dart';
import '../../plugins/framework/plugin_sidebar.dart';
import '../../plugins/framework/plugin_panel.dart';

/// Settings screen -- configure connections, display, night mode, and music.
///
/// All changes persist immediately via [HubConfigNotifier.update], so there's
/// no "save" button. Each setting opens an appropriate dialog (text input,
/// slider, or choice picker) to keep the main screen scannable.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _selectedId = 'hearth.weather';

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PluginSidebar(
            selectedId: _selectedId,
            onSelected: (id) => setState(() => _selectedId = id),
          ),
          Expanded(child: _buildSelectedPanel(config)),
        ],
      ),
    );
  }

  Widget _buildSelectedPanel(HubConfig config) {
    if (_selectedId == 'legacy') {
      return _buildLegacyPanel(config);
    }
    final plugins = ref.read(allPluginsProvider);
    HearthPlugin? plugin;
    for (final p in plugins) {
      if (p.id == _selectedId) {
        plugin = p;
        break;
      }
    }
    if (plugin == null && plugins.isNotEmpty) {
      plugin = plugins.first;
    }
    if (plugin == null) {
      return _buildLegacyPanel(config);
    }
    return PluginPanel(plugin: plugin);
  }

  Widget _buildLegacyPanel(HubConfig config) {
    final allModules = ref.watch(allModulesProvider);
    return ListView(
      padding: HearthSpacing.allX6,
      children: [
        // ── Services ────────────────────────────────────────────────
        const _SectionHeader(
          title: 'Services',
          description: 'Connect to your smart home services',
        ),
        const SizedBox(height: HearthSpacing.x2),

        // Per-module settings (only shown when module is enabled).
        ...allModules
            .where((m) => config.enabledModules.contains(m.id))
            .map((m) => m.buildSettingsSection())
            .whereType<Widget>(),
      ],
    );
  }
}

/// Section header used to visually group related settings.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? description;
  const _SectionHeader({required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 1.2,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(
              fontSize: HearthFont.caption,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

