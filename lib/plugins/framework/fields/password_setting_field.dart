import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';
import 'setting_field.dart';

/// Password / token input. Maps 1:1 to a string field on HubConfig via
/// configPath. Same auto-save semantics as [TextSettingField] but renders
/// obscured by default with a visibility-toggle button.
class PasswordSettingField extends SettingField<String> {
  /// Optional validator. Returns null when valid, error message otherwise.
  final String? Function(String value)? validate;

  const PasswordSettingField({
    required super.label,
    super.hint,
    super.configPath,
    this.validate,
  });

  @override
  Future<void> writeValue(WidgetRef ref, String value) async {
    final path = configPath;
    if (path == null) {
      throw StateError(
          'PasswordSettingField "$label" has no configPath and no writeValue override');
    }
    final notifier = ref.read(hubConfigProvider.notifier);
    await notifier.update((c) {
      return HubConfig.fromJson({...c.toJson(), path: value});
    });
  }

  @override
  Widget buildWidget(WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final current = readValue(config) ?? '';
    return _PasswordFieldRow(field: this, initialValue: current);
  }

  @override
  String buildHtml(WebContext ctx) {
    final current = readValue(ctx.config) ?? '';
    final escaped = _escapeHtml(current);
    final escapedHint = hint == null ? '' : _escapeHtml(hint!);
    final placeholder = hint == null ? '' : 'placeholder="$escapedHint"';
    return '''
<div class="field">
  <label>${_escapeHtml(label)}</label>
  <div class="secret-wrap" style="position:relative">
    <input type="password"
           class="hearth-field"
           data-config-path="${configPath ?? ''}"
           value="$escaped"
           $placeholder>
    <button type="button" class="toggle-vis"
            style="position:absolute;right:8px;top:8px;background:transparent;border:none;cursor:pointer;color:#888;font-size:16px"
            onclick="(function(b){var i=b.previousElementSibling;i.type=i.type==='password'?'text':'password';})(this)">&#x1f441;</button>
  </div>
</div>
''';
  }
}

class _PasswordFieldRow extends ConsumerStatefulWidget {
  final PasswordSettingField field;
  final String initialValue;
  const _PasswordFieldRow({required this.field, required this.initialValue});

  @override
  ConsumerState<_PasswordFieldRow> createState() => _PasswordFieldRowState();
}

class _PasswordFieldRowState extends ConsumerState<_PasswordFieldRow> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String? _error;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final validator = widget.field.validate;
    final err = validator?.call(value);
    setState(() => _error = err);
    if (err != null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.field.writeValue(ref, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.field.label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            obscureText: _obscured,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: widget.field.hint,
              hintStyle: const TextStyle(color: Colors.white38),
              errorText: _error,
              filled: true,
              fillColor: const Color(0xFF161618),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
            onChanged: _onChanged,
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
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
