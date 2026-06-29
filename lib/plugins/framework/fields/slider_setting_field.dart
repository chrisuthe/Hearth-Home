import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';
import 'setting_field.dart';

/// Numeric slider field. Renders a Flutter [Slider] on device and an
/// `<input type="range">` on the web portal.
///
/// Writes are debounced (300 ms) so a drag generates one config write at
/// the end rather than flooding [hubConfigProvider.notifier.update] on
/// every tick.
///
/// Reading: by default the field reads `configPath` from `HubConfig.toJson()`
/// and coerces to `num`. Override with [readOverride] for fields that need
/// custom mapping (e.g. clamping or scaling).
///
/// Writing: the slider hands a `double` to [writeOverride]. The default path
/// (no override) writes the raw `num` back via the JSON-merge pattern, which
/// works for `double` HubConfig fields but loses fidelity for `int` fields —
/// in that case supply [writeOverride] and round before persisting.
///
/// Web note: the portal posts the range value back as the raw `<input>`
/// string. The `/api/config` POST handler coerces each field to its declared
/// HubConfig type (see `_coerceConfigValue` in local_api_server.dart), so an
/// int or double field backed purely by [configPath] saves correctly from the
/// web with no [writeOverride] needed.
class SliderSettingField extends SettingField<num> {
  final double min;
  final double max;
  final int? divisions;

  /// Format the current value for display under the slider (e.g. "30s",
  /// "1.5x"). Default: '${value.round()}'.
  final String Function(double value)? labelBuilder;

  /// Multiplier applied to the raw slider value before the web portal's
  /// live-drag readout rounds it. The on-load / post-save readout uses
  /// [labelBuilder] (Dart), but mid-drag the browser updates the number with
  /// inline JS, which can't call [labelBuilder]. Set this (with
  /// [htmlDisplaySuffix]) so fractional fields read sensibly while dragging —
  /// e.g. uiScale uses scale 100, suffix '%' to show "125%" instead of "1".
  /// Default 1.0 leaves integer sliders (idle timeout, etc.) unchanged.
  final double htmlDisplayScale;

  /// Suffix appended to the web portal's live-drag readout. See
  /// [htmlDisplayScale]. Default '' (no suffix).
  final String htmlDisplaySuffix;

  /// Custom read override (takes precedence over configPath).
  final double Function(HubConfig)? readOverride;

  /// Custom write override (called with the slider's double value).
  final Future<void> Function(WidgetRef ref, double value)? writeOverride;

  const SliderSettingField({
    required super.label,
    super.hint,
    super.configPath,
    required this.min,
    required this.max,
    this.divisions,
    this.labelBuilder,
    this.htmlDisplayScale = 1.0,
    this.htmlDisplaySuffix = '',
    this.readOverride,
    this.writeOverride,
  });

  @override
  num? readValue(HubConfig config) {
    if (readOverride != null) return readOverride!(config);
    final path = configPath;
    if (path == null) return null;
    final json = config.toJson();
    final v = json[path];
    if (v is num) return v;
    return null;
  }

  @override
  Future<void> writeValue(WidgetRef ref, num value) async {
    if (writeOverride != null) {
      await writeOverride!(ref, value.toDouble());
      return;
    }
    final path = configPath;
    if (path == null) {
      throw StateError(
          'SliderSettingField "$label" has no configPath and no writeOverride');
    }
    final notifier = ref.read(hubConfigProvider.notifier);
    await notifier.update((c) {
      return HubConfig.fromJson({...c.toJson(), path: value});
    });
  }

  @override
  Widget buildWidget(WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final current = (readValue(config) ?? min).toDouble().clamp(min, max);
    return _SliderRow(field: this, initialValue: current);
  }

  @override
  String buildHtml(WebContext ctx) {
    final current = (readValue(ctx.config) ?? min).toDouble().clamp(min, max);
    final display = labelBuilder != null
        ? labelBuilder!(current)
        : current.round().toString();
    final step = divisions != null
        ? ((max - min) / divisions!).toString()
        : '1';
    return '''
<div class="field">
  <label>${_escapeHtml(label)}</label>
  <div style="display:flex;align-items:center;gap:12px">
    <input type="range"
           class="hearth-field"
           data-config-path="${configPath ?? ''}"
           min="$min"
           max="$max"
           step="$step"
           value="$current"
           style="flex:1"
           oninput="this.nextElementSibling.textContent=Math.round(this.value*$htmlDisplayScale)+'${_escapeHtml(htmlDisplaySuffix)}'">
    <span style="color:#aaa;font-size:13px;min-width:60px;text-align:right">${_escapeHtml(display)}</span>
  </div>
</div>
''';
  }
}

class _SliderRow extends ConsumerStatefulWidget {
  final SliderSettingField field;
  final double initialValue;
  const _SliderRow({required this.field, required this.initialValue});

  @override
  ConsumerState<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends ConsumerState<_SliderRow> {
  late double _value;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(double v) {
    setState(() => _value = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.field.writeValue(ref, v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.field.labelBuilder != null
        ? widget.field.labelBuilder!(_value)
        : _value.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.field.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Text(display,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          Slider(
            value: _value,
            min: widget.field.min,
            max: widget.field.max,
            divisions: widget.field.divisions,
            activeColor: const Color(0xFF646cff),
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
      .replaceAll('"', '&quot;');
}
