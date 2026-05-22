import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../services/local_api_server.dart';
import 'wifi_settings.dart';
import 'photo_sources_section.dart';
import 'update_settings.dart';
import '../../modules/hearth_module.dart';
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
        // ── 1. Screens ──────────────────────────────────────────────
        const _SectionHeader(
          title: 'Screens',
          description: 'Manage screens and their order',
        ),
        const SizedBox(height: HearthSpacing.x2),
        ...allModules.where((m) => !m.isCommunity).map(
            (module) => _modulePlacementTile(module, config)),
        if (allModules.any((m) => m.isCommunity)) ...[
          const SizedBox(height: HearthSpacing.x4),
          const _ServiceSubHeader(title: 'Community Contributed'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
            child: Text(
              'Modules contributed by the community. Disabled by default — enable at your own discretion.',
              style: TextStyle(color: Colors.white54, fontSize: HearthFont.caption),
            ),
          ),
          const SizedBox(height: HearthSpacing.x1),
          ...allModules.where((m) => m.isCommunity).map(
              (module) => _modulePlacementTile(module, config)),
        ],
        const SizedBox(height: HearthSpacing.x3),
        _ModuleReorderList(
          config: config,
          modules: allModules,
          onReorder: (newOrder) =>
              _updateConfig((c) => c.copyWith(moduleOrder: newOrder)),
          onReset: () =>
              _updateConfig((c) => c.copyWith(moduleOrder: const [])),
        ),

        const SizedBox(height: HearthSpacing.x6),

        // ── 2. Services ─────────────────────────────────────────────
        const _SectionHeader(
          title: 'Services',
          description: 'Connect to your smart home services',
        ),
        const SizedBox(height: HearthSpacing.x2),

        // -- Immich Photo Sources --
        // Connection settings live in the new Immich plugin. The album /
        // photo-source picker below is a bespoke widget that stays here
        // for now and will migrate later as a custom widget contribution.
        const _ServiceSubHeader(title: 'Immich Photo Sources'),
        const PhotoSourcesSection(),

        const SizedBox(height: HearthSpacing.x6),

        // ── 6. Network & Access ─────────────────────────────────────
        const _SectionHeader(
          title: 'Network & Access',
          description: 'WiFi and web portal',
        ),
        const SizedBox(height: HearthSpacing.x2),
        const WifiSettingsSection(),
        _SettingsTile(
          icon: Icons.pin,
          title: 'Web Portal PIN',
          subtitle: ref.watch(webPinProvider),
          onTap: () {},
        ),

        const SizedBox(height: HearthSpacing.x6),

        // ── 7. System ───────────────────────────────────────────────
        const _SectionHeader(
          title: 'System',
          description: 'Updates and maintenance',
        ),
        const SizedBox(height: HearthSpacing.x2),
        const UpdateSettingsSection(),

        const SizedBox(height: HearthSpacing.x6),

        // Per-module settings (only shown when module is enabled).
        ...allModules
            .where((m) => config.enabledModules.contains(m.id))
            .map((m) => m.buildSettingsSection())
            .whereType<Widget>(),
      ],
    );
  }

  Widget _modulePlacementTile(HearthModule module, HubConfig config) {
    final placements = List<String>.from(
        config.modulePlacements[module.id] ?? []);
    return ListTile(
      leading: Icon(module.icon, color: Colors.white54),
      title: Text(module.name),
      subtitle: Wrap(
        spacing: 6,
        children: [
          for (final placement in ['swipe', 'menu1', 'menu2'])
            FilterChip(
              label: Text(
                placement == 'swipe' ? 'Swipe' :
                placement == 'menu1' ? 'Menu 1' : 'Menu 2',
                style: const TextStyle(fontSize: HearthFont.caption),
              ),
              selected: placements.contains(placement),
              onSelected: (selected) {
                final updated = Map<String, List<String>>.from(
                    config.modulePlacements);
                final list = List<String>.from(updated[module.id] ?? []);
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
                _updateConfig((c) => c.copyWith(modulePlacements: updated));
              },
              selectedColor: const Color(0xFF646CFF),
              backgroundColor: const Color(0xFF1E1E1E),
              labelStyle: TextStyle(
                color: placements.contains(placement)
                    ? Colors.white : Colors.white70,
                fontSize: HearthFont.caption,
              ),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }

  /// Persists a config change immediately -- no save button needed.
  Future<void> _updateConfig(HubConfig Function(HubConfig) updater) async {
    await ref.read(hubConfigProvider.notifier).update(updater);
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

/// Sub-header for grouping settings within a section (e.g., per-service).
class _ServiceSubHeader extends StatelessWidget {
  final String title;
  const _ServiceSubHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: HearthSpacing.x2, top: HearthSpacing.x3, bottom: HearthSpacing.x1),
      child: Text(
        title,
        style: TextStyle(
          fontSize: HearthFont.caption,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Individual settings row with icon, title, subtitle, and tap action.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white54, size: HearthIcon.md),
      title: Text(title, style: const TextStyle(fontSize: HearthFont.body)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: HearthFont.label,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }
}

/// Reorderable list for customizing screen order in the PageView.
class _ModuleReorderList extends StatefulWidget {
  final HubConfig config;
  final List<HearthModule> modules;
  final ValueChanged<List<String>> onReorder;
  final VoidCallback onReset;

  const _ModuleReorderList({
    required this.config,
    required this.modules,
    required this.onReorder,
    required this.onReset,
  });

  @override
  State<_ModuleReorderList> createState() => _ModuleReorderListState();
}

class _ModuleReorderListState extends State<_ModuleReorderList> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = _buildOrder();
  }

  @override
  void didUpdateWidget(_ModuleReorderList old) {
    super.didUpdateWidget(old);
    if (old.config.enabledModules != widget.config.enabledModules ||
        old.config.moduleOrder != widget.config.moduleOrder ||
        old.modules != widget.modules) {
      _order = _buildOrder();
    }
  }

  /// Build the display order list from config.
  /// If moduleOrder is set, use it (filtered to enabled modules).
  /// Otherwise, sort enabled modules by defaultOrder.
  List<String> _buildOrder() {
    final enabledIds = widget.config.enabledModules;
    final enabled = widget.modules.where((m) => enabledIds.contains(m.id)).toList();

    if (widget.config.moduleOrder.isNotEmpty) {
      // Start with modules in the custom order that are still enabled.
      final ordered = widget.config.moduleOrder
          .where((id) => enabledIds.contains(id))
          .toList();
      // Add any newly enabled modules not yet in the order.
      for (final m in enabled) {
        if (!ordered.contains(m.id)) ordered.add(m.id);
      }
      return ordered;
    }

    // Default order: sort by defaultOrder, left-of-home first.
    enabled.sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
    return enabled.map((m) => m.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isEmpty) return const SizedBox.shrink();

    final hasCustomOrder = widget.config.moduleOrder.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: HearthSpacing.x2, bottom: HearthSpacing.x1),
          child: Row(
            children: [
              Text(
                'Screen Order',
                style: TextStyle(
                  fontSize: HearthFont.caption,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              if (hasCustomOrder)
                GestureDetector(
                  onTap: widget.onReset,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: HearthSpacing.x2, vertical: HearthSpacing.x3),
                    child: Text(
                      'Reset to Default',
                      style: TextStyle(
                        fontSize: HearthFont.caption,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            proxyDecorator: (child, index, animation) {
              return Material(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                elevation: 4,
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _order.removeAt(oldIndex);
                _order.insert(newIndex, item);
              });
              widget.onReorder(List<String>.from(_order));
            },
            itemBuilder: (context, index) {
              final moduleId = _order[index];
              final module = widget.modules.firstWhere((m) => m.id == moduleId);
              return ListTile(
                key: ValueKey(moduleId),
                dense: true,
                leading: Icon(module.icon, color: Colors.white38, size: HearthIcon.sm),
                title: Text(
                  module.name,
                  style: const TextStyle(fontSize: HearthFont.body),
                ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle, color: Colors.white24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3),
              );
            },
          ),
        ),
      ],
    );
  }
}


