import 'dart:io';
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

    test('applyTimezone handles a timezone string', () async {
      // On Linux CI: may succeed (returns true) if timedatectl works.
      // On Windows dev: returns false (not Linux).
      final result = await service.applyTimezone('America/New_York');
      expect(result, isA<bool>());
      if (!Platform.isLinux) {
        expect(result, false);
      }
    });

    test('getCurrentTimezone returns a string', () async {
      final tz = await service.getCurrentTimezone();
      expect(tz, isA<String>());
      // On Linux, should be a non-empty timezone like 'Etc/UTC'.
      // On Windows, returns empty string.
    });

    test('listTimezones returns a non-empty list', () async {
      final zones = await service.listTimezones();
      expect(zones, isNotEmpty);
      // Should contain common timezone names on any platform.
      expect(zones, contains('America/New_York'));
      expect(zones, contains('Europe/London'));
    });

    test('fallback timezone list is non-empty', () {
      expect(TimezoneService.commonTimezones, isNotEmpty);
    });
  });
}
