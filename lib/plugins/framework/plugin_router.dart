import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';

/// Reads a provider's current value. Mirrors `Ref.read` / `WidgetRef.read`
/// so production code can pass `ref.read` straight through (a generic
/// function tearoff) and routes reach any service singleton.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Wraps an incoming HTTP request for a plugin route. Plugin handlers
/// receive this instead of the raw [HttpRequest] so they get pre-decoded
/// body, config read/write access, service-provider access, and uniform
/// response helpers.
class PluginRequest {
  /// The raw HttpRequest for advanced cases (streaming, custom headers).
  final HttpRequest raw;

  /// Pre-decoded JSON body. Empty map for GET requests or empty POST bodies.
  final Map<String, dynamic> body;

  /// Current config snapshot. For writes use [updateConfig].
  final HubConfig config;

  /// Notifier for persisting config changes. Most routes should prefer the
  /// [updateConfig] convenience over poking the notifier directly.
  final HubConfigNotifier configNotifier;

  /// Values of the route's `:name` path segments.
  final Map<String, String> pathParams;

  /// Scoped provider reader (production wires `ref.read`). Null when no
  /// reader was supplied, in which case [readProvider] throws.
  final ProviderReader? _readProvider;

  PluginRequest({
    required this.raw,
    required this.body,
    required this.config,
    required this.configNotifier,
    this.pathParams = const {},
    ProviderReader? readProvider,
  }) : _readProvider = readProvider;

  /// Persist a config change. Delegates to [HubConfigNotifier.update], so
  /// the new config is written to disk and pushed to listeners exactly as
  /// an on-device settings change would be.
  Future<void> updateConfig(HubConfig Function(HubConfig) updater) =>
      configNotifier.update(updater);

  /// Read a service provider (HA, Immich, AlarmService, ...). Throws a
  /// [StateError] when no reader was wired into this request — that only
  /// happens for [LocalApiServer] constructions made without a Riverpod
  /// `ref` (e.g. some unit tests), never in production.
  T readProvider<T>(ProviderListenable<T> provider) {
    final reader = _readProvider;
    if (reader == null) {
      throw StateError(
        'No provider reader wired into this PluginRequest. Construct '
        'LocalApiServer with a readProvider (ref.read) so plugin routes '
        'can reach service providers.',
      );
    }
    return reader(provider);
  }

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

  /// Register a GET handler at `/api/plugin/<current-id>/<path>`. A path
  /// segment written `:name` matches any one segment, handed to the handler
  /// as `pathParams['name']`.
  void get(String path, PluginRouteHandler handler) =>
      _add('GET', path, handler);

  /// Register a POST handler at `/api/plugin/<current-id>/<path>`.
  void post(String path, PluginRouteHandler handler) =>
      _add('POST', path, handler);

  /// Register a PUT handler at `/api/plugin/<current-id>/<path>`.
  void put(String path, PluginRouteHandler handler) =>
      _add('PUT', path, handler);

  /// Register a DELETE handler at `/api/plugin/<current-id>/<path>`.
  void delete(String path, PluginRouteHandler handler) =>
      _add('DELETE', path, handler);

  void _add(String method, String path, PluginRouteHandler handler) {
    final id = _currentPluginId;
    if (id == null) {
      throw StateError('Call register(pluginId) before adding routes');
    }
    _routes[_RouteKey(method, '/api/plugin/$id/$path')] = handler;
  }

  /// Resolve a request to its handler, or null if no route matches.
  PluginRouteHandler? resolve(String method, String path) =>
      match(method, path)?.handler;

  /// Resolve a request to its handler and the values of its `:name`
  /// segments, or null if no route matches. An exact route wins.
  ({PluginRouteHandler handler, Map<String, String> params})? match(
      String method, String path) {
    final exact = _routes[_RouteKey(method, path)];
    if (exact != null) return (handler: exact, params: const {});
    final segments = path.split('/');
    for (final entry in _routes.entries) {
      final key = entry.key;
      if (key.method != method || !key.path.contains('/:')) continue;
      final pattern = key.path.split('/');
      if (pattern.length != segments.length) continue;
      final params = <String, String>{};
      var ok = true;
      for (var i = 0; i < pattern.length && ok; i++) {
        if (pattern[i].startsWith(':')) {
          if (segments[i].isEmpty) {
            ok = false;
          } else {
            params[pattern[i].substring(1)] =
                Uri.decodeComponent(segments[i]);
          }
        } else {
          ok = pattern[i] == segments[i];
        }
      }
      if (ok) return (handler: entry.value, params: params);
    }
    return null;
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
