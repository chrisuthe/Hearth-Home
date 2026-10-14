import 'dart:async';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';
import 'ha_calendar_source.dart';
import 'models.dart';

/// The default window around [now]: from the start of last week (Monday) to
/// the end of next month.
DateTimeRange defaultCalendarWindow(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  return DateTimeRange(
    start: DateTime(weekStart.year, weekStart.month, weekStart.day - 7),
    end: DateTime(now.year, now.month + 2, 1),
  );
}

/// The range the calendar is showing. One shared window for every view and
/// the ambient glance; a change resubscribes every source.
final calendarWindowProvider = StateProvider<DateTimeRange>((ref) {
  Timer? timer;
  void scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      final window = ref.controller.state;
      final today = DateTime.now();
      // Follow "today" once it leaves the window's second week; a window the
      // user paged away from today stays where it is.
      final lagging = !today.isBefore(window.start.add(const Duration(days: 14)));
      if (lagging) ref.controller.state = defaultCalendarWindow(today);
      scheduleMidnight();
    });
  }

  scheduleMidnight();
  ref.onDispose(() => timer?.cancel());
  return defaultCalendarWindow(DateTime.now());
});

/// Events of one configured source over [calendarWindowProvider]. Rebuilt,
/// and so resubscribed, when the source's config entry or the window changes.
final calendarSourceEventsProvider =
    StreamProvider.family<SourceEvents, String>((ref, sourceId) {
  final source = ref.watch(hubConfigProvider.select((c) {
    for (final s in c.calendarSources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }));
  if (source == null) {
    return Stream.value(const SourceEvents(
        status: SourceStatus.error, error: 'Calendar source not configured'));
  }
  final window = ref.watch(calendarWindowProvider);

  switch (source.kind) {
    case CalendarSourceKind.ha:
      final ha = ref.watch(homeAssistantServiceProvider);
      final haUrl = ref.watch(hubConfigProvider.select((c) => c.haUrl));
      final haToken = ref.watch(hubConfigProvider.select((c) => c.haToken));
      final pollMinutes =
          ref.watch(hubConfigProvider.select((c) => c.calendarIcsPollMinutes));
      final haSource = HaCalendarSource(
        ha: ha,
        source: source,
        window: window,
        haUrl: haUrl,
        haToken: haToken,
        pollInterval: Duration(minutes: pollMinutes),
      );
      ref.onDispose(haSource.dispose);
      return haSource.stream;
    case CalendarSourceKind.ics:
      // IcsCalendarSource (fetch, parse, expand, poll) plugs in here.
      return Stream.value(const SourceEvents(
          status: SourceStatus.error, error: 'ICS feeds are not supported yet'));
  }
});

/// Every enabled source's events, merged and sorted, with each source's
/// status for the legend.
class MergedEvents {
  /// Sorted by start, all-day first, then source order.
  final List<CalendarEvent> events;

  /// Keyed by source id, in source order.
  final Map<String, SourceEvents> sources;

  const MergedEvents({this.events = const [], this.sources = const {}});
}

final calendarEventsProvider = Provider<MergedEvents>((ref) {
  final enabled = ref
      .watch(hubConfigProvider.select((c) => c.calendarSources))
      .where((s) => s.enabled)
      .toList();
  final order = {for (var i = 0; i < enabled.length; i++) enabled[i].id: i};

  final sources = <String, SourceEvents>{};
  final events = <CalendarEvent>[];
  for (final source in enabled) {
    final value = ref.watch(calendarSourceEventsProvider(source.id));
    final status = value.when(
      data: (v) => v,
      loading: () => const SourceEvents(),
      error: (e, _) =>
          SourceEvents(status: SourceStatus.error, error: e.toString()),
    );
    sources[source.id] = status;
    events.addAll(status.events);
  }

  events.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return order[a.sourceId]!.compareTo(order[b.sourceId]!);
  });
  return MergedEvents(events: events, sources: sources);
});
