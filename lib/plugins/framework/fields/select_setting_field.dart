import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';
import 'setting_field.dart';

/// Dropdown selection field. Maps 1:1 to a string field on HubConfig via
/// configPath by default, but accepts optional [readOverride] /
/// [writeOverride] callbacks for plugins that need custom mapping logic.
///
/// Options are a `Map<String, String>` of wire-value -> display label. The
/// current selection is the key.
class SelectSettingField extends SettingField<String> {
  /// Map of wire-value -> display label.
  final Map<String, String> options;
  final IconData? icon;

  /// Custom read override (takes precedence over configPath).
  final String Function(HubConfig)? readOverride;

  /// Custom write override (takes precedence over configPath behavior).
  final Future<void> Function(WidgetRef ref, String value)? writeOverride;

  const SelectSettingField({
    required super.label,
    super.hint,
    super.configPath,
    required this.options,
    this.icon,
    this.readOverride,
    this.writeOverride,
  });

  @override
  String? readValue(HubConfig config) {
    if (readOverride != null) return readOverride!(config);
    return super.readValue(config);
  }

  @override
  Future<void> writeValue(WidgetRef ref, String value) async {
    if (writeOverride != null) {
      await writeOverride!(ref, value);
      return;
    }
    final path = configPath;
    if (path == null) {
      throw StateError(
          'SelectSettingField "$label" has no configPath and no writeOverride');
    }
    final notifier = ref.read(hubConfigProvider.notifier);
    await notifier.update((c) {
      return HubConfig.fromJson({...c.toJson(), path: value});
    });
  }

  @override
  Widget buildWidget(WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final current = readValue(config) ?? options.keys.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161618),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: current,
                isExpanded: true,
                dropdownColor: const Color(0xFF1a1a1a),
                style: const TextStyle(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                items: options.entries.map((e) {
                  return DropdownMenuItem(
                      value: e.key, child: Text(e.value));
                }).toList(),
                onChanged: (v) {
                  if (v != null) writeValue(ref, v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  String buildHtml(WebContext ctx) {
    final config = ctx.config;
    final current = readValue(config) ?? options.keys.first;
    final optionsHtml = options.entries.map((e) {
      final selected = e.key == current ? 'selected' : '';
      return '<option value="${_escapeHtml(e.key)}" $selected>${_escapeHtml(e.value)}</option>';
    }).join('\n');
    return '''
<div class="field">
  <label>${_escapeHtml(label)}</label>
  <select class="hearth-field"
          data-config-path="${configPath ?? ''}"
          style="width:100%;padding:10px 12px;background:#161618;border:1px solid #333;border-radius:6px;color:#e0e0e0;font-size:14px;outline:none">
    $optionsHtml
  </select>
</div>
''';
  }
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
