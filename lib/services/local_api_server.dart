import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'display_mode_service.dart';

/// Minimal HTTP server for external device control.
///
/// Runs on port 8090 by default. Only two endpoints:
///   POST /api/display-mode — set night/day mode from external devices
///   GET  /api/display-mode — query current mode
///
/// This lets HA automations or other devices on the network control
/// the hub's display without needing to go through the HA WebSocket.
class LocalApiServer {
  final DisplayModeService _displayModeService;
  HttpServer? _server;

  LocalApiServer({required DisplayModeService displayModeService})
      : _displayModeService = displayModeService;

  Future<int> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/display-mode') {
      if (request.method == 'POST') {
        await _handleSetDisplayMode(request);
      } else if (request.method == 'GET') {
        await _handleGetDisplayMode(request);
      } else {
        request.response.statusCode = 405;
        await request.response.close();
      }
    } else {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'not found'}));
      await request.response.close();
    }
  }

  Future<void> _handleSetDisplayMode(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modeStr = json['mode'] as String?;

    final mode = modeStr == 'night' ? DisplayMode.night : DisplayMode.day;
    _displayModeService.setModeFromApi(mode);

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': modeStr}));
    await request.response.close();
  }

  Future<void> _handleGetDisplayMode(HttpRequest request) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'mode': 'day'}));
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close();
  }
}

final localApiServerProvider = Provider<LocalApiServer>((ref) {
  final displayService = ref.watch(displayModeServiceProvider);
  return LocalApiServer(displayModeService: displayService);
});
