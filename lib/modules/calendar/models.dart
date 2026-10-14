enum CalendarSourceKind { ha, ics }

/// One configured calendar. Persisted in HubConfig.calendarSources.
class CalendarSource {
  /// `ha:calendar.family` or `ics:<uuid>`.
  final String id;
  final CalendarSourceKind kind;

  /// kind == ha; '' otherwise.
  final String entityId;

  /// kind == ics; stored as typed, `webcal://` included.
  final String url;

  /// Display name; defaults to HA friendly_name / X-WR-CALNAME.
  final String name;

  /// ARGB.
  final int color;
  final bool enabled;

  const CalendarSource({
    required this.id,
    required this.kind,
    this.entityId = '',
    this.url = '',
    this.name = '',
    this.color = defaultColor,
    this.enabled = true,
  });

  static const defaultColor = 0xFF646CFF; // the accent indigo

  CalendarSource copyWith({
    String? name,
    int? color,
    bool? enabled,
  }) =>
      CalendarSource(
        id: id,
        kind: kind,
        entityId: entityId,
        url: url,
        name: name ?? this.name,
        color: color ?? this.color,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'entityId': entityId,
        'url': url,
        'name': name,
        'color': color,
        'enabled': enabled,
      };

  factory CalendarSource.fromJson(Map<String, dynamic> json) {
    final kind = CalendarSourceKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => CalendarSourceKind.ha,
    );
    return CalendarSource(
      id: json['id'] as String? ?? '',
      kind: kind,
      entityId: json['entityId'] as String? ?? '',
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as int? ?? defaultColor,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarSource &&
      other.id == id &&
      other.kind == kind &&
      other.entityId == entityId &&
      other.url == url &&
      other.name == name &&
      other.color == color &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, kind, entityId, url, name, color, enabled);
}

/// One occurrence, already expanded. Immutable.
///
/// Timed events hold UTC instants, converted to the display zone at render
/// time. All-day events hold a calendar date as local midnight and are never
/// shifted by a zone. [end] is exclusive for both (RFC 5545 §3.8.2.2).
class CalendarEvent {
  final String sourceId;

  /// '' when the source gave none.
  final String uid;

  /// Identifies the instance within a series.
  final String? recurrenceId;
  final String summary;
  final String? description;
  final String? location;
  final bool allDay;

  /// allDay: local midnight of the first day.
  final DateTime start;

  /// Exclusive; allDay: local midnight after the last day.
  final DateTime end;
  final bool tentative;

  const CalendarEvent({
    required this.sourceId,
    this.uid = '',
    this.recurrenceId,
    required this.summary,
    this.description,
    this.location,
    required this.allDay,
    required this.start,
    required this.end,
    this.tentative = false,
  });

  /// Identity for diffing and widget keys.
  (String, String, Object) get key =>
      (sourceId, uid, recurrenceId ?? start);

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.sourceId == sourceId &&
      other.uid == uid &&
      other.recurrenceId == recurrenceId &&
      other.summary == summary &&
      other.description == description &&
      other.location == location &&
      other.allDay == allDay &&
      other.start == start &&
      other.end == end &&
      other.tentative == tentative;

  @override
  int get hashCode => Object.hash(sourceId, uid, recurrenceId, summary,
      description, location, allDay, start, end, tentative);

  @override
  String toString() =>
      'CalendarEvent($summary, ${allDay ? 'all-day ' : ''}$start – $end)';
}

enum SourceStatus { loading, ok, stale, error }

/// What one source currently has. A failed refresh keeps the last good
/// [events] and moves to [SourceStatus.stale].
class SourceEvents {
  final List<CalendarEvent> events;
  final SourceStatus status;
  final DateTime? lastOk;
  final String? error;

  const SourceEvents({
    this.events = const [],
    this.status = SourceStatus.loading,
    this.lastOk,
    this.error,
  });

  SourceEvents stale(String error) => SourceEvents(
      events: events, status: SourceStatus.stale, lastOk: lastOk, error: error);
}
