/// Parsed UPnP SOAP control request.
class SoapAction {
  /// Service type URN from the SOAPACTION header, e.g.
  /// `urn:schemas-upnp-org:service:AVTransport:1`.
  final String serviceType;

  /// Action name, e.g. `SetAVTransportURI`.
  final String action;

  /// In-args by name (already XML-unescaped). Wrapper elements (Envelope,
  /// Body, the namespaced action element) are excluded.
  final Map<String, String> args;

  const SoapAction({
    required this.serviceType,
    required this.action,
    required this.args,
  });
}

/// Reverse of `xmlEscape` — decode the XML entities that appear in arg values.
/// `&amp;` is decoded last so an already-decoded `<` can't be re-decoded.
String xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

// Unprefixed, attribute-less argument elements only. The SOAP wrapper tags
// (`s:Envelope`, `s:Body`, `u:ActionName …`) carry a namespace prefix and/or
// attributes, so `<(\w+)>…</\1>` never matches them — leaving exactly the
// action's in-args. Non-greedy body handles escaped DIDL inside metadata args.
// Match an in-arg element and its text content. The opening tag may carry
// attributes — Windows "Cast to Device" tags every arg with typed attributes
// (`<CurrentURI xmlns:dt="..." dt:dt="string">...`), so a bare `<(\w+)>` would
// silently drop those args and a cast would play nothing. `(?:\s[^>]*)?` allows
// the optional attribute list; prefixed wrappers (`<m:SetAVTransportURI ...>`)
// still don't match because `:` is neither whitespace nor `>`.
final RegExp _argRe = RegExp(r'<(\w+)(?:\s[^>]*)?>([\s\S]*?)</\1>');
final RegExp _actionElemRe = RegExp(r'<(?:\w+:)?(\w+)\s+xmlns:u=');

/// Parse a SOAP control request from the `SOAPACTION` header and request body.
///
/// The header is the authoritative source of the service type and action
/// (`"<serviceType>#<Action>"`, quotes mandatory per UDA). Returns null if the
/// header is malformed.
SoapAction? parseSoapAction(String? soapActionHeader, String body) {
  if (soapActionHeader == null) return null;
  final header = soapActionHeader.trim().replaceAll('"', '');
  final hash = header.indexOf('#');
  if (hash <= 0 || hash >= header.length - 1) return null;
  final serviceType = header.substring(0, hash);
  final action = header.substring(hash + 1);

  final args = <String, String>{};
  for (final m in _argRe.allMatches(body)) {
    args[m.group(1)!] = xmlUnescape(m.group(2)!);
  }
  return SoapAction(serviceType: serviceType, action: action, args: args);
}

/// Extract just the action name from a SOAP body (fallback when no SOAPACTION
/// header is present). Returns null if no namespaced action element is found.
String? actionNameFromBody(String body) =>
    _actionElemRe.firstMatch(body)?.group(1);
