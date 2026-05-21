import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../config/webview_config.dart';

class CustomUrlList extends ConsumerWidget {
  const CustomUrlList({super.key});

  String _newId() {
    final n = Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return 'webview:custom:$n';
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, {WebviewConfig? existing}) async {
    final result = await showDialog<_EditorResult>(
      context: context,
      builder: (_) => _UrlEditorDialog(existing: existing),
    );
    if (result == null) return;
    final notifier = ref.read(hubConfigProvider.notifier);
    if (existing == null) {
      // Add new
      final config = WebviewConfig(
        id: _newId(),
        url: result.url,
        name: result.name,
        iconCodePoint: result.icon.codePoint,
        source: WebviewSource.customUrl,
        order: ref.read(hubConfigProvider).webviews.length,
      );
      notifier.update((c) => c.copyWith(webviews: [...c.webviews, config]));
    } else {
      // Edit existing
      notifier.update((c) => c.copyWith(
        webviews: c.webviews.map((w) {
          if (w.id != existing.id) return w;
          return w.copyWith(
            url: result.url,
            name: result.name,
            iconCodePoint: result.icon.codePoint,
          );
        }).toList(),
      ));
    }
  }

  void _remove(WidgetRef ref, WebviewConfig config) {
    final notifier = ref.read(hubConfigProvider.notifier);
    notifier.update((c) => c.copyWith(
      webviews: c.webviews.where((w) => w.id != config.id).toList(),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final customs = config.webviews
        .where((w) => w.source == WebviewSource.customUrl)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.link, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            const Text('Custom URLs',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, color: Color(0xFF646CFF)),
              label: const Text('Add', style: TextStyle(color: Color(0xFF646CFF))),
              onPressed: () => _showEditor(context, ref),
            ),
          ],
        ),
        if (customs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No custom URLs yet.',
                style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
          )
        else
          Column(
            children: customs.map((c) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.icon, color: Colors.white70),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(c.url,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54),
                      onPressed: () => _showEditor(context, ref, existing: c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _remove(ref, c),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _EditorResult {
  final String url;
  final String name;
  final IconData icon;
  _EditorResult({required this.url, required this.name, required this.icon});
}

class _UrlEditorDialog extends StatefulWidget {
  final WebviewConfig? existing;
  const _UrlEditorDialog({this.existing});

  @override
  State<_UrlEditorDialog> createState() => _UrlEditorDialogState();
}

class _UrlEditorDialogState extends State<_UrlEditorDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _nameCtrl;
  late IconData _icon;

  static const _availableIcons = [
    Icons.dashboard,
    Icons.web,
    Icons.analytics,
    Icons.show_chart,
    Icons.electrical_services,
    Icons.shopping_cart,
    Icons.print,
    Icons.cloud,
    Icons.security,
    Icons.thermostat,
  ];

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.existing?.url ?? '');
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _icon = widget.existing?.icon ?? Icons.web;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(isEdit ? 'Edit webview' : 'Add webview',
          style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://…',
                labelStyle: TextStyle(color: Colors.white54),
                hintStyle: TextStyle(color: Colors.white24),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Icon', style: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableIcons.map((i) {
                final selected = i.codePoint == _icon.codePoint;
                return GestureDetector(
                  onTap: () => setState(() => _icon = i),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF646CFF).withValues(alpha: 0.3) : Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      border: selected ? Border.all(color: const Color(0xFF646CFF)) : null,
                    ),
                    child: Icon(i, color: Colors.white),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF646CFF)),
          onPressed: () {
            final url = _urlCtrl.text.trim();
            final name = _nameCtrl.text.trim();
            if (url.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop(_EditorResult(url: url, name: name, icon: _icon));
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
