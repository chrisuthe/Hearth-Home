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

  /// When true, the script also installs a `matchMedia` shim that reports
  /// `prefers-color-scheme: dark`, so an HA frontend on the default/"Auto"
  /// theme renders dark. Verified against the frontend's `themes-mixin.ts`:
  /// `darkMode = themeSettings?.dark === undefined ? darkPreferred : themeSettings.dark`,
  /// where `darkPreferred = matchMedia('(prefers-color-scheme: dark)').matches`.
  final bool darkMode;

  const HaTokenInjector({
    required this.haUrl,
    required this.token,
    this.darkMode = false,
  });

  /// The document-start JS to run on the HA origin.
  String get script {
    final jsUrl = jsonEncode(haUrl);
    final jsToken = jsonEncode(token);
    final seed = '(function(){try{'
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
    return darkMode ? '$seed${_darkModeShim(jsUrl)}' : seed;
  }

  /// Overrides `window.matchMedia` so `(prefers-color-scheme: dark)` reports a
  /// match (and `light` reports none), delegating every other query to the
  /// real implementation so HA's responsive breakpoints are unaffected. Runs
  /// at document-start, before the HA frontend reads the preference.
  static String _darkModeShim(String jsUrl) => '(function(){try{'
      'var hassUrl=$jsUrl;'
      'if(location.origin!==new URL(hassUrl).origin)return;'
      'var m=window.matchMedia?window.matchMedia.bind(window):null;'
      'function q(query,val){return{matches:val,media:query,onchange:null,'
      'addListener:function(){},removeListener:function(){},'
      'addEventListener:function(){},removeEventListener:function(){},'
      'dispatchEvent:function(){return false;}};}'
      'window.matchMedia=function(query){'
      'if(typeof query==="string"){'
      'if(/prefers-color-scheme\\s*:\\s*dark/i.test(query))return q(query,true);'
      'if(/prefers-color-scheme\\s*:\\s*light/i.test(query))return q(query,false);'
      '}'
      'return m?m(query):q(query,false);'
      '};'
      '}catch(e){}})();';

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
  bool darkMode = false,
}) {
  if (config.source != WebviewSource.haDashboard) return null;
  if (haUrl.isEmpty || haToken.isEmpty) return null;
  // Require an absolute http(s) URL with a host: anything else makes
  // HaTokenInjector.allowOrigin (Uri.origin) throw. Gate it out so a
  // misconfigured haUrl degrades to "no injection" rather than crashing.
  final uri = Uri.tryParse(haUrl);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return HaTokenInjector(haUrl: haUrl, token: haToken, darkMode: darkMode);
}
