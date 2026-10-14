import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/ics_calendar_source.dart';
import 'package:hearth/modules/calendar/models.dart';

String _fixture(String name) =>
    File('test/fixtures/calendar/$name.ics').readAsStringSync();

/// Answers each request with the next of [replies]: a `(status, body,
/// headers)` record, or an exception to throw. The last one repeats.
class _FakeAdapter implements HttpClientAdapter {
  final List<Object> replies;
  final requests = <RequestOptions>[];
  _FakeAdapter(this.replies);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply =
        replies[requests.length <= replies.length
            ? requests.length - 1
            : replies.length - 1];
    if (reply is Exception) {
      throw reply is DioException
          ? reply.copyWith(requestOptions: options)
          : reply;
    }
    final (status, body, headers) =
        reply as (int, String, Map<String, List<String>>);
    return ResponseBody.fromString(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

(int, String, Map<String, List<String>>) _ok(String body, {String? etag}) => (
  200,
  body,
  {
    if (etag != null) 'etag': [etag],
  },
);

const _source = CalendarSource(
  id: 'ics:family',
  kind: CalendarSourceKind.ics,
  url: 'webcal://example.com/family.ics',
  name: 'Family',
);

final _window = DateTimeRange(
  start: DateTime.utc(2026, 10, 5),
  end: DateTime.utc(2026, 10, 26),
);

Future<R> _inline<R>(R Function() work) async => work();

void main() {
  late IcsCalendarSource source;
  late _FakeAdapter adapter;
  late List<SourceEvents> states;
  var seen = 0;

  IcsCalendarSource start(
    List<Object> replies, {
    Duration poll = const Duration(minutes: 30),
  }) {
    adapter = _FakeAdapter(replies);
    source = IcsCalendarSource(
      source: _source,
      window: _window,
      pollInterval: poll,
      dio: Dio()..httpClientAdapter = adapter,
      worker: _inline,
    );
    addTearDown(source.dispose);
    states = [];
    seen = 0;
    source.stream.listen(states.add);
    return source;
  }

  /// The next emission after the last one returned, with [status] if given.
  Future<SourceEvents> next([SourceStatus? status]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      while (seen < states.length) {
        final s = states[seen++];
        if (status == null || s.status == status) return s;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'no $status; saw ${states.map((s) => s.status)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('webcal and webcals map to https; other schemes pass through', () {
    expect(
      IcsCalendarSource.normalizeUrl('webcal://example.com/a.ics'),
      'https://example.com/a.ics',
    );
    expect(
      IcsCalendarSource.normalizeUrl(' WEBCALS://example.com/a.ics '),
      'https://example.com/a.ics',
    );
    expect(
      IcsCalendarSource.normalizeUrl('http://nas.local/a.ics'),
      'http://nas.local/a.ics',
    );
  });

  test(
    'fetches the https URL with a 20 s timeout and expands the feed',
    () async {
      start([_ok(_fixture('ics_recurring_with_exceptions'))]);
      final ok = await next(SourceStatus.ok);

      expect(
        adapter.requests.single.uri.toString(),
        'https://example.com/family.ics',
      );
      expect(
        IcsCalendarSource.newDio().options.receiveTimeout,
        const Duration(seconds: 20),
      );
      expect(ok.events, hasLength(3));
      expect(ok.events.every((e) => e.sourceId == _source.id), isTrue);
      expect(ok.lastOk, isNotNull);
    },
  );

  test('a 304 keeps the last calendar', () async {
    start([
      _ok(_fixture('ics_recurring_with_exceptions'), etag: '"v1"'),
      (304, '', <String, List<String>>{}),
    ], poll: const Duration(milliseconds: 20));
    final first = await next(SourceStatus.ok);
    final second = await next();

    expect(adapter.requests[1].headers['If-None-Match'], '"v1"');
    expect(second.status, SourceStatus.ok);
    expect(second.events, first.events);
  });

  test('a 404 is an error, not retried before the next poll', () async {
    start([(404, 'Not found', <String, List<String>>{})]);
    final error = await next(SourceStatus.error);

    expect(error.error, 'Calendar not found at this URL');
    expect(error.events, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.requests, hasLength(1));
  });

  test('a timeout is stale and keeps the last events', () async {
    start([
      _ok(_fixture('ics_recurring_with_exceptions')),
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.receiveTimeout,
      ),
    ], poll: const Duration(milliseconds: 20));
    final ok = await next(SourceStatus.ok);
    final stale = await next(SourceStatus.stale);

    expect(stale.error, 'Calendar server timed out');
    expect(stale.events, ok.events);
    expect(stale.lastOk, ok.lastOk);
  });

  test('a timeout before any success is an error, and retries', () async {
    start([
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionTimeout,
      ),
      _ok(_fixture('ics_recurring_with_exceptions')),
    ], poll: const Duration(milliseconds: 20));
    expect((await next(SourceStatus.error)).error, 'Calendar server timed out');
    expect((await next(SourceStatus.ok)).events, hasLength(3));
  });

  test('a body over 10 MB is refused', () async {
    start([
      (
        200,
        '',
        {
          Headers.contentLengthHeader: ['${IcsCalendarSource.maxBytes + 1}'],
        },
      ),
    ]);
    expect(
      (await next(SourceStatus.error)).error,
      'Calendar is larger than 10 MB',
    );
  });

  test('a window change re-expands without refetching', () async {
    start([_ok(_fixture('ics_recurring_with_exceptions'))]);
    await next(SourceStatus.ok);

    source.window = DateTimeRange(
      start: DateTime.utc(2026, 10, 26),
      end: DateTime.utc(2026, 11, 2),
    );
    final moved = await next(SourceStatus.ok);

    // Mon 26 and Wed 28, 17:00 CDT.
    expect(moved.events.map((e) => e.start).toList()..sort(), [
      DateTime.utc(2026, 10, 26, 22),
      DateTime.utc(2026, 10, 28, 22),
    ]);
    expect(adapter.requests, hasLength(1));
  });

  test('calendarEventsProvider merges an ICS source with an HA source, '
      'parsed in an isolate', () async {
    const ha = CalendarSource(
      id: 'ha:calendar.school',
      kind: CalendarSourceKind.ha,
      entityId: 'calendar.school',
    );
    adapter = _FakeAdapter([_ok(_fixture('ics_recurring_with_exceptions'))]);
    final haFeed = StreamController<SourceEvents>();
    final c = ProviderContainer(
      overrides: [
        hubConfigProvider.overrideWith(
          (ref) => _MemoryConfigNotifier(
            const HubConfig(calendarSources: [_source, ha]),
          ),
        ),
        calendarWindowProvider.overrideWith((ref) => _window),
        icsDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        calendarSourceEventsProvider(
          ha.id,
        ).overrideWith((ref) => haFeed.stream),
      ],
    );
    addTearDown(c.dispose);
    c.listen(calendarEventsProvider, (_, _) {});
    haFeed.add(
      SourceEvents(
        status: SourceStatus.ok,
        events: [
          CalendarEvent(
            sourceId: ha.id,
            summary: 'Field trip',
            allDay: false,
            start: DateTime.utc(2026, 10, 6, 14),
            end: DateTime.utc(2026, 10, 6, 20),
          ),
        ],
      ),
    );

    final merged =
        await Future.doWhile(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return c
                      .read(calendarEventsProvider)
                      .sources[_source.id]
                      ?.status !=
                  SourceStatus.ok;
            })
            .timeout(const Duration(seconds: 10))
            .then((_) => c.read(calendarEventsProvider));

    expect(merged.events.map((e) => e.summary), [
      'Swim lessons',
      'Field trip',
      'Swim lessons',
      'Swim lessons (moved)',
    ]);
    expect(merged.sources.keys, [_source.id, ha.id]);

    // Moving the window re-expands; it does not refetch.
    c.read(calendarWindowProvider.notifier).state = DateTimeRange(
      start: DateTime.utc(2026, 10, 26),
      end: DateTime.utc(2026, 11, 2),
    );
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return c
          .read(calendarEventsProvider)
          .events
          .every((e) => e.start.isBefore(DateTime.utc(2026, 10, 26)));
    }).timeout(const Duration(seconds: 10));
    expect(adapter.requests, hasLength(1));
  });

  group('probe', () {
    const feed = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
        'X-WR-CALNAME:School\r\nX-APPLE-CALENDAR-COLOR:#1BADF8FF\r\n'
        'BEGIN:VEVENT\r\nUID:a\r\nSUMMARY:One\r\n'
        'DTSTART;VALUE=DATE:20261012\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:b\r\nSUMMARY:Two\r\n'
        'DTSTART;VALUE=DATE:20261013\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    Future<IcsProbe> probe(List<Object> replies) {
      adapter = _FakeAdapter(replies);
      return IcsCalendarSource.probe(
        'webcal://example.com/school.ics',
        dio: Dio()..httpClientAdapter = adapter,
        worker: _inline,
      );
    }

    test('reports the name, colour and event count from one fetch', () async {
      final result = await probe([_ok(feed)]);
      expect(result.name, 'School');
      expect(result.color, '#1BADF8FF');
      expect(result.eventCount, 2);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.toString(),
          'https://example.com/school.ics');
    });

    test('a 404 gives the same message a source shows', () async {
      expect(
        probe([
          DioException(
            requestOptions: RequestOptions(),
            response: Response(requestOptions: RequestOptions(), statusCode: 404),
            type: DioExceptionType.badResponse,
          ),
        ]),
        throwsA(isA<IcsProbeException>().having(
            (e) => e.message, 'message', 'Calendar not found at this URL')),
      );
    });

    test('a page that is not iCalendar is refused', () async {
      expect(
        probe([_ok('<html>Sign in</html>')]),
        throwsA(isA<IcsProbeException>().having((e) => e.message, 'message',
            'This URL is not an iCalendar feed')),
      );
    });
  });
}

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
