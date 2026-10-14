import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../services/home_assistant_service.dart';
import '../../utils/logger.dart';
import 'models.dart';

/// Events of one Home Assistant `calendar.*` entity over a fixed window.
///
/// Subscribes with `calendar/event/subscribe` (HA 2026.5.0+), which pushes
/// the whole expanded set on every change. On an older HA (`unknown_command`)
/// it polls `GET /api/calendars/<entity_id>` instead, for the life of the
/// instance. Read-only: it sends no create/update/delete command.
///
/// A new window or config means a new instance; [dispose] unsubscribes.
class HaCalendarSource {
  final HomeAssistantService _ha;
  final CalendarSource source;
  final DateTimeRange window;
  final String _haUrl;
  final String _haToken;
  final Duration _pollInterval;
  final Dio _dio;

  final _controller = StreamController<SourceEvents>();
  final List<StreamSubscription<void>> _subs = [];
  SourceEvents _current = const SourceEvents();
  void Function()? _unsubscribe;
  Timer? _connectTimer;
  Timer? _pollTimer;
  bool _disposed = false;

  HaCalendarSource({
    required HomeAssistantService ha,
    required this.source,
    required this.window,
    required String haUrl,
    required String haToken,
    Duration pollInterval = const Duration(minutes: 30),
    Duration connectTimeout = const Duration(seconds: 20),
    Dio? dio,
  })  : _ha = ha,
        _haUrl = haUrl.replaceAll(RegExp(r'/+$'), ''),
        _haToken = haToken,
        _pollInterval = pollInterval,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _emit(_current);
    if (_haUrl.isEmpty || _haToken.isEmpty) {
      _fail('Home Assistant is not configured');
      return;
    }
    _subs.add(_ha.onDisconnected.listen((_) {
      if (_current.status == SourceStatus.ok) {
        _emit(_current.stale('Lost connection to Home Assistant'));
      }
    }));
    // The service never surfaces a connect that never happens, so time it.
    _connectTimer = Timer(connectTimeout, () {
      if (_current.status == SourceStatus.loading) {
        _fail("Can't reach Home Assistant");
      }
    });
    _unsubscribe = _ha.subscribe(
      {
        'type': 'calendar/event/subscribe',
        'entity_id': source.entityId,
        'start': _iso(window.start),
        'end': _iso(window.end),
      },
      onEvent: _onPush,
      onError: _onSubscribeError,
    );
  }

  Stream<SourceEvents> get stream => _controller.stream;
  SourceEvents get current => _current;

  // UTC with `Z`: an offset datetime HA parses, and safe in a query string.
  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  void _onPush(Map<String, dynamic> event) {
    final events = event['events'];
    if (events is! List) {
      // HA sends null when the integration raised while fetching.
      _emit(_current.stale('Home Assistant could not read the calendar'));
      return;
    }
    _ok(parseEvents(source.id, events));
  }

  void _onSubscribeError(Map<String, dynamic> error) {
    _unsubscribe?.call();
    _unsubscribe = null;
    switch (error['code']) {
      case 'unknown_command':
        Log.i('Calendar', '${source.entityId}: no calendar/event/subscribe, '
            'polling REST');
        _startRest();
      case 'not_found':
        _fail('Entity not found in Home Assistant');
      default:
        _fail(error['message'] as String? ?? 'Home Assistant refused the '
            'calendar subscription');
    }
  }

  void _startRest() {
    _subs.add(_ha.onAuthenticated.listen((_) => _fetchRest()));
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetchRest());
    _fetchRest();
  }

  Future<void> _fetchRest() async {
    try {
      final response = await _dio.get<dynamic>(
        '$_haUrl/api/calendars/${source.entityId}',
        queryParameters: {'start': _iso(window.start), 'end': _iso(window.end)},
        options: Options(headers: {'Authorization': 'Bearer $_haToken'}),
      );
      if (_disposed) return;
      final data = response.data;
      if (data is! List) throw const FormatException('not a list');
      _ok(parseEvents(source.id, data));
    } catch (e) {
      if (_disposed) return;
      final message = e is DioException && e.response?.statusCode == 404
          ? 'Entity not found in Home Assistant'
          : "Can't read the calendar from Home Assistant";
      Log.w('Calendar', '${source.entityId}: REST fetch failed: $e');
      if (_current.lastOk != null) {
        _emit(_current.stale(message));
      } else {
        _fail(message);
      }
    }
  }

  void _ok(List<CalendarEvent> events) {
    _emit(SourceEvents(
        events: events, status: SourceStatus.ok, lastOk: DateTime.now()));
  }

  void _fail(String message) {
    _emit(SourceEvents(
        events: _current.events,
        status: SourceStatus.error,
        lastOk: _current.lastOk,
        error: message));
  }

  void _emit(SourceEvents value) {
    if (_disposed) return;
    _current = value;
    _controller.add(value);
  }

  /// Parses HA calendar events in either shape: the WebSocket push
  /// (`start` a string, `all_day`, nulls omitted) or the REST list (`start`
  /// a `{date}` / `{dateTime}` object, nulls present). An event that does
  /// not parse is skipped.
  static List<CalendarEvent> parseEvents(String sourceId, List<dynamic> raw) {
    final events = <CalendarEvent>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) continue;
      final start = _parseTime(e['start']);
      final end = _parseTime(e['end']);
      if (start == null || end == null) continue;
      events.add(CalendarEvent(
        sourceId: sourceId,
        uid: e['uid'] as String? ?? '',
        recurrenceId: e['recurrence_id'] as String?,
        summary: e['summary'] as String? ?? '',
        description: e['description'] as String?,
        location: e['location'] as String?,
        allDay: start.allDay,
        start: start.time,
        end: end.time,
        tentative: e['status'] == 'tentative',
      ));
    }
    return events;
  }

  /// A date (`2026-10-14`) becomes local midnight, untouched by any zone; a
  /// datetime with its offset becomes a UTC instant.
  static ({DateTime time, bool allDay})? _parseTime(dynamic value) {
    if (value is Map) value = value['dateTime'] ?? value['date'];
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    if (!value.contains('T')) {
      return (
        time: DateTime(parsed.year, parsed.month, parsed.day),
        allDay: true
      );
    }
    return (time: parsed.toUtc(), allDay: false);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _connectTimer?.cancel();
    _pollTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _controller.close();
  }
}
