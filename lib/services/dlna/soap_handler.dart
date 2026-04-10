import 'dart:io';

/// Parsed SOAP action from a DLNA control point.
class SoapAction {
  final String serviceType;
  final String actionName;
  final Map<String, String> arguments;

  SoapAction(this.serviceType, this.actionName, this.arguments);
}

/// Parse a SOAP action from an HTTP request.
/// SOAPAction header format: "urn:schemas-upnp-org:service:AVTransport:1#Play"
/// Returns null if invalid.
SoapAction? parseSoapAction(HttpRequest request, String body) {
  final soapAction = request.headers.value('SOAPAction');
  if (soapAction == null) return null;

  // Strip surrounding quotes if present
  final cleaned = soapAction.replaceAll('"', '');
  final hashIndex = cleaned.indexOf('#');
  if (hashIndex < 0) return null;

  final serviceType = cleaned.substring(0, hashIndex);
  final actionName = cleaned.substring(hashIndex + 1);
  if (actionName.isEmpty) return null;

  // Extract arguments from SOAP body
  final args = <String, String>{};
  final argPattern = RegExp(r'<(\w+)(?:\s[^>]*)?>([^<]*)</\1>', multiLine: true);
  // Find the action element first, then extract children
  final actionPattern =
      RegExp('<u:$actionName[^>]*>(.*?)</u:$actionName>', dotAll: true);
  final actionMatch = actionPattern.firstMatch(body);
  if (actionMatch != null) {
    final actionBody = actionMatch.group(1)!;
    for (final match in argPattern.allMatches(actionBody)) {
      final name = match.group(1)!;
      final value = match.group(2)!;
      args[name] = value;
    }
  }

  return SoapAction(serviceType, actionName, args);
}

/// Build a SOAP response envelope.
String soapResponse(
  String serviceType,
  String actionName,
  Map<String, String> values,
) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln(
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
    )
    ..writeln('<s:Body>')
    ..writeln('<u:${actionName}Response xmlns:u="$serviceType">');

  for (final entry in values.entries) {
    buffer.writeln(
      '<${entry.key}>${_xmlEscape(entry.value)}</${entry.key}>',
    );
  }

  buffer
    ..writeln('</u:${actionName}Response>')
    ..writeln('</s:Body>')
    ..write('</s:Envelope>');

  return buffer.toString();
}

/// Build a SOAP fault response.
String soapFault(int errorCode, String errorDescription) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\n'
      '<s:Body>\n'
      '<s:Fault>\n'
      '<faultcode>s:Client</faultcode>\n'
      '<faultstring>UPnPError</faultstring>\n'
      '<detail>\n'
      '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">\n'
      '<errorCode>$errorCode</errorCode>\n'
      '<errorDescription>${_xmlEscape(errorDescription)}</errorDescription>\n'
      '</UPnPError>\n'
      '</detail>\n'
      '</s:Fault>\n'
      '</s:Body>\n'
      '</s:Envelope>';
}

/// Format Duration as HH:MM:SS for DLNA time strings.
String formatDlnaTime(Duration d) {
  final hours = d.inHours.toString().padLeft(2, '0');
  final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

/// Parse DLNA time string (HH:MM:SS) to Duration.
Duration? parseDlnaTime(String time) {
  final parts = time.split(':');
  if (parts.length != 3) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = int.tryParse(parts[2]);
  if (hours == null || minutes == null || seconds == null) return null;
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

/// Parse DIDL-Lite metadata to extract title.
String? parseDidlTitle(String metadata) {
  final match = RegExp(r'<dc:title>(.*?)</dc:title>', dotAll: true)
      .firstMatch(metadata);
  return match?.group(1);
}

/// Parse DIDL-Lite metadata to extract album art URL.
String? parseDidlArtUrl(String metadata) {
  final match =
      RegExp(r'<upnp:albumArtURI>(.*?)</upnp:albumArtURI>', dotAll: true)
          .firstMatch(metadata);
  return match?.group(1);
}

/// XML-escape a string.
String _xmlEscape(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
