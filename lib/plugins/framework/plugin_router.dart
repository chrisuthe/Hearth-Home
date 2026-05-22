import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/hub_config.dart';

/// Wraps an incoming HTTP request for a plugin route. Plugin handlers
/// receive this instead of the raw [HttpRequest] so they get pre-decoded
/// body, config access, and uniform response helpers.
class PluginRequest {
  /// The raw HttpRequest for advanced cases (streaming, custom headers).
  final HttpRequest raw;

  /// Pre-decoded JSON body. Empty map for GET requests or empty POST bodies.
  final Map<String, dynamic> body;

  /// Current config snapshot.
  final HubConfig config;

  PluginRequest({
    required this.raw,
    required this.body,
    required this.config,
  });

  /// Write a JSON response with the given object as the body.
  Future<void> respondJson(Object data) async {
    raw.response.statusCode = 200;
    raw.response.headers.contentType = ContentType.json;
    raw.response.write(jsonEncode(data));
    await raw.response.close();
  }

  /// Write an error response with the given status and message.
  Future<void> respondError(int status, String message) async {
    raw.response.statusCode = status;
    raw.response.headers.contentType = ContentType.json;
    raw.response.write(jsonEncode({'error': message}));
    await raw.response.close();
  }
}

/// Signature plugins implement for HTTP handlers.
typedef PluginRouteHandler = Future<void> Function(PluginRequest req);

/// HTTP router that scopes plugin routes under `/api/plugin/<id>/...`.
///
/// Plugins call [register] with their ID before registering routes; the
/// router prepends the prefix automatically. [resolve] performs path
/// matching against registered routes; LocalApiServer integrates this
/// in its request dispatch (see Task 13).
class PluginRouter {
  /// Map of (method, full-path) -> handler. Full paths are
  /// `/api/plugin/<id>/<suffix>`.
  final Map<_RouteKey, PluginRouteHandler> _routes = {};

  /// Currently-registering plugin ID. Set by [register]; used by
  /// [get]/[post] to construct the full path.
  String? _currentPluginId;

  /// Mark the start of route registration for the given plugin ID.
  /// Subsequent calls to [get]/[post] scope under this prefix until
  /// [register] is called again or this router is disposed.
  void register(String pluginId) {
    _currentPluginId = pluginId;
  }

  /// Register a GET handler at `/api/plugin/<current-id>/<path>`.
  void get(String path, PluginRouteHandler handler) {
    final id = _currentPluginId;
    if (id == null) {
      throw StateError('Call register(pluginId) before adding routes');
    }
    _routes[_RouteKey('GET', '/api/plugin/$id/$path')] = handler;
  }

  /// Register a POST handler at `/api/plugin/<current-id>/<path>`.
  void post(String path, PluginRouteHandler handler) {
    final id = _currentPluginId;
    if (id == null) {
      throw StateError('Call register(pluginId) before adding routes');
    }
    _routes[_RouteKey('POST', '/api/plugin/$id/$path')] = handler;
  }

  /// Resolve a request to its handler, or null if no route matches.
  PluginRouteHandler? resolve(String method, String path) {
    return _routes[_RouteKey(method, path)];
  }

  /// All registered route paths, for debugging.
  Iterable<String> get registeredRoutes =>
      _routes.keys.map((k) => '${k.method} ${k.path}');
}

class _RouteKey {
  final String method;
  final String path;
  _RouteKey(this.method, this.path);

  @override
  bool operator ==(Object other) =>
      other is _RouteKey && other.method == method && other.path == path;

  @override
  int get hashCode => Object.hash(method, path);
}
