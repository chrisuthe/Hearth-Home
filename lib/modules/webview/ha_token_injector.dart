import 'dart:convert';

import '../../config/webview_config.dart';

/// Builds the document-start JavaScript that authenticates a WPE-rendered
/// Home Assistant Lovelace dashboard by seeding `localStorage['hassTokens']`
/// before the HA frontend bootstraps.
///
/// The payload mirrors `home-assistant-js-websocket`'s
/// `createLongLivedTokenAuth(hassUrl, token)` exactly — verified against
/// source (`lib/auth.ts` and the frontend's `src/common/auth/token_storage.ts`),
/// not guessed:
///
/// ```js
/// new Auth({
///   hassUrl,
///   clientId: null,
///   expires: Date.now() + 1e11,
///   refresh_token: "",
///   access_token,
///   expires_in: 1e11,
/// })
/// // stored via: localStorage.setItem("hassTokens", JSON.stringify(tokens))
/// ```
///
/// `expires`/`expires_in` are emitted as the literal `Date.now()+1e11` / `1e11`
/// so the value is computed at injection time on the device clock, matching
/// HA's own runtime behaviour. With no `refresh_token`, the far-future
/// `expires` means the frontend never attempts a refresh, so the session lasts
/// the long-lived token's life.
///
/// The script re-runs at document-start on every page load (it is registered
/// on the WebView's user-content manager), so the configured token is the
/// source of truth on each load — robust whether or not WPE persists
/// localStorage across reloads/reboots.
class HaTokenInjector {
  /// The configured Home Assistant base URL (`config.haUrl`).
  final String haUrl;

  /// The long-lived access token (`config.haToken`).
  final String token;

  const HaTokenInjector({required this.haUrl, required this.token});

  /// The document-start JS to run on the HA origin.
  String get script {
    final jsUrl = jsonEncode(haUrl);
    final jsToken = jsonEncode(token);
    return '(function(){try{'
        'var hassUrl=$jsUrl;'
        // Defense-in-depth: only seed on the HA origin even if the
        // user-script allow-list is ever widened.
        'if(location.origin!==new URL(hassUrl).origin)return;'
        'localStorage.setItem("hassTokens",JSON.stringify({'
        'hassUrl:hassUrl,'
        'clientId:null,'
        'expires:Date.now()+1e11,'
        'refresh_token:"",'
        'access_token:$jsToken,'
        'expires_in:1e11'
        '}));'
        '}catch(e){}})();';
  }

  /// URL-match pattern scoping the user script to the HA origin only, e.g.
  /// `https://ha.example.com/*`. Passed to the native side as the
  /// `WebKitUserScript` allow-list so the token never leaks to other origins.
  String get allowOrigin => '${Uri.parse(haUrl).origin}/*';
}

/// Returns an [HaTokenInjector] for [config] iff it is an HA dashboard webview
/// with both an HA URL and token configured; otherwise null.
///
/// This is the gating that keeps token injection scoped to HA dashboards —
/// custom-URL webviews always get null and so receive no script.
HaTokenInjector? injectorForWebview(
  WebviewConfig config, {
  required String haUrl,
  required String haToken,
}) {
  if (config.source != WebviewSource.haDashboard) return null;
  if (haUrl.isEmpty || haToken.isEmpty) return null;
  return HaTokenInjector(haUrl: haUrl, token: haToken);
}
