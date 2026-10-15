import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/models.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

CalendarSource _ha(String entity, {bool enabled = true}) => CalendarSource(
      id: 'ha:$entity',
      kind: CalendarSourceKind.ha,
      entityId: entity,
      enabled: enabled,
    );

CalendarEvent _event(String sourceId, String summary, DateTime start,
        {bool allDay = false}) =>
    CalendarEvent(
      sourceId: sourceId,
      summary: summary,
      allDay: allDay,
      start: start,
      end: start.add(const Duration(hours: 1)),
    );

void main() {
  group('calendarEventsProvider', () {
    late Map<String, StreamController<SourceEvents>> feeds;

    ProviderContainer container(List<CalendarSource> sources) {
      feeds = {
        for (final s in sources) s.id: StreamController<SourceEvents>()
      };
      final c = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith(
            (ref) => _MemoryConfigNotifier(HubConfig(calendarSources: sources))),
        calendarSourceEventsProvider
            .overrideWith((ref, id) => feeds[id]!.stream),
      ]);
      addTearDown(c.dispose);
      c.listen(calendarEventsProvider, (_, _) {});
      return c;
    }

    final family = _ha('calendar.family');
    final school = _ha('calendar.school');

    test('merges sources sorted by start, all-day first, then source order',
        () async {
      final c = container([family, school]);
      final day = DateTime(2026, 10, 14);
      feeds[family.id]!.add(SourceEvents(status: SourceStatus.ok, events: [
        _event(family.id, 'Dentist', DateTime.utc(2026, 10, 14, 14)),
        _event(family.id, 'Same time, family', DateTime.utc(2026, 10, 14, 16)),
      ]));
      feeds[school.id]!.add(SourceEvents(status: SourceStatus.ok, events: [
        _event(school.id, 'Same time, school', DateTime.utc(2026, 10, 14, 16)),
        _event(school.id, 'Break', day, allDay: true),
        _event(school.id, 'Midnight', day.toUtc()),
        _event(school.id, 'Early', DateTime.utc(2026, 10, 12, 12)),
      ]));
      await pumpEventQueue();

      final merged = c.read(calendarEventsProvider);
      expect(merged.events.map((e) => e.summary).toList(), [
        'Early',
        'Break', // ties with 'Midnight'; all-day first
        'Midnight',
        'Dentist',
        'Same time, family', // ties with school; source order
        'Same time, school',
      ]);
      expect(merged.sources.keys, [family.id, school.id]);
    });

    test('a disabled source is excluded', () async {
      final off = _ha('calendar.off', enabled: false);
      final c = container([family, off]);
      feeds[family.id]!.add(SourceEvents(status: SourceStatus.ok, events: [
        _event(family.id, 'Dentist', DateTime.utc(2026, 10, 14, 14)),
      ]));
      await pumpEventQueue();

      final merged = c.read(calendarEventsProvider);
      expect(merged.sources.keys, [family.id]);
      expect(merged.events.single.summary, 'Dentist');
    });

    test('per-source status is carried; a failing source hides nothing else',
        () async {
      final c = container([family, school]);
      feeds[family.id]!.add(SourceEvents(status: SourceStatus.ok, events: [
        _event(family.id, 'Dentist', DateTime.utc(2026, 10, 14, 14)),
      ]));
      feeds[school.id]!.add(const SourceEvents(
          status: SourceStatus.error, error: 'Entity not found'));
      await pumpEventQueue();

      final merged = c.read(calendarEventsProvider);
      expect(merged.events.single.summary, 'Dentist');
      expect(merged.sources[family.id]!.status, SourceStatus.ok);
      expect(merged.sources[school.id]!.status, SourceStatus.error);
      expect(merged.sources[school.id]!.error, 'Entity not found');
    });

    test('a source that has not reported yet is loading', () async {
      final c = container([family]);
      await pumpEventQueue();
      expect(c.read(calendarEventsProvider).sources[family.id]!.status,
          SourceStatus.loading);
    });
  });

  group('calendarSourceEventsProvider', () {
    test('HA source with HA unconfigured reports an error', () async {
      final c = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier(
            HubConfig(calendarSources: [_ha('calendar.family')]))),
      ]);
      addTearDown(c.dispose);
      final sub =
          c.listen(calendarSourceEventsProvider('ha:calendar.family'), (_, _) {});
      await pumpEventQueue();
      expect(sub.read().value?.status, SourceStatus.error);
    });

    test('disabling an ICS source stops its fetches', () async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          requests++;
          handler.reject(DioException(requestOptions: options));
        }));
      const ics = CalendarSource(
        id: 'ics:1',
        kind: CalendarSourceKind.ics,
        url: 'https://example.com/cal.ics',
      );
      final notifier =
          _MemoryConfigNotifier(const HubConfig(calendarSources: [ics]));
      final c = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) => notifier),
        icsDioProvider.overrideWithValue(dio),
      ]);
      addTearDown(c.dispose);
      c.listen(calendarSourceEventsProvider(ics.id), (_, _) {});
      await pumpEventQueue();
      expect(requests, 1);

      await notifier.update((cfg) => cfg.copyWith(
          calendarSources: [ics.copyWith(enabled: false)]));
      await pumpEventQueue();
      expect(requests, 1);
    });
  });

  group('defaultCalendarWindow', () {
    test('runs from the Monday before last week to the end of next month', () {
      final w = defaultCalendarWindow(DateTime(2026, 10, 14, 15, 30)); // Wed
      expect(w.start, DateTime(2026, 10, 5));
      expect(w.end, DateTime(2026, 12, 1));
    });

    test('crosses a year', () {
      final w = defaultCalendarWindow(DateTime(2026, 12, 3)); // Thu
      expect(w.start, DateTime(2026, 11, 23));
      expect(w.end, DateTime(2027, 2, 1));
    });
  });
}
