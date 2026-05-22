import '../../config/hub_config.dart';

/// Context passed to [HearthPlugin.buildSettingsHtml].
class WebContext {
  /// Current config snapshot the plugin uses to hydrate field values.
  final HubConfig config;

  /// Bearer token for `fetch()` Authorization headers from the rendered
  /// HTML's inline JavaScript.
  final String apiBearerToken;

  /// Path prefix the plugin's HTTP routes are exposed at — already includes
  /// the plugin ID. Plugins emit `hearth.action('foo')` and the helper
  /// concatenates with this prefix.
  final String pluginActionPrefix;

  const WebContext({
    required this.config,
    required this.apiBearerToken,
    required this.pluginActionPrefix,
  });
}
