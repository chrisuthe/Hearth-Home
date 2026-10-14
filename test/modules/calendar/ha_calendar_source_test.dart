import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/ha_calendar_source.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/services/home_assistant_service.dart';

import '../../services/home_assistant_service_test.dart'
    show FakeWebSocketChannel;

Map<String, dynamic> _fixture(String name) => jsonDecode(
        File('test/fixtures/calendar/$name.json').readAsStringSync())
    as Map<String, dynamic>;

/// Answers `GET /api/calendars/...` with [body] and records each request.
class _FakeAdapter implements HttpClientAdapter {
  final Object body;
  final int status;
  final requests = <RequestOptions>[];
  _FakeAdapter(this.body, {this.status = 200});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _source = CalendarSource(
  id: 'ha:calendar.family',
  kind: CalendarSourceKind.ha,
  entityId: 'calendar.family',
  name: 'Family',
);

final _window = DateTimeRange(
  start: DateTime.utc(2026, 10, 5),
  end: DateTime.utc(2026, 11, 9),
);

void main() {
  group('HaCalendarSource.parseEvents', () {
    test('recurring series with one moved and one deleted instance', () {
      final fixture = _fixture('ha_recurring_with_exception');
      final events = HaCalendarSource.parseEvents(
          _source.id, fixture['websocket'] as List);

      expect(events, hasLength(3));
      expect(events.map((e) => e.recurrenceId),
          ['20261005T090000', '20261012T090000', '20261026T090000']);
      expect(events.every((e) => e.uid == 'standup@hearth'), isTrue);
      // The moved instance keeps its series identity at its new time.
      final moved = events[1];
      expect(moved.start, DateTime.utc(2026, 10, 13, 15));
      expect(moved.summary, 'Standup (moved)');
      expect(moved.location, 'Kitchen');
      // The deleted Monday is simply absent; HA expands, we do not.
      expect(events.where((e) => e.start.day == 19), isEmpty);
      expect(events[2].tentative, isTrue);
      expect(events[0].tentative, isFalse);
      expect(events[0].key, isNot(events[2].key));
    });

    test('timed events keep HA offsets across DST, whatever the device zone',
        () {
      final events = HaCalendarSource.parseEvents(
          _source.id, _fixture('ha_timed_offsets')['websocket'] as List);

      expect(events.every((e) => e.start.isUtc && !e.allDay), isTrue);
      // CDT (-05:00) before 2026-11-01, CST (-06:00) after: 09:00 local
      // both times, an hour apart in UTC.
      expect(events[0].start, DateTime.utc(2026, 10, 30, 14));
      expect(events[0].end, DateTime.utc(2026, 10, 30, 15));
      expect(events[1].start, DateTime.utc(2026, 11, 2, 15));
      expect(events[2].start, events[2].end, reason: 'zero length allowed');
    });

    test('all-day events are dates with an exclusive end', () {
      final events = HaCalendarSource.parseEvents(
          _source.id, _fixture('ha_all_day_multi_day')['websocket'] as List);

      final visit = events[0];
      expect(visit.allDay, isTrue);
      expect(visit.start, DateTime(2026, 10, 16));
      expect(visit.end, DateTime(2026, 10, 19));
      expect(visit.start.isUtc, isFalse);
      expect(visit.description, 'Bring the photos');
      final birthday = events[1];
      expect(birthday.start, DateTime(2026, 10, 14));
      expect(birthday.end, DateTime(2026, 10, 15));
    });

    for (final name in [
      'ha_recurring_with_exception',
      'ha_timed_offsets',
      'ha_all_day_multi_day',
    ]) {
      test('$name: REST shape parses to the WebSocket events', () {
        final fixture = _fixture(name);
        expect(
          HaCalendarSource.parseEvents(_source.id, fixture['rest'] as List),
          HaCalendarSource.parseEvents(
              _source.id, fixture['websocket'] as List),
        );
      });
    }

    test('skips an event it cannot read', () {
      final events = HaCalendarSource.parseEvents(_source.id, [
        {'summary': 'no start'},
        'not a map',
        {'start': '2026-10-14', 'end': '2026-10-15', 'summary': 'ok'},
      ]);
      expect(events.single.summary, 'ok');
    });
  });

  group('HaCalendarSource', () {
    late FakeWebSocketChannel channel;
    late HomeAssistantService ha;
    late List<SourceEvents> states;
    HaCalendarSource? source;

    setUp(() {
      channel = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(channel);
      states = [];
    });

    tearDown(() async {
      source?.dispose();
      source = null;
      ha.dispose();
      await channel.close();
    });

    Future<void> tick() => Future.delayed(const Duration(milliseconds: 20));

    // A REST round trip can outlast one tick when the whole suite is running.
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tick();
      }
    }

    List<Map<String, dynamic>> sent(FakeWebSocketChannel c) => c.sentMessages
        .map((m) => jsonDecode(m) as Map<String, dynamic>)
        .toList();

    Map<String, dynamic>? lastOfType(FakeWebSocketChannel c, String type) {
      final matches = sent(c).where((m) => m['type'] == type);
      return matches.isEmpty ? null : matches.last;
    }

    HaCalendarSource start({
      String haUrl = 'http://ha.local:8123/',
      Dio? dio,
      Duration connectTimeout = const Duration(seconds: 20),
    }) {
      final s = HaCalendarSource(
        ha: ha,
        source: _source,
        window: _window,
        haUrl: haUrl,
        haToken: 'token',
        dio: dio,
        connectTimeout: connectTimeout,
      );
      s.stream.listen(states.add);
      return source = s;
    }

    Future<int> connectAndSubscribe() async {
      ha.connect('token');
      channel.simulateMessage({'type': 'auth_ok'});
      await tick();
      return lastOfType(channel, 'calendar/event/subscribe')!['id'] as int;
    }

    void push(FakeWebSocketChannel c, int id, Object? events) =>
        c.simulateMessage({
          'id': id,
          'type': 'event',
          'event': {'events': events},
        });

    void fail(int id, String code) => channel.simulateMessage({
          'id': id,
          'type': 'result',
          'success': false,
          'error': {'code': code, 'message': code},
        });

    final pushA = _fixture('ha_all_day_multi_day')['websocket'] as List;
    final pushB = _fixture('ha_timed_offsets')['websocket'] as List;

    test('subscribes for the window; result then event fills the list',
        () async {
      start();
      final id = await connectAndSubscribe();
      final msg = lastOfType(channel, 'calendar/event/subscribe')!;
      expect(msg['entity_id'], 'calendar.family');
      expect(msg['start'], '2026-10-05T00:00:00.000Z');
      expect(msg['end'], '2026-11-09T00:00:00.000Z');

      channel.simulateMessage(
          {'id': id, 'type': 'result', 'success': true, 'result': null});
      await tick();
      expect(source!.current.status, SourceStatus.loading);

      push(channel, id, pushA);
      await tick();
      expect(source!.current.status, SourceStatus.ok);
      expect(source!.current.events.map((e) => e.summary),
          ['Grandma visit', 'Birthday']);
      expect(source!.current.events.first.sourceId, 'ha:calendar.family');
      expect(source!.current.lastOk, isNotNull);
      expect(states.first.status, SourceStatus.loading);
    });

    test('a second push replaces, not appends', () async {
      start();
      final id = await connectAndSubscribe();
      push(channel, id, pushA);
      push(channel, id, pushB);
      await tick();
      expect(source!.current.events.map((e) => e.uid), ['a', 'b', 'c']);
    });

    test('events: null keeps the old list and marks stale', () async {
      start();
      final id = await connectAndSubscribe();
      push(channel, id, pushA);
      push(channel, id, null);
      await tick();
      expect(source!.current.status, SourceStatus.stale);
      expect(source!.current.events, hasLength(2));
      expect(source!.current.error, isNotNull);
    });

    test('reconnect: stale while down, new id after auth_ok, old id ignored',
        () async {
      start();
      final oldId = await connectAndSubscribe();
      push(channel, oldId, pushA);
      await tick();

      await channel.close();
      await tick();
      expect(source!.current.status, SourceStatus.stale);
      expect(source!.current.events, hasLength(2));

      final second = FakeWebSocketChannel();
      ha.replaceChannel(second);
      ha.connect('token');
      second.simulateMessage({'type': 'auth_ok'});
      await tick();
      final newId = lastOfType(second, 'calendar/event/subscribe')!['id'];
      expect(newId, isNot(oldId));

      push(second, oldId, pushB);
      await tick();
      expect(source!.current.events.map((e) => e.uid), ['visit', 'bday']);
      push(second, newId as int, pushB);
      await tick();
      expect(source!.current.status, SourceStatus.ok);
      expect(source!.current.events.map((e) => e.uid), ['a', 'b', 'c']);
      await second.close();
    });

    test('unknown_command switches to REST with the same events', () async {
      final adapter = _FakeAdapter(
          _fixture('ha_recurring_with_exception')['rest'] as List);
      start(dio: Dio()..httpClientAdapter = adapter);
      final id = await connectAndSubscribe();
      fail(id, 'unknown_command');
      await until(() => source!.current.status != SourceStatus.loading);

      expect(adapter.requests, hasLength(1));
      final req = adapter.requests.single;
      expect(req.uri.path, '/api/calendars/calendar.family');
      expect(req.uri.queryParameters['start'], '2026-10-05T00:00:00.000Z');
      expect(req.headers['Authorization'], 'Bearer token');
      expect(source!.current.status, SourceStatus.ok);
      expect(
        source!.current.events,
        HaCalendarSource.parseEvents(_source.id,
            _fixture('ha_recurring_with_exception')['websocket'] as List),
      );

      // REST refetches on each auth_ok, and never resubscribes over WS.
      channel.simulateMessage({'type': 'auth_ok'});
      await tick();
      expect(adapter.requests, hasLength(2));
      expect(
          sent(channel)
              .where((m) => m['type'] == 'calendar/event/subscribe'),
          hasLength(1));
    });

    test('REST failure with nothing loaded is an error, not an exception',
        () async {
      final adapter = _FakeAdapter({'message': 'boom'}, status: 500);
      start(dio: Dio()..httpClientAdapter = adapter);
      final id = await connectAndSubscribe();
      fail(id, 'unknown_command');
      await tick();
      expect(source!.current.status, SourceStatus.error);
    });

    test('not_found reports an error and does not retry', () async {
      start();
      final id = await connectAndSubscribe();
      fail(id, 'not_found');
      await tick();
      expect(source!.current.status, SourceStatus.error);
      expect(source!.current.error, contains('not found'));

      channel.simulateMessage({'type': 'auth_ok'});
      await tick();
      expect(
          sent(channel)
              .where((m) => m['type'] == 'calendar/event/subscribe'),
          hasLength(1));
    });

    test('dispose (a window or config change) unsubscribes the id', () async {
      start();
      final id = await connectAndSubscribe();
      source!.dispose();
      await tick();
      expect(lastOfType(channel, 'unsubscribe_events')!['subscription'], id);
    });

    test('unconfigured HA is an error state', () async {
      start(haUrl: '');
      await tick();
      expect(states.last.status, SourceStatus.error);
      expect(channel.sentMessages, isEmpty);
    });

    test('unreachable HA times out to an error state', () async {
      start(connectTimeout: const Duration(milliseconds: 30));
      await Future.delayed(const Duration(milliseconds: 80));
      expect(source!.current.status, SourceStatus.error);
      expect(source!.current.error, contains("Can't reach"));
    });

    test('sends nothing but subscribe and unsubscribe', () async {
      start();
      final id = await connectAndSubscribe();
      push(channel, id, pushA);
      source!.dispose();
      await tick();
      final types = sent(channel).map((m) => m['type']).toSet();
      expect(types, {
        'subscribe_events',
        'get_states',
        'calendar/event/subscribe',
        'unsubscribe_events',
      });
    });
  });
}
