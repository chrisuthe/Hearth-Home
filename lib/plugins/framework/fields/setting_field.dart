import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/hub_config.dart';
import '../web_context.dart';

/// Base class for all setting fields rendered inside a plugin panel.
///
/// Each subclass renders surface-natively (Flutter widget on-device, HTML
/// fragment on web) and handles its own read/write against the HubConfig.
///
/// Implementations must either provide a [configPath] (sugar for reading
/// the named field via [HubConfig.toJson]) OR override [readValue] and
/// [writeValue] for non-trivial mappings.
abstract class SettingField<T> {
  /// User-facing label shown above the field.
  final String label;

  /// Optional hint text / placeholder.
  final String? hint;

  /// Optional path into [HubConfig.toJson]'s output. When set, the framework
  /// reads via reflection. Subclasses can override [readValue] / [writeValue]
  /// for fields with custom mapping.
  final String? configPath;

  const SettingField({required this.label, this.hint, this.configPath});

  /// Read the current value of this field from [config].
  ///
  /// Default implementation looks up [configPath] in `config.toJson()`.
  /// Subclasses with custom storage override this.
  T? readValue(HubConfig config) {
    final path = configPath;
    if (path == null) {
      throw StateError(
          'SettingField "$label" has no configPath and no readValue override');
    }
    final json = config.toJson();
    return json[path] as T?;
  }

  /// Persist a new [value] for this field.
  ///
  /// Subclasses with custom storage override this; subclasses using
  /// [configPath] sugar implement this by calling
  /// `hubConfigProvider.notifier.update(...)` to write the field back.
  Future<void> writeValue(WidgetRef ref, T value);

  /// Render the field as a Flutter widget. Reads current value from
  /// [hubConfigProvider] internally.
  Widget buildWidget(WidgetRef ref);

  /// Render the field as an HTML fragment.
  String buildHtml(WebContext ctx);
}
