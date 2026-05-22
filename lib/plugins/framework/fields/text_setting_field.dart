import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';
import 'setting_field.dart';

/// Plain text input. Maps 1:1 to a string field on HubConfig via configPath.
///
/// Writes are debounced (300 ms) before persisting via
/// `hubConfigProvider.notifier.update`. Validation is optional and runs
/// on every keystroke; an error string returned from [validate] disables
/// the save and shows the message under the field.
class TextSettingField extends SettingField<String> {
  /// Optional validator. Return null when value is valid, error message
  /// otherwise.
  final String? Function(String value)? validate;

  const TextSettingField({
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
          'TextSettingField "$label" has no configPath and no writeValue override');
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
    return _TextFieldRow(
      field: this,
      initialValue: current,
    );
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
  <input type="text"
         class="hearth-field"
         data-config-path="${configPath ?? ''}"
         value="$escaped"
         $placeholder>
</div>
''';
  }
}

class _TextFieldRow extends ConsumerStatefulWidget {
  final TextSettingField field;
  final String initialValue;
  const _TextFieldRow({required this.field, required this.initialValue});

  @override
  ConsumerState<_TextFieldRow> createState() => _TextFieldRowState();
}

class _TextFieldRowState extends ConsumerState<_TextFieldRow> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String? _error;

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
