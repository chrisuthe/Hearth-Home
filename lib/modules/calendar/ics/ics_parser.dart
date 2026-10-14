/// An iCalendar (RFC 5545) reader for the parts a calendar view needs.
///
/// Written here because every published Dart parser loses data on ordinary
/// feeds (see docs/specs/2026-10-14-calendar-module-design.md, "ICS feeds").
/// It never throws for a whole feed: an event it cannot read is skipped and
/// counted in [IcsCalendar.skipped].
library;

/// How a DATE or DATE-TIME value is anchored (RFC 5545 §3.3.4, §3.3.5).
enum IcsTimeKind {
  /// `VALUE=DATE`: a calendar date, no time and no zone.
  date,

  /// `…Z`: an instant.
  utc,

  /// `TZID=`: a wall-clock time in a named zone.
  zoned,

  /// Neither: a wall-clock time wherever the viewer is.
  floating,
}

/// One DATE or DATE-TIME value, as written: wall-clock fields plus how to
/// anchor them. Turning it into an instant is the expander's job.
class IcsDateTime {
  final IcsTimeKind kind;
  final int year, month, day, hour, minute, second;

  /// kind == zoned only.
  final String? tzid;

  const IcsDateTime(
    this.kind,
    this.year,
    this.month,
    this.day, [
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
    this.tzid,
  ]);

  bool get isDate => kind == IcsTimeKind.date;

  /// The wall-clock fields as a UTC-flagged [DateTime], which is how `rrule`
  /// wants them: zone-less.
  DateTime get wall => DateTime.utc(year, month, day, hour, minute, second);

  @override
  bool operator ==(Object other) =>
      other is IcsDateTime &&
      other.kind == kind &&
      other.wall == wall &&
      other.tzid == tzid;

  @override
  int get hashCode => Object.hash(kind, wall, tzid);

  @override
  String toString() => '$kind $wall${tzid == null ? '' : ' $tzid'}';
}

class IcsEvent {
  final String uid;
  final String summary;
  final String? description;
  final String? location;

  /// Upper case, e.g. `CONFIRMED`, `TENTATIVE`, `CANCELLED`; null if absent.
  final String? status;
  final IcsDateTime start;
  final IcsDateTime? end;
  final Duration? duration;

  /// The rule's value, without the `RRULE:` name.
  final String? rrule;
  final List<IcsDateTime> exdates;
  final List<IcsDateTime> rdates;
  final IcsDateTime? recurrenceId;

  const IcsEvent({
    this.uid = '',
    this.summary = '',
    this.description,
    this.location,
    this.status,
    required this.start,
    this.end,
    this.duration,
    this.rrule,
    this.exdates = const [],
    this.rdates = const [],
    this.recurrenceId,
  });

  bool get cancelled => status == 'CANCELLED';
}

class IcsCalendar {
  /// `X-WR-CALNAME`.
  final String? name;

  /// `X-WR-TIMEZONE`, the fallback for a `TZID` we cannot resolve.
  final String? timezone;

  /// `X-APPLE-CALENDAR-COLOR`, as written (`#rrggbb` in the feeds we know).
  final String? color;
  final List<IcsEvent> events;

  /// The `TZID`s of the feed's `VTIMEZONE` components.
  final Set<String> timezoneIds;

  /// `VEVENT`s that could not be read.
  final int skipped;

  const IcsCalendar({
    this.name,
    this.timezone,
    this.color,
    this.events = const [],
    this.timezoneIds = const {},
    this.skipped = 0,
  });
}

/// One content line: `NAME;PARAM=value:VALUE` (RFC 5545 §3.1).
class IcsProperty {
  final String name;
  final Map<String, String> params;
  final String value;
  const IcsProperty(this.name, this.params, this.value);
}

class IcsParser {
  IcsParser._();

  static IcsCalendar parse(String text) {
    String? name, timezone, color;
    final events = <IcsEvent>[];
    final timezoneIds = <String>{};
    var skipped = 0;

    // Open components, innermost last. A VEVENT is read only directly under
    // VCALENDAR, and only its own properties are, so a VALARM inside it
    // doesn't leak its DESCRIPTION and an unknown component hides its body.
    final stack = <String>[];
    List<IcsProperty>? event;
    var eventDepth = 0;

    for (final line in unfold(text)) {
      final prop = parseLine(line);
      if (prop == null) continue;
      if (prop.name == 'BEGIN') {
        final component = prop.value.trim().toUpperCase();
        if (component == 'VEVENT' &&
            event != null &&
            stack.length == eventDepth) {
          // The previous VEVENT never ended; drop it, keep this one.
          skipped++;
          stack.removeLast();
          event = null;
        }
        final parent = stack.isEmpty ? '' : stack.last;
        stack.add(component);
        if (component == 'VEVENT' && parent == 'VCALENDAR') {
          event = [];
          eventDepth = stack.length;
        }
        continue;
      }
      if (prop.name == 'END') {
        final at = stack.lastIndexOf(prop.value.trim().toUpperCase());
        if (at < 0) continue;
        stack.removeRange(at, stack.length);
        if (event != null && stack.length < eventDepth) {
          final parsed = _event(event);
          if (parsed == null) {
            skipped++;
          } else if (!parsed.cancelled || parsed.recurrenceId != null) {
            // A cancelled override is kept: it deletes its instance.
            events.add(parsed);
          }
          event = null;
        }
        continue;
      }
      final top = stack.isEmpty ? '' : stack.last;
      if (event != null && stack.length == eventDepth) {
        event.add(prop);
      } else if (top == 'VTIMEZONE' && prop.name == 'TZID') {
        timezoneIds.add(prop.value.trim());
      } else if (top == 'VCALENDAR') {
        switch (prop.name) {
          case 'X-WR-CALNAME':
            name = unescapeText(prop.value);
          case 'X-WR-TIMEZONE':
            timezone = prop.value.trim();
          case 'X-APPLE-CALENDAR-COLOR':
            color = prop.value.trim();
        }
      }
    }
    // A feed cut off mid-event loses that event.
    if (event != null) skipped++;

    return IcsCalendar(
      name: name,
      timezone: timezone,
      color: color,
      events: events,
      timezoneIds: timezoneIds,
      skipped: skipped,
    );
  }

  static IcsEvent? _event(List<IcsProperty> props) {
    String uid = '', summary = '';
    String? description, location, status, rrule;
    IcsDateTime? start, end, recurrenceId;
    Duration? duration;
    final exdates = <IcsDateTime>[];
    final rdates = <IcsDateTime>[];

    for (final p in props) {
      switch (p.name) {
        case 'UID':
          uid = p.value;
        case 'SUMMARY':
          summary = unescapeText(p.value);
        case 'DESCRIPTION':
          description = unescapeText(p.value);
        case 'LOCATION':
          location = unescapeText(p.value);
        case 'STATUS':
          status = p.value.trim().toUpperCase();
        case 'DTSTART':
          start = parseDateTime(p.value, p.params);
          if (start == null) return null;
        case 'DTEND':
          end = parseDateTime(p.value, p.params);
        case 'DURATION':
          duration = parseDuration(p.value);
        case 'RRULE':
          rrule = p.value;
        case 'RECURRENCE-ID':
          recurrenceId = parseDateTime(p.value, p.params);
          if (recurrenceId == null) return null;
        case 'EXDATE':
          exdates.addAll(_dateList(p));
        case 'RDATE':
          rdates.addAll(_dateList(p));
      }
    }
    if (start == null) return null;
    return IcsEvent(
      uid: uid,
      summary: summary,
      description: description,
      location: location,
      status: status,
      start: start,
      end: end,
      duration: duration,
      rrule: rrule,
      exdates: exdates,
      rdates: rdates,
      recurrenceId: recurrenceId,
    );
  }

  /// A comma-separated EXDATE or RDATE value. An `RDATE;VALUE=PERIOD` keeps
  /// its start (§3.8.5.2). Values that do not parse are dropped.
  static Iterable<IcsDateTime> _dateList(IcsProperty p) sync* {
    for (final v in p.value.split(',')) {
      final t = parseDateTime(v.split('/').first, p.params);
      if (t != null) yield t;
    }
  }

  /// Joins folded lines: a line break followed by one space or TAB is
  /// removed, nothing else (§3.1). Accepts CRLF and bare LF.
  static List<String> unfold(String text) {
    final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    return unfolded
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
  }

  /// Splits a content line into name, parameters and value, honouring
  /// quoted parameter values (§3.1, §3.2). Null for a line without `:`.
  static IcsProperty? parseLine(String line) {
    var i = 0;
    while (i < line.length && line[i] != ';' && line[i] != ':') {
      i++;
    }
    if (i == line.length || i == 0) return null;
    final name = line.substring(0, i).trim().toUpperCase();
    final params = <String, String>{};

    while (line[i] == ';') {
      i++;
      final eq = line.indexOf('=', i);
      if (eq < 0) return null;
      final key = line.substring(i, eq).trim().toUpperCase();
      i = eq + 1;
      final value = StringBuffer();
      var quoted = false;
      while (i < line.length) {
        final c = line[i];
        if (c == '"') {
          quoted = !quoted;
        } else if (!quoted && (c == ';' || c == ':')) {
          break;
        } else {
          value.write(c);
        }
        i++;
      }
      if (i == line.length) return null;
      params[key] = value.toString();
    }
    return IcsProperty(name, params, line.substring(i + 1));
  }

  /// Unescapes a TEXT value: `\\`, `\;`, `\,`, `\n` and `\N` (§3.3.11).
  static String unescapeText(String value) {
    if (!value.contains(r'\')) return value;
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == r'\' && i + 1 < value.length) {
        final next = value[++i];
        out.write(next == 'n' || next == 'N' ? '\n' : next);
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  static final _dateTime = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$',
  );

  /// Parses a DATE (`20261014`) or DATE-TIME (`20261014T090000`, `…Z`)
  /// value with its `VALUE` and `TZID` parameters. Null if it doesn't parse.
  static IcsDateTime? parseDateTime(String value, Map<String, String> params) {
    final m = _dateTime.firstMatch(value.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    if (m[4] == null || params['VALUE']?.toUpperCase() == 'DATE') {
      return IcsDateTime(IcsTimeKind.date, y, mo, d);
    }
    final h = int.parse(m[4]!), mi = int.parse(m[5]!), s = int.parse(m[6]!);
    if (h > 23 || mi > 59 || s > 60) return null;
    // A leap second is read as the end of its minute.
    final sec = s == 60 ? 59 : s;
    if (m[7] == 'Z') return IcsDateTime(IcsTimeKind.utc, y, mo, d, h, mi, sec);
    final tzid = params['TZID']?.trim();
    if (tzid != null && tzid.isNotEmpty) {
      return IcsDateTime(IcsTimeKind.zoned, y, mo, d, h, mi, sec, tzid);
    }
    return IcsDateTime(IcsTimeKind.floating, y, mo, d, h, mi, sec);
  }

  static final _duration = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  );

  /// Parses a DURATION value such as `P2D`, `PT1H30M` or `P1W` (§3.3.6).
  static Duration? parseDuration(String value) {
    final v = value.trim();
    final m = _duration.firstMatch(v);
    if (m == null || v == 'P' || v.endsWith('T')) return null;
    int n(int g) => int.parse(m[g] ?? '0');
    final d = Duration(
      days: n(2) * 7 + n(3),
      hours: n(4),
      minutes: n(5),
      seconds: n(6),
    );
    return m[1] == '-' ? -d : d;
  }
}
