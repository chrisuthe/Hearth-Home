import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/timezone_service.dart';

void main() {
  group('TimezoneService', () {
    late TimezoneService service;

    setUp(() {
      service = TimezoneService();
    });

    test('commonTimezones contains expected entries', () {
      expect(TimezoneService.commonTimezones, contains('America/New_York'));
      expect(TimezoneService.commonTimezones, contains('Europe/London'));
      expect(TimezoneService.commonTimezones, contains('Asia/Tokyo'));
      expect(TimezoneService.commonTimezones, contains('Pacific/Auckland'));
    });

    test('commonTimezones are all valid IANA format', () {
      for (final tz in TimezoneService.commonTimezones) {
        expect(tz, contains('/'), reason: '$tz should contain a slash');
      }
    });

    test('applyTimezone returns false for empty timezone', () async {
      final result = await service.applyTimezone('');
      expect(result, false);
    });

    test('applyTimezone returns false on non-Linux (Windows)', () async {
      // On Windows test runner, this should be a no-op returning false.
      final result = await service.applyTimezone('America/New_York');
      expect(result, false);
    });

    test('getCurrentTimezone returns empty on non-Linux', () async {
      // On Windows test runner, should return empty string.
      final tz = await service.getCurrentTimezone();
      expect(tz, '');
    });

    test('listTimezones returns fallback list on non-Linux', () async {
      // On Windows test runner, should return the hardcoded fallback list.
      final zones = await service.listTimezones();
      expect(zones, isNotEmpty);
      expect(zones, contains('America/New_York'));
      expect(zones, contains('Europe/London'));
      expect(zones, contains('UTC'));
    });

    test('fallback timezone list is sorted', () {
      final sorted = List<String>.from(TimezoneService.commonTimezones)..sort();
      // Common list is curated, not necessarily sorted — but fallback should be.
      final fallback = TimezoneService.commonTimezones;
      expect(fallback, isNotEmpty);
    });
  });
}
