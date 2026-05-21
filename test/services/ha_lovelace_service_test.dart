import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/ha_lovelace_service.dart';

void main() {
  group('HaLovelaceService', () {
    test('parses a single-dashboard response correctly', () {
      final raw = [
        {
          'id': '1',
          'url_path': 'lovelace',
          'title': 'Overview',
          'icon': 'mdi:view-dashboard',
          'show_in_sidebar': true,
          'require_admin': false,
          'mode': 'storage',
        },
      ];
      final result = HaLovelaceService.parseDashboards(raw);
      expect(result.length, 1);
      expect(result.first.urlPath, 'lovelace');
      expect(result.first.title, 'Overview');
    });

    test('parses multi-dashboard response correctly', () {
      final raw = [
        {'id': '1', 'url_path': 'lovelace', 'title': 'Overview', 'icon': 'mdi:view-dashboard', 'show_in_sidebar': true, 'require_admin': false, 'mode': 'storage'},
        {'id': '2', 'url_path': 'lights', 'title': 'Lights', 'icon': 'mdi:lightbulb', 'show_in_sidebar': true, 'require_admin': false, 'mode': 'storage'},
      ];
      final result = HaLovelaceService.parseDashboards(raw);
      expect(result.length, 2);
      expect(result[1].urlPath, 'lights');
    });

    test('handles missing icon gracefully', () {
      final raw = [
        {'id': '1', 'url_path': 'lovelace', 'title': 'Overview', 'show_in_sidebar': true, 'require_admin': false, 'mode': 'storage'},
      ];
      final result = HaLovelaceService.parseDashboards(raw);
      expect(result.first.icon, isNull);
    });

    test('HaDashboard.fullUrlOn strips trailing slash from base url', () {
      const dashboard = HaDashboard(
        urlPath: 'lovelace',
        title: 'Overview',
        icon: null,
        showInSidebar: true,
        requireAdmin: false,
        mode: 'storage',
      );
      expect(dashboard.fullUrlOn('https://ha.example/'), 'https://ha.example/lovelace');
      expect(dashboard.fullUrlOn('https://ha.example'), 'https://ha.example/lovelace');
    });
  });
}
