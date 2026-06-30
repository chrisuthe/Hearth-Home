import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/dlna/soap_request.dart';

const _setUriBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>http://10.0.1.99:8200/video/movie.mp4</CurrentURI>
      <CurrentURIMetaData>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;Movie&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';

const _playBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>''';

void main() {
  group('parseSoapAction', () {
    test('extracts service type and action from SOAPACTION header', () {
      final result = parseSoapAction(
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
        _setUriBody,
      );
      expect(result, isNotNull);
      expect(result!.serviceType,
          'urn:schemas-upnp-org:service:AVTransport:1');
      expect(result.action, 'SetAVTransportURI');
    });

    test('extracts in-args and ignores wrapper elements', () {
      final result = parseSoapAction(
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
        _setUriBody,
      )!;
      expect(result.args['InstanceID'], '0');
      expect(result.args['CurrentURI'],
          'http://10.0.1.99:8200/video/movie.mp4');
      // Wrapper elements (Envelope/Body/the namespaced action) must not appear.
      expect(result.args.containsKey('Envelope'), isFalse);
      expect(result.args.containsKey('Body'), isFalse);
      expect(result.args.containsKey('SetAVTransportURI'), isFalse);
    });

    test('unescapes nested DIDL metadata in arg values', () {
      final result = parseSoapAction(
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
        _setUriBody,
      )!;
      expect(result.args['CurrentURIMetaData'],
          '<DIDL-Lite><item><dc:title>Movie</dc:title></item></DIDL-Lite>');
    });

    test('parses a Play envelope with Speed arg', () {
      final result = parseSoapAction(
        '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
        _playBody,
      )!;
      expect(result.action, 'Play');
      expect(result.args['Speed'], '1');
    });

    test('returns null for a malformed SOAPACTION header', () {
      expect(parseSoapAction('no-hash-here', _playBody), isNull);
      expect(parseSoapAction(null, _playBody), isNull);
    });
  });

  group('xmlUnescape', () {
    test('decodes all five entities, ampersand last', () {
      expect(xmlUnescape('&lt;a&gt;&amp;&quot;&apos;'), '<a>&"\'');
    });
  });

  group('actionNameFromBody', () {
    test('extracts the namespaced action element name', () {
      expect(actionNameFromBody(_playBody), 'Play');
    });
  });
}
