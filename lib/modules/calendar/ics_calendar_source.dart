import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../utils/logger.dart';
import 'ics/ics_expand.dart';
import 'ics/ics_parser.dart';
import 'models.dart';

/// Parses and expands off the UI isolate; tests pass one that runs inline.
typedef IcsWorker = Future<R> Function<R>(R Function() work);

Future<R> _isolateRun<R>(R Function() work) => Isolate.run(work);

/// Events of one ICS/iCal URL over a window.
///
/// Fetches with a conditional GET, parses and expands in a background
/// isolate, and polls. The parsed calendar is kept, so a new [window]
/// re-expands without refetching. A failed refresh keeps the last good
/// events as `stale` and retries after 1, 2, 4 … minutes, capped at the poll
/// interval; a 4xx other than 408/429 is `error` until the next poll.
/// Read-only.
class IcsCalendarSource {
  final CalendarSource source;
  final Duration _pollInterval;
  final Dio _dio;
  final IcsWorker _worker;

  static const maxBytes = 10 * 1024 * 1024;
  static const timeout = Duration(seconds: 20);

  final _controller = StreamController<SourceEvents>();
  SourceEvents _current = const SourceEvents();
  DateTimeRange _window;
  IcsCalendar? _calendar;
  String? _etag;
  String? _lastModified;
  int _failures = 0;
  int _generation = 0;
  Timer? _timer;
  bool _disposed = false;

  IcsCalendarSource({
    required this.source,
    required DateTimeRange window,
    Duration pollInterval = const Duration(minutes: 30),
    Dio? dio,
    IcsWorker? worker,
  }) : _window = window,
       _pollInterval = pollInterval,
       _worker = worker ?? _isolateRun,
       _dio = dio ?? newDio() {
    _emit(_current);
    _fetch();
  }

  static Dio newDio() =>
      Dio(BaseOptions(connectTimeout: timeout, receiveTimeout: timeout));

  Stream<SourceEvents> get stream => _controller.stream;
  SourceEvents get current => _current;
  DateTimeRange get window => _window;

  /// `webcal://` and `webcals://` are the same resource over HTTPS; other
  /// schemes pass through.
  static String normalizeUrl(String url) {
    final trimmed = url.trim();
    final match = RegExp(
      r'^webcals?://',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return trimmed;
    return 'https://${trimmed.substring(match.end)}';
  }

  /// Re-expands the kept calendar over [window]; no fetch.
  set window(DateTimeRange window) {
    if (window == _window) return;
    _window = window;
    final calendar = _calendar;
    if (calendar != null) _expand(calendar);
  }

  Future<void> _fetch() async {
    _timer?.cancel();
    final url = normalizeUrl(source.url);
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (_etag != null) 'If-None-Match': _etag,
            if (_lastModified != null) 'If-Modified-Since': _lastModified,
          },
          validateStatus: (s) => s != null && (s == 304 || s ~/ 100 == 2),
        ),
      );
      if (_disposed) return;
      if (response.statusCode == 304 && _calendar != null) {
        _failures = 0;
        _emit(
          SourceEvents(
            events: _current.events,
            status: SourceStatus.ok,
            lastOk: DateTime.now(),
          ),
        );
        _schedule(_pollInterval);
        return;
      }
      final body = await _read(response.data!);
      if (_disposed) return;
      final generation = ++_generation;
      final (calendar, events) = await _parseAndExpand(
        _worker,
        body,
        _window,
        source.id,
      );
      if (_disposed) return;
      if (calendar.skipped > 0) {
        Log.w(
          'Calendar',
          '${source.id}: skipped ${calendar.skipped} '
              'unreadable events',
        );
      }
      _calendar = calendar;
      _etag = response.headers.value('etag');
      _lastModified = response.headers.value('last-modified');
      _failures = 0;
      if (generation == _generation) {
        _ok(events);
      } else {
        // The window moved while this parse ran.
        _expand(calendar);
      }
      _schedule(_pollInterval);
    } catch (e) {
      if (_disposed) return;
      _onFailure(e);
    }
  }

  Future<String> _read(ResponseBody body) async {
    final length = int.tryParse(
      body.headers[Headers.contentLengthHeader]?.firstOrNull ?? '',
    );
    if (length != null && length > maxBytes) throw const _TooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) throw const _TooLarge();
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<void> _expand(IcsCalendar calendar) async {
    final generation = ++_generation;
    try {
      final events = await _expandIn(_worker, calendar, _window, source.id);
      if (_disposed || generation != _generation) return;
      _emit(
        SourceEvents(
          events: events,
          status: _current.status,
          lastOk: _current.lastOk,
          error: _current.error,
        ),
      );
    } catch (e) {
      Log.w('Calendar', '${source.id}: expand failed: $e');
    }
  }

  // Static, so the closures sent to the isolate capture only their arguments.
  static Future<(IcsCalendar, List<CalendarEvent>)> _parseAndExpand(
    IcsWorker worker,
    String body,
    DateTimeRange window,
    String id,
  ) => worker(() {
    final calendar = IcsParser.parse(body);
    return (calendar, expandIcs(calendar, window, id));
  });

  static Future<List<CalendarEvent>> _expandIn(
    IcsWorker worker,
    IcsCalendar calendar,
    DateTimeRange window,
    String id,
  ) => worker(() => expandIcs(calendar, window, id));

  void _onFailure(Object e) {
    final status = e is DioException ? e.response?.statusCode : null;
    if (status != null &&
        status >= 400 &&
        status < 500 &&
        status != 408 &&
        status != 429) {
      // A wrong URL doesn't get better by retrying sooner.
      Log.w('Calendar', '${source.id}: HTTP $status');
      _failures = 0;
      _emit(
        SourceEvents(
          events: _current.events,
          status: SourceStatus.error,
          lastOk: _current.lastOk,
          error: status == 404 || status == 410
              ? 'Calendar not found at this URL'
              : 'The server refused the calendar (HTTP $status)',
        ),
      );
      _schedule(_pollInterval);
      return;
    }

    final message = switch (e) {
      _TooLarge() => 'Calendar is larger than 10 MB',
      DioException(type: DioExceptionType.connectionTimeout) ||
      DioException(type: DioExceptionType.receiveTimeout) ||
      DioException(
        type: DioExceptionType.sendTimeout,
      ) => 'Calendar server timed out',
      DioException(response: Response(:final statusCode?)) =>
        "Can't read the calendar (HTTP $statusCode)",
      _ => "Can't reach the calendar server",
    };
    Log.w('Calendar', '${source.id}: fetch failed: $e');
    _emit(
      _current.lastOk != null
          ? _current.stale(message)
          : SourceEvents(
              events: _current.events,
              status: SourceStatus.error,
              error: message,
            ),
    );
    final minutes = 1 << (_failures < 20 ? _failures : 20);
    _failures++;
    final backoff = Duration(minutes: minutes);
    _schedule(backoff < _pollInterval ? backoff : _pollInterval);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, _fetch);
  }

  void _ok(List<CalendarEvent> events) {
    _emit(
      SourceEvents(
        events: events,
        status: SourceStatus.ok,
        lastOk: DateTime.now(),
      ),
    );
  }

  void _emit(SourceEvents value) {
    if (_disposed) return;
    _current = value;
    _controller.add(value);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _controller.close();
  }
}

class _TooLarge implements Exception {
  const _TooLarge();
}
