import 'package:flutter/material.dart';

import '../app/tokens/tokens.dart';
import '../config/hub_config.dart';
import '../modules/hearth_module.dart';

/// Reorderable list for customizing screen order in the PageView.
///
/// Used by the Screens & Order plugin. Originally a private
/// `_ModuleReorderList` widget inside `settings_screen.dart`.
class ModuleReorderList extends StatefulWidget {
  final HubConfig config;
  final List<HearthModule> modules;
  final ValueChanged<List<String>> onReorder;
  final VoidCallback onReset;

  const ModuleReorderList({
    super.key,
    required this.config,
    required this.modules,
    required this.onReorder,
    required this.onReset,
  });

  @override
  State<ModuleReorderList> createState() => _ModuleReorderListState();
}

class _ModuleReorderListState extends State<ModuleReorderList> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = _buildOrder();
  }

  @override
  void didUpdateWidget(ModuleReorderList old) {
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
    final enabled =
        widget.modules.where((m) => enabledIds.contains(m.id)).toList();

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
          padding: const EdgeInsets.only(
              left: HearthSpacing.x2, bottom: HearthSpacing.x1),
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
                        horizontal: HearthSpacing.x2,
                        vertical: HearthSpacing.x3),
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
              final module =
                  widget.modules.firstWhere((m) => m.id == moduleId);
              return ListTile(
                key: ValueKey(moduleId),
                dense: true,
                leading: Icon(module.icon,
                    color: Colors.white38, size: HearthIcon.sm),
                title: Text(
                  module.name,
                  style: const TextStyle(fontSize: HearthFont.body),
                ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child:
                      const Icon(Icons.drag_handle, color: Colors.white24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.x3),
              );
            },
          ),
        ),
      ],
    );
  }
}
