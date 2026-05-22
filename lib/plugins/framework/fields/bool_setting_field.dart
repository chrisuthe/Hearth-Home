import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';
import 'setting_field.dart';

/// On/off toggle field. Maps 1:1 to a bool field on HubConfig via configPath
/// by default, but accepts optional [readOverride] / [writeOverride] callbacks
/// for plugins that need side-effect logic on write (e.g. generating a
/// clientId on first enable).
///
/// Flutter rendering uses a [SwitchListTile] with icon + label + subtitle.
/// HTML rendering emits a styled `<input type="checkbox">` that the auto-save
/// helper in `hearth.js` binds to via `data-config-path`.
class BoolSettingField extends SettingField<bool> {
  final IconData? icon;
  final String? subtitle;

  /// Optional disabled-state callback. Returns null when the field is enabled,
  /// or a string explaining why it's disabled (shown as subtitle).
  final String? Function(HubConfig)? disabledReason;

  /// Custom read override (takes precedence over configPath).
  final bool Function(HubConfig)? readOverride;

  /// Custom write override (takes precedence over configPath behavior).
  final Future<void> Function(WidgetRef ref, bool value)? writeOverride;

  const BoolSettingField({
    required super.label,
    super.hint,
    super.configPath,
    this.icon,
    this.subtitle,
    this.disabledReason,
    this.readOverride,
    this.writeOverride,
  });

  @override
  bool? readValue(HubConfig config) {
    if (readOverride != null) return readOverride!(config);
    return super.readValue(config);
  }

  @override
  Future<void> writeValue(WidgetRef ref, bool value) async {
    if (writeOverride != null) {
      await writeOverride!(ref, value);
      return;
    }
    final path = configPath;
    if (path == null) {
      throw StateError(
          'BoolSettingField "$label" has no configPath and no writeOverride');
    }
    final notifier = ref.read(hubConfigProvider.notifier);
    await notifier.update((c) {
      return HubConfig.fromJson({...c.toJson(), path: value});
    });
  }

  @override
  Widget buildWidget(WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final value = readValue(config) ?? false;
    final disabled = disabledReason?.call(config);
    return SwitchListTile(
      secondary: icon != null ? Icon(icon, color: Colors.white54) : null,
      title: Text(label),
      subtitle: Text(
        disabled ?? subtitle ?? (value ? 'Enabled' : 'Disabled'),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      value: value,
      onChanged: disabled != null ? null : (v) => writeValue(ref, v),
    );
  }

  @override
  String buildHtml(WebContext ctx) {
    final config = ctx.config;
    final value = readValue(config) ?? false;
    final checked = value ? 'checked' : '';
    final disabled = disabledReason?.call(config);
    final disabledAttr = disabled != null ? 'disabled' : '';
    final subtitleText = disabled ?? subtitle ?? '';
    final escapedLabel = _escapeHtml(label);
    final escapedSubtitle = subtitleText.isEmpty
        ? ''
        : '<div class="field-subtitle" style="font-size:11px;color:#888;margin-top:4px">${_escapeHtml(subtitleText)}</div>';
    return '''
<div class="field">
  <label class="checkbox-label" style="display:flex;align-items:center;gap:8px">
    <input type="checkbox"
           class="hearth-field"
           data-config-path="${configPath ?? ''}"
           $checked
           $disabledAttr>
    <span>$escapedLabel</span>
  </label>
  $escapedSubtitle
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
