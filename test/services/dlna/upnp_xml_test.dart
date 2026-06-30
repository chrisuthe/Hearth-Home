import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/dlna/upnp_xml.dart';

void main() {
  group('time formatting', () {
    test('formatUpnpTime zero-pads H:MM:SS', () {
      expect(formatUpnpTime(const Duration(minutes: 1, seconds: 23)),
          '00:01:23');
      expect(
          formatUpnpTime(
              const Duration(hours: 1, minutes: 32, seconds: 10)),
          '01:32:10');
    });

    test('parseUpnpTime round-trips HH:MM:SS', () {
      expect(parseUpnpTime('00:01:23'),
          const Duration(minutes: 1, seconds: 23));
      expect(parseUpnpTime('01:32:10'),
          const Duration(hours: 1, minutes: 32, seconds: 10));
    });

    test('parseUpnpTime tolerates fractional seconds and bad input', () {
      expect(parseUpnpTime('0:00:05.500'),
          const Duration(seconds: 5, milliseconds: 500));
      expect(parseUpnpTime('garbage'), Duration.zero);
    });
  });

  group('deviceDescription', () {
    test('declares MediaRenderer device type and the three services', () {
      final xml = deviceDescription(uuid: 'abc-123', friendlyName: 'Hearth');
      expect(xml, contains(kMediaRendererDeviceType));
      expect(xml, contains('<UDN>uuid:abc-123</UDN>'));
      expect(xml, contains('<friendlyName>Hearth</friendlyName>'));
      expect(xml, contains(kAvTransportType));
      expect(xml, contains(kRenderingControlType));
      expect(xml, contains(kConnectionManagerType));
    });

    test('escapes the friendly name', () {
      final xml = deviceDescription(uuid: 'u', friendlyName: 'A & B');
      expect(xml, contains('<friendlyName>A &amp; B</friendlyName>'));
    });
  });

  group('soapResponse', () {
    test('wraps args in a namespaced Response element', () {
      final xml = soapResponse(kAvTransportType, 'GetTransportInfo', const {
        'CurrentTransportState': 'PLAYING',
        'CurrentSpeed': '1',
      });
      expect(
          xml,
          contains(
              '<u:GetTransportInfoResponse xmlns:u="$kAvTransportType">'));
      expect(xml, contains('<CurrentTransportState>PLAYING</CurrentTransportState>'));
      expect(xml, contains('</u:GetTransportInfoResponse>'));
    });

    test('emits an empty Response element when there are no args', () {
      final xml = soapResponse(kAvTransportType, 'Play', const {});
      expect(xml, contains('<u:PlayResponse xmlns:u="$kAvTransportType">'));
      expect(xml, contains('</u:PlayResponse>'));
    });

    test('escapes arg values', () {
      final xml = soapResponse(kAvTransportType, 'GetMediaInfo', const {
        'CurrentURI': 'http://h/a?b=1&c=2',
      });
      expect(xml, contains('http://h/a?b=1&amp;c=2'));
    });
  });

  group('soapFault', () {
    test('emits a UPnPError with the given code', () {
      final xml = soapFault(401, 'Invalid Action');
      expect(xml, contains('<faultstring>UPnPError</faultstring>'));
      expect(xml, contains('<errorCode>401</errorCode>'));
      expect(xml, contains('<errorDescription>Invalid Action</errorDescription>'));
      expect(xml, contains('urn:schemas-upnp-org:control-1-0'));
    });
  });

  group('LastChange events', () {
    test('AVTransport wraps an escaped Event document', () {
      final xml = avtLastChangePropertySet({'TransportState': 'PLAYING'});
      expect(xml, contains('urn:schemas-upnp-org:event-1-0'));
      expect(xml, contains('<LastChange>'));
      // The inner Event is escaped character data.
      expect(xml, contains('&lt;TransportState val=&quot;PLAYING&quot;/&gt;'));
    });

    test('RenderingControl vars carry channel="Master"', () {
      final xml = rcLastChangePropertySet({'Volume': '50'});
      expect(xml,
          contains('&lt;Volume channel=&quot;Master&quot; val=&quot;50&quot;/&gt;'));
    });
  });
}
