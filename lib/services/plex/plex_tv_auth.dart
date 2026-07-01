import 'dart:convert';
import 'dart:io';

import '../../utils/logger.dart';
import 'plex_wire.dart';

/// A freshly-created plex.tv PIN: its [id] (used to poll) and the 4-char [code]
/// the user types at plex.tv/link.
class PlexPin {
  final int id;
  final String code;
  const PlexPin({required this.id, required this.code});
}

/// plex.tv PIN-link device pairing (`MyPlexPinLogin` flow).
///
/// Grounded in python-plexapi `plexapi/myplex.py`: create a PIN, show the code
/// at [linkUrl], poll until an `authToken` returns. The **same**
/// [clientId] (X-Plex-Client-Identifier) must be sent on every call or plex.tv
/// treats us as a different device. IO is isolated here so the service and the
/// pairing widget stay simple; the [HttpClient] factory is injectable for tests.
class PlexTvAuth {
  static const String _pinsUrl = 'https://plex.tv/api/v2/pins';
  static const String _userUrl = 'https://plex.tv/api/v2/user';

  /// The page the user visits to enter the 4-char code.
  static const String linkUrl = 'https://plex.tv/link';

  final String clientId;
  final String deviceName;
  final HttpClient Function() _createClient;

  PlexTvAuth({
    required this.clientId,
    required this.deviceName,
    HttpClient Function()? clientFactory,
  }) : _createClient = clientFactory ?? HttpClient.new;

  /// The stable X-Plex-* identity headers, applied to every plex.tv call.
  void applyIdentityHeaders(HttpClientRequest req) {
    req.headers
      ..set('Accept', 'application/json')
      ..set('X-Plex-Product', kPlexProduct)
      ..set('X-Plex-Version', kPlexVersion)
      ..set('X-Plex-Client-Identifier', clientId)
      ..set('X-Plex-Platform', 'Flutter')
      ..set('X-Plex-Device', kPlexProduct)
      ..set('X-Plex-Device-Name', deviceName.isEmpty ? kPlexProduct : deviceName)
      ..set('X-Plex-Provides', 'player');
  }

  /// Create a PIN. Returns null on failure.
  Future<PlexPin?> createPin() async {
    try {
      final client = _createClient();
      final req = await client.postUrl(Uri.parse(_pinsUrl));
      applyIdentityHeaders(req);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode >= 400) {
        Log.e('Plex', 'createPin failed: HTTP ${resp.statusCode}');
        return null;
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final id = json['id'];
      final code = json['code'] as String?;
      if (id == null || code == null) return null;
      return PlexPin(id: id as int, code: code);
    } catch (e) {
      Log.e('Plex', 'createPin error: $e');
      return null;
    }
  }

  /// Poll a PIN once. Returns the `authToken` when the user has linked, else
  /// null (not yet linked, or an error).
  Future<String?> pollForToken(int pinId) async {
    try {
      final client = _createClient();
      final req = await client.getUrl(Uri.parse('$_pinsUrl/$pinId'));
      applyIdentityHeaders(req);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode >= 400) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final token = json['authToken'] as String?;
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (e) {
      Log.w('Plex', 'pollForToken error: $e');
      return null;
    }
  }

  /// True if [token] is a currently-valid plex.tv token.
  Future<bool> verifyToken(String token) async {
    if (token.isEmpty) return false;
    try {
      final client = _createClient();
      final req = await client.getUrl(Uri.parse(_userUrl));
      applyIdentityHeaders(req);
      req.headers.set('X-Plex-Token', token);
      final resp = await req.close();
      await resp.drain();
      client.close();
      return resp.statusCode == 200;
    } catch (e) {
      Log.w('Plex', 'verifyToken error: $e');
      return false;
    }
  }
}
