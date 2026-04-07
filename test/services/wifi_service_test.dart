import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/wifi_service.dart';

void main() {
  group('WifiNetwork', () {
    test('parses nmcli scan output line', () {
      const line = 'MyNetwork:85:WPA2';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, 'MyNetwork');
      expect(network.signalStrength, 85);
      expect(network.security, 'WPA2');
    });

    test('parses open network (no security)', () {
      const line = 'CoffeeShop:42:';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, 'CoffeeShop');
      expect(network.signalStrength, 42);
      expect(network.security, '');
      expect(network.isOpen, true);
    });

    test('skips blank SSID lines', () {
      const line = ':30:WPA2';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, '');
    });
  });

  group('WifiService', () {
    test('parseScanOutput deduplicates and sorts by signal', () {
      const output =
          'MyNetwork:85:WPA2\nOtherNet:60:WPA2\nMyNetwork:90:WPA2\nOpenNet:30:';
      final networks = WifiService.parseScanOutput(output);
      expect(networks.length, 3);
      expect(networks[0].ssid, 'MyNetwork');
      expect(networks[0].signalStrength, 90);
      expect(networks[1].ssid, 'OtherNet');
      expect(networks[2].ssid, 'OpenNet');
    });

    test('parseActiveConnection extracts active SSID', () {
      const output = 'wlan0:MyNetwork';
      final ssid = WifiService.parseActiveConnection(output);
      expect(ssid, 'MyNetwork');
    });

    test('parseActiveConnection returns null when disconnected', () {
      const output = 'wlan0:';
      final ssid = WifiService.parseActiveConnection(output);
      expect(ssid, isNull);
    });
  });
}
