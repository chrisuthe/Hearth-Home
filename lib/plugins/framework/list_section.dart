import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// N-entry list primitive: ADD button at the header, each row has summary
/// + edit + delete actions. Plugin owns the item type [T] and provides
/// callbacks for: rendering each row's summary, opening the editor
/// (returns a new T or null on cancel), and persisting the updated list.
///
/// Other variants (toggle list, picker list) are separate primitives.
///
/// **Web limitations:** for first ship the HTML render is read-only — items
/// appear as static rows. Add/edit/delete happens on-device. Plugins that
/// need interactive web editing can override their plugin's
/// `buildSettingsHtml` with a custom fragment that calls plugin HTTP
/// routes.
class ListSection<T> {
  /// Section label shown in the header (e.g. "Alarms", "Custom URLs").
  final String label;

  /// Current list of items, read from HubConfig.
  final List<T> items;

  /// Render the summary text for a list row given an item.
  final String Function(T item) summaryFor;

  /// Persist a new full list of items (write to HubConfig).
  final Future<void> Function(List<T> newList) onListChanged;

  /// Build the editor widget for adding a new item or editing an existing.
  /// Returns the new item or null on cancel. Receives the item being
  /// edited (null for "add new", or the pre-filled item from
  /// [newItemFactory] when supplied).
  final Future<T?> Function(BuildContext context, T? existing) editorBuilder;

  /// Optional initial-item factory for "add new" — used to pre-fill the
  /// editor with default values. If null, [editorBuilder] is invoked with
  /// `null` as the existing arg.
  final T Function()? newItemFactory;

  const ListSection({
    required this.label,
    required this.items,
    required this.summaryFor,
    required this.onListChanged,
    required this.editorBuilder,
    this.newItemFactory,
  });

  /// Render as a Flutter widget.
  Widget buildWidget(BuildContext context, WidgetRef ref) {
    return _ListSectionWidget<T>(section: this);
  }

  /// Render as an HTML fragment. Items appear as a static read-only list
  /// because the editor flow doesn't translate cleanly to a stateless HTML
  /// render. The plugin's web-side panel can override `buildSettingsHtml`
  /// with a more interactive UI if needed.
  String buildHtml() {
    final buf = StringBuffer();
    buf.writeln('<div class="field">');
    buf.writeln('  <label>${_escapeHtml(label)}</label>');
    if (items.isEmpty) {
      buf.writeln(
          '  <div class="hint" style="color:#888;font-style:italic">No items yet.</div>');
    } else {
      buf.writeln('  <ul style="list-style:none;padding:0;margin:0">');
      for (final item in items) {
        buf.writeln(
            '    <li style="padding:8px 12px;background:#161618;border-radius:6px;margin-bottom:4px">${_escapeHtml(summaryFor(item))}</li>');
      }
      buf.writeln('  </ul>');
    }
    buf.writeln(
        '  <div class="hint" style="font-size:11px;color:#666;margin-top:6px">Edit items from the on-device Settings screen.</div>');
    buf.writeln('</div>');
    return buf.toString();
  }
}

class _ListSectionWidget<T> extends ConsumerStatefulWidget {
  final ListSection<T> section;
  const _ListSectionWidget({required this.section});

  @override
  ConsumerState<_ListSectionWidget<T>> createState() =>
      _ListSectionWidgetState<T>();
}

class _ListSectionWidgetState<T> extends ConsumerState<_ListSectionWidget<T>> {
  Future<void> _addItem() async {
    final factory = widget.section.newItemFactory;
    final initial = factory != null ? factory() : null;
    final result = await widget.section.editorBuilder(context, initial);
    if (result == null) return;
    await widget.section.onListChanged([...widget.section.items, result]);
  }

  Future<void> _editItem(int index) async {
    final result = await widget.section
        .editorBuilder(context, widget.section.items[index]);
    if (result == null) return;
    final newList = [...widget.section.items];
    newList[index] = result;
    await widget.section.onListChanged(newList);
  }

  Future<void> _deleteItem(int index) async {
    final newList = [...widget.section.items]..removeAt(index);
    await widget.section.onListChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.section.label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add,
                    color: Color(0xFF646cff), size: 16),
                label: const Text('Add',
                    style: TextStyle(color: Color(0xFF646cff))),
                onPressed: _addItem,
              ),
            ],
          ),
          if (widget.section.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No items yet.',
                style: TextStyle(
                  color: Colors.white54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            for (var i = 0; i < widget.section.items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.section.summaryFor(widget.section.items[i]),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54),
                      onPressed: () => _editItem(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      onPressed: () => _deleteItem(i),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
