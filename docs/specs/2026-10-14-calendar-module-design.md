# Calendar Module — Design

**Date:** 2026-10-14
**Status:** Design. No code yet.
**Goal:** Specify a read-only Calendar module that shows Home Assistant calendar entities and external ICS/iCal feeds, and break the work into the tasks the Calendar epic will follow.
**Tracking:** issue 214 (Skylight feature inventory). This builds Path A from that issue, Home Assistant as the source, and adds ICS URLs.

## How to read this

- **verified** — read in source at the commit or version under [Sources read](#sources-read). The file and line are named inline.
- **assumed** — reasoned from that source or from a standard, not settled by code we read or a test we ran.

Home Assistant paths are relative to `homeassistant/components/` in HA core.

## Sources read

| Short name | Repository / package | Version | Notes |
|---|---|---|---|
| HA core | `home-assistant/core` | tag `2026.10.1` (`abe1fdd7`) | `calendar/`, `local_calendar/`, `websocket_api/`, `config/entity_registry.py`, `helpers/entity_registry.py` |
| Hearth | this repository | `1dd331b` | |
| RFC 5545 | iCalendar | — | Section numbers cited inline |
| `rrule` | pub.dev, github.com/JonasWanke/rrule | `0.2.18` (2026-01-06) | Apache-2.0; pure Dart; pulls in `time` 2.1.6 (MIT) |
| `timezone` | pub.dev, dart-lang/labs `pkgs/timezone` | `0.11.2` (2026-10-12) | BSD-2-Clause; pure Dart; tzdb `2026e` |
| `icalendar_parser` | pub.dev, github.com/TesteurManiak/icalendar_parser | `2.1.0` (2024-09-26) | MIT; read, not chosen |
| `enough_icalendar` | pub.dev, github.com/Enough-Software/enough_icalendar | `0.17.0` (2025-08-19) | MPL-2.0; read, not chosen |
| `ical_parser`, `ical`, `icalendar` | pub.dev | `1.2.0`, `0.2.2`, `0.1.3` | read, not chosen |
| `flutter_timezone`, `flutter_native_timezone` | pub.dev | `5.1.1`, `2.0.0` | read, not chosen |
| `win2iana_tz_converter` | pub.dev | `0.1.3` | LGPL-3.0; read, not chosen |

Package paths below are relative to the package root of the version in this table.

## Scope

In scope:

- Events from Home Assistant `calendar.*` entities and from ICS/iCal URLs (`https://`, `http://`, `webcal://`).
- Four views: day/agenda, 3-day and week time grid with an all-day band, and a month grid. Plus a short "upcoming" glance on the idle Home screen.
- One colour per source.

Out of scope, on purpose:

- **Any write-back.** No create, edit or delete, on either source. HA gates those behind `CalendarEntityFeature.CREATE_EVENT` / `UPDATE_EVENT` / `DELETE_EVENT` and the `calendar/event/create|update|delete` commands (**verified**, `calendar/const.py:31-36`, `calendar/__init__.py:653-784`). Hearth sends none of them.
- **Chores and lists.** No HA `todo` entities, no chore chart, no shopping or to-do lists, no Skylight data.
- Per-person categories beyond "one source, one colour". In HA, one calendar per person already gives that.
- Reminders, notifications for upcoming events, per-event weather, event search.
- CalDAV, Google or Microsoft OAuth. Anything like that goes through HA, which already integrates them.

## Home Assistant calendar API

### The WebSocket subscription

`calendar/event/subscribe` exists (**verified**, `calendar/__init__.py:787-846`). It was added in #156340 (commit `61c02c854f`, 2026-04-07); the first release that contains it is **2026.5.0** (**verified**, `git tag --contains 61c02c854f`). `uid`, `recurrence_id` and `rrule` joined the pushed payload in #168318 (`0c2dd5b02f`), also first released in 2026.5.0. So every HA that has the command sends those fields.

Request:

```json
{"id": 42, "type": "calendar/event/subscribe",
 "entity_id": "calendar.family",
 "start": "2026-10-12T00:00:00-05:00",
 "end":   "2026-10-19T00:00:00-05:00"}
```

`entity_id` must be in the `calendar` domain, `start`/`end` are datetimes, and `start` must be before `end` (**verified**, `:787-822`). The user needs read permission on the entity (`:802-803`).

Responses, all carrying the request's `id`:

1. `{"type":"result","success":true,"result":null}` — sent before any events (`:843`, `send_result` with no payload).
2. `{"type":"event","event":{"events":[ ... ]}}` — the first set, pushed only to this subscriber (`:845-846`).
3. Further `event` messages with the whole set again whenever it may have changed. Each push replaces the previous set; there are no deltas.
4. `"events": null` when the integration raised while fetching (`:522-532`). Treat it as "keep what you have and mark the source stale", not as an empty calendar.

Errors arrive as `result` with `success:false`: `not_found` for an unknown entity, `invalid_format` for `start >= end` (`:805-822`), and `unknown_command` on an HA older than 2026.5.0 (**verified**, `websocket_api/const.py:42`, `websocket_api/connection.py:238`).

Unsubscribe with the generic `{"type":"unsubscribe_events","subscription":42}` (**verified**, `websocket_api/commands.py:247-262`); the calendar subscription lives in the same `connection.subscriptions` map (`calendar/__init__.py:840`).

**When pushes happen.** The entity re-pushes from `_async_write_ha_state`, debounced with a 1 s cooldown that fires immediately on the first call (**verified**, `calendar/__init__.py:96`, `375-377`, `451-458`). An entity writes state when it updates, and at the start and end of its next event (`:399-409`). So a push follows the integration's own refresh (`SCAN_INTERVAL` is 60 s for polled calendars, `:95`), not the remote calendar change itself. Since 2026.10.0, listeners on the same range share one fetch (#182013, **verified**, `:479-490`); Hearth does not depend on that.

**The window is fixed.** The range is stored with the listener when it subscribes (`:460-461`) and every later push uses it. Moving the window, at midnight or when the user pages to another month, means unsubscribing and subscribing again.

### The pushed event payload

Each element of `events` is `CalendarEvent.as_dict()`: the dataclass through `event_dict_factory`, plus `all_day` (**verified**, `calendar/__init__.py:178-213`, `calendar/helper.py:158-166`):

| Key | Type | Notes |
|---|---|---|
| `start`, `end` | string | `date.isoformat()` (`"2026-10-14"`) for all-day, `datetime.isoformat()` with offset in HA's configured zone for timed (`as_local_timezone`, `__init__.py:127`) |
| `summary` | string | always present |
| `description`, `location` | string | omitted when null |
| `uid` | string | omitted when null |
| `recurrence_id` | string | set on an instance of a recurring event; omitted otherwise |
| `rrule` | string | the series rule, e.g. `FREQ=WEEKLY;BYDAY=MO`; informational only, see below |
| `status` | string | `confirmed` or `tentative`; added in 2026.10.0 (#179312, `f945b3d2ff`). Cancelled events are never returned (`const.py:39-52`) |
| `all_day` | bool | `true` when `start` is a date |

`start` and `end` are always the same type (`has_same_type`, `__init__.py:125`). The all-day `end` is exclusive: an all-day event whose start equals its end is widened to one day (`:228-236`), which only makes sense for an exclusive end. Timed events may have zero length (`MIN_EVENT_DURATION = 0`, `helper.py:24-26`).

**Recurrences are expanded by HA.** `async_get_events(start, end)` returns the event instances in the range (`__init__.py:538-545`); `local_calendar`, for example, returns the overlapping instances of its timeline, each with its own `recurrence_id` (**verified**, `local_calendar/calendar.py:101-113`, `249-273`). Hearth never expands an HA `rrule`. That holds for each integration that follows the base-class contract; we read `local_calendar` only, and assume the others (Google, CalDAV) do the same, since the HA frontend's calendar panel relies on it.

### The REST fallback, for HA before 2026.5.0

`GET /api/calendars/<entity_id>?start=<iso>&end=<iso>` with `Authorization: Bearer <token>` (**verified**, `calendar/__init__.py:571-623`). It needs read permission, returns 400 when either bound is missing or `start > end`, and 500 with a message when the integration raises. The body is a JSON list of the same events through `api_event_dict_factory` (`helper.py:169-179`), which differs from the WebSocket shape:

- `start` / `end` are objects: `{"date": "2026-10-14"}` or `{"dateTime": "2026-10-14T09:00:00-05:00"}`.
- Null fields are present as `null` instead of omitted.
- There is no `all_day` key; it is the presence of `date`.

`GET /api/calendars` lists `{name, entity_id}` for every calendar the user can read (`:626-650`). The settings picker uses the entity cache instead, which already holds every `calendar.*` state.

### Calendar colour

Since 2026.2.0 an integration can give a calendar an `initial_color`; HA validates it as `#rrggbb` and stores it once, as the entity's registry options `{"calendar": {"color": "#rrggbb"}}` (**verified**, `calendar/__init__.py:271-322`, commits `b13c2e3018` and `16fd5e8f1f`). It is not a state attribute. A client reads it with `config/entity_registry/get_entries` (`{"entity_ids": [...]}`), which needs no admin and returns `extended_dict`, including `options` (**verified**, `config/entity_registry.py:94-114`, `helpers/entity_registry.py:369-400`). Hearth already uses the admin-free `config/entity_registry/list` through `getEntityRegistry()`; `list` returns `partial_json_repr`, which is built from `as_partial_dict` and also has `options` (`entity_registry.py:369-400`, `417-430`), so either works.

That the HA frontend's calendar colour picker writes to this same key is **assumed**; we did not read the frontend. Hearth uses it only as the default for a new HA source, so a missing or different value costs a default colour, nothing more.

## ICS feeds

An ICS feed needs three jobs done: parse the text, expand the recurrence rules, and turn `TZID` wall-clock times into instants. We use two packages and write the parser ourselves.

### Choice

| Job | Choice | Licence | Why |
|---|---|---|---|
| Parse | **Our own**, `lib/modules/calendar/ics/ics_parser.dart`, about 300–400 lines | ours | Every published parser loses data on ordinary feeds; see below |
| Expand `RRULE` | **`rrule` 0.2.18** | Apache-2.0 | The only maintained Dart RRULE engine. All of RFC 5545 §3.3.10: `FREQ` from `SECONDLY` to `YEARLY`, `INTERVAL`, `COUNT`, `UNTIL`, every `BY*` part including `BYSETPOS` and `BYWEEKNO` (**verified**, `lib/src/codecs/string/decoder.dart`) |
| Zones | **`timezone` 0.11.2**, `package:timezone/data/latest_all.dart` | BSD-2-Clause | The IANA database as Dart data (tzdb `2026e`, **verified**, header of `lib/data/latest_all.dart`). `latest_all` (441 KB) rather than `latest_10y` because it keeps the backward aliases such as `US/Eastern` that feeds still use, and the history needed for a series that started years ago |

All three pieces are pure Dart, so they run the same on flutter-pi, Android and desktop. Neither package is a Hearth dependency today (**verified**, `pubspec.lock`). Being Dart packages, they reach `THIRD_PARTY_NOTICES.md` through the generator without a manual entry.

**Why not a published parser.** Read at the versions in [Sources read](#sources-read):

- `icalendar_parser` 2.1.0 trims every content line and the whole continuation, so a space at a fold boundary is lost, and only a leading space (not TAB) counts as a fold (`lib/src/model/icalendar.dart:297-306`; RFC 5545 §3.1 allows either). Parameters are split on `;` and `:` without honouring quotes (`:309-331`). Only `\,` is unescaped; its `\n` unescape is a JavaScript-style regex string that never matches (`lib/src/utils/parsing_methods.dart:31`). `RECURRENCE-ID`, `RDATE` and `DURATION` are not known fields and are dropped (`icalendar.dart:114-229`). `VALUE=DATE` is ignored and `TZID` is not applied when converting to `DateTime`.
- `enough_icalendar` 0.17.0 parses parameters properly but throws on the whole feed for an unknown component (`lib/src/components.dart:286`), a `VEVENT` without `DTSTAMP` or `UID` (`:1048-1052`), or `EXDATE;VALUE=DATE:` with more than one date (`lib/src/properties.dart:186-196`, `lib/src/types.dart:1167`). A single bad event in a school's feed would blank the calendar. It also leaves `\;` and `\\` escaped (`properties.dart:1009-1013`), does not apply `TZID` (`types.dart:1180`), contains `print` calls, and is MPL-2.0.
- `ical_parser`, `ical` and `icalendar` are smaller still: no parameter parsing, a generator only, and no unfolding, respectively.

Writing the parser costs a few hundred lines that the tests pin down. It fixes all of the above and never throws for a whole feed: an event it cannot read is skipped and counted.

### The parser

`IcsParser.parse(String) → IcsCalendar`:

- Unfold: a CRLF or bare LF followed by exactly one space or TAB is removed, nothing else (RFC 5545 §3.1).
- Content lines: name, then `;`-separated parameters with quoted values honoured, then `:` and the value (§3.1, §3.2).
- `TEXT` values: unescape `\\`, `\;`, `\,`, `\n` and `\N` (§3.3.11).
- Components: `VCALENDAR`, `VEVENT`, `VTIMEZONE` (kept only for its `TZID`); anything else is skipped with its nested contents. Repeated properties stay lists (`EXDATE`, `RDATE` may appear many times, §3.8.5.1–2).
- Calendar properties: `X-WR-CALNAME`, `X-WR-TIMEZONE`, `X-APPLE-CALENDAR-COLOR` (all non-standard; used as defaults only).
- Per event: `UID`, `SUMMARY`, `DESCRIPTION`, `LOCATION`, `STATUS`, `DTSTART`, `DTEND` or `DURATION`, `RRULE`, `EXDATE`, `RDATE`, `RECURRENCE-ID`. Each date value parses to one of four kinds: **date** (`VALUE=DATE`, §3.3.4), **UTC** (`…Z`), **zoned** (`TZID=`), **floating** (neither, §3.3.5).
- `STATUS:CANCELLED` events are dropped, matching what HA returns (`calendar/const.py:39-52`).

### Expansion

`expand(IcsCalendar, DateTimeRange window) → List<CalendarEvent>`, per `UID`:

1. Resolve the zone of `DTSTART`: the `TZID` as an IANA name; else the Windows name mapped to IANA (below); else `X-WR-TIMEZONE`; else the device zone. Floating times use the device zone. Dates use no zone.
2. Duration: `DTEND − DTSTART`, else `DURATION` (§3.8.2.5), else one day for a date and zero for a date-time (§3.6.1).
3. No `RRULE`: one instance.
4. With `RRULE`: expand in **wall-clock time**. `rrule` wants `DateTime`s marked `isUtc` but treats them as zone-less (**verified**, `lib/src/utils.dart:119`), which is what keeps a 09:00 meeting at 09:00 across a DST change. We pass `DTSTART`'s wall time, and turn each result into an instant with `TZDateTime(location, y, m, d, h, mi, s)`, which resolves DST gaps and overlaps (`timezone`, `lib/src/location.dart:80-103`).
5. Add `RDATE` instances; remove `EXDATE` instances, matching on the instant (or the date for all-day), each `EXDATE` line with its own `TZID` (§3.8.5.1–2).
6. Apply overrides: a `VEVENT` with the same `UID` and a `RECURRENCE-ID` replaces the instance whose original start equals that `RECURRENCE-ID` (§3.8.4.4). A cancelled override removes it.
7. Keep instances overlapping the window.

Expansion runs `getInstances(start: dtstart, before: window.end)` with a hard cap of 2,000 instances per event, because `rrule`'s `before` is a filter inside the loop (`lib/src/iteration/iteration.dart:60-63`) and a rule that never matches would otherwise run to year 9999.

### What the packages don't handle, and we do

| Gap | Where | What we do |
|---|---|---|
| `EXDATE`, `RDATE`, `RECURRENCE-ID` | `rrule` handles `RRULE` only | Steps 5 and 6 above |
| `WKST` other than `MO` throws | `rrule`, `decoder.dart:203-215`; Google emits `WKST=SU` | Strip `WKST` before decoding. It only changes results for `WEEKLY` with `INTERVAL>1` and `BYDAY` crossing the week start, or `BYWEEKNO`; that case is a known gap |
| `UNTIL` in UTC read as wall time | `rrule`, `decoder.dart:88-109` drops the `Z` | Convert a UTC `UNTIL` into `DTSTART`'s zone and wall time before decoding |
| Windows zone names (`Central Standard Time`) | not in `timezone` (no match in `lib/`) | Embed the CLDR `windowsZones.xml` territory-`001` table (about 140 rows) as a Dart map. Unicode licence; needs an entry in `assets/licenses/notices.json`. `win2iana_tz_converter` does this but is LGPL-3.0 |
| A `TZID` that exists only as a custom `VTIMEZONE` | not modelled by `timezone` | Not handled: fall back as in step 1 and log the `TZID`. Real feeds name IANA or Windows zones |
| `RECURRENCE-ID;RANGE=THISANDFUTURE` | §3.8.4.4 | Not handled: treated as a single-instance override. Publishers we know of split the series instead |
| Device zone name | `timezone`'s `tz.local` defaults to UTC (`lib/src/env.dart:56`) | Not needed for display (`DateTime.toLocal()`); for floating times, `setLocalLocation(getLocation(config.timezone))`, falling back to `TimezoneService.getCurrentTimezone()` on Linux and to the OS offset elsewhere |

`flutter_timezone` 5.1.1 reports the OS zone on Android and desktop, but on Linux it is a GTK plugin (`linux/flutter_timezone_plugin.cc:33-68`), and flutter-pi does not load GTK desktop plugins (**assumed** from flutter-pi's design, not tried). We don't need it: on the Pi, `TimezoneService` already reads the zone with the same commands in Dart. `flutter_native_timezone` is abandoned (2021) and has no Linux or Windows build.

## Data model

`lib/modules/calendar/models.dart`:

```dart
enum CalendarSourceKind { ha, ics }

/// One configured calendar. Persisted in HubConfig.calendarSources.
class CalendarSource {
  final String id;              // 'ha:calendar.family' or 'ics:<uuid>'
  final CalendarSourceKind kind;
  final String entityId;        // kind == ha; '' otherwise
  final String url;             // kind == ics; stored as typed, webcal:// included
  final String name;            // display name; defaults to HA friendly_name / X-WR-CALNAME
  final int color;              // ARGB
  final bool enabled;
}

/// One occurrence, already expanded. Immutable.
class CalendarEvent {
  final String sourceId;
  final String uid;             // '' when the source gave none
  final String? recurrenceId;   // identifies the instance within a series
  final String summary;
  final String? description;
  final String? location;
  final bool allDay;
  final DateTime start;         // allDay: local midnight of the first day
  final DateTime end;           // exclusive; allDay: local midnight after the last day
  final bool tentative;
}
```

- Timed events hold UTC `DateTime`s, converted to the display zone at render time. All-day events hold a calendar date only (y/m/d as a local `DateTime` at midnight) and are never shifted by a zone: a birthday stays on its date wherever the kiosk is.
- `end` is exclusive for both, matching HA and RFC 5545 §3.8.2.2 (`DTEND` is the non-inclusive end).
- A multi-day event is one `CalendarEvent`. Views split it per day when they lay it out.
- Event identity for diffing and keys is `(sourceId, uid, recurrenceId ?? start)`.
- No `rrule` field. Both sources hand the views expanded instances.

## Configuration

New `HubConfig` fields, persisted like every other field (`copyWith`, `toJson`, `fromJson` with defaults):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `calendarSources` | `List<CalendarSource>` | `[]` | The calendars, in display order (legend and tie-break order) |
| `calendarIcsPollMinutes` | `int` | `30` | How often each ICS URL is fetched; clamped to 5–1440 |
| `calendarAmbientGlance` | `bool` | `true` | Show the upcoming-events glance on the idle Home screen |
| `calendarDefaultView` | `String` | `'week'` | `day`, `3day`, `week` or `month`; the view the screen opens in |

Colour defaults: an HA source takes its registry colour when it has one, otherwise the next colour from a fixed eight-colour palette led by the accent indigo `0xFF646CFF`. An ICS source takes `X-APPLE-CALENDAR-COLOR` when the feed has one (a non-standard property Apple and Google emit; **assumed** from feeds, not read in code), otherwise the palette. The colour is stored at the moment the source is added, and the user can change it; Hearth never re-reads it.

Nothing else is stored. Events are not cached to disk: on boot each source refetches. A kiosk that boots without a network shows an empty calendar with a "can't reach" note per source, which is honest and avoids a cache-invalidation story.

ICS URLs can carry a secret (Google's "secret address in iCal format"). They are stored in `hub_config.json` like the HA token already is, and the `:8090` portal shows them masked, using the password field.

## Providers

All in `lib/modules/calendar/calendar_providers.dart`. Each source is a *self-initializing provider*, as in CLAUDE.md: it watches its own config and the window, and Riverpod rebuilds it when either changes. There is no init call in `main.dart`.

```
calendarWindowProvider            StateProvider<DateTimeRange>
   │  the range the screen is showing, widened to whole weeks;
   │  defaults to [start of this week − 7 d, end of next month)
   │
calendarSourceEventsProvider      StreamProvider.family<SourceEvents, String>(sourceId)
   │  watches the source's config entry and the window
   │  ha  → HaCalendarSource   (WS subscribe; REST fallback)
   │  ics → IcsCalendarSource  (fetch, parse, expand; poll)
   │
calendarEventsProvider            Provider<MergedEvents>
      watches every enabled source; merges, sorts by (start, allDay first, source order)
      and carries per-source status for the legend
```

`SourceEvents` is `{List<CalendarEvent> events, SourceStatus status, DateTime? lastOk, String? error}`, with `SourceStatus` one of `loading`, `ok`, `stale`, `error`. A failed refresh keeps the last good events and moves to `stale`, so a flaky feed does not blank the screen.

The window is one shared range, not one per view, so switching between day, week and month inside it costs nothing. It is wide enough for the default views and the ambient glance (which needs only the next 7 days). Paging outside it moves it, which resubscribes HA sources and re-expands (but does not refetch) ICS sources. A midnight timer moves it when "today" leaves the first week.

The glance does not keep the window alive on its own: `calendarEventsProvider` is watched by HubShell's Home screen, which is always built, so the sources stay live as long as at least one source is enabled and either the module is placed or the glance is on.

### HA source

`HaCalendarSource` needs two small changes to `HomeAssistantService` (`lib/services/home_assistant_service.dart`):

1. **Route `event` messages by subscription id.** Today `_handleEvent` assumes every `event` is `state_changed` and drops anything without `event.data.new_state` (`:216-232`), so a calendar push would vanish silently. Add `Map<int, void Function(Map<String, dynamic>)> _eventHandlers`; `_handleMessage` looks up `msg['id']` there first and only falls through to the existing state-changed handling when it is absent.
2. **Resubscribe after reconnect.** Add `Stream<void> get onAuthenticated`, fired on every `auth_ok` (`:142-145`). Subscriptions die with the socket, and `_msgId` keeps counting, so a subscriber must send a new subscribe on each `auth_ok` and register the new id. The service exposes this as one method that hides both:

   ```dart
   /// Sends [message] as a subscription now and after every reconnect.
   /// [onEvent] gets each `event` payload; [onError] the failed `result`.
   /// The returned function unsubscribes and stops resubscribing.
   void Function() subscribe(Map<String, dynamic> message,
       {required void Function(Map<String, dynamic> event) onEvent,
        void Function(Map<String, dynamic> error)? onError});
   ```

   It also clears its handlers in `dispose`. `connect()`'s `onDone` already completes pending responses with `null`; subscriptions need nothing there because the next `auth_ok` replays them.

`HaCalendarSource` then:

- calls `subscribe({'type':'calendar/event/subscribe', entity_id, start, end}, ...)` with the window as offset datetimes;
- on each event replaces its list with the parsed `events` (or marks `stale` on `null`);
- on `unknown_command` switches to REST for the life of the instance: `GET {haUrl}/api/calendars/{entity_id}?start=&end=` through `dio` with the HA token, every `calendarIcsPollMinutes`, and again on each `auth_ok`;
- on `not_found` reports `error` ("entity not found in Home Assistant") and does not retry until config changes;
- is disposed, and so unsubscribes, when its config entry or the window changes.

While the socket is down the source keeps its events and shows `stale`; the service's own backoff (1 s doubling to 30 s, `:116-135`) is the only retry loop.

### ICS source

`IcsCalendarSource`:

1. Normalise the URL: `webcal://` → `https://`, `webcals://` → `https://`; other schemes pass through. `webcal` is a de facto scheme (an IANA provisional registration), not part of RFC 5545, and every publisher we know of serves the same resource over HTTPS.
2. `GET` with `dio`, a 20 s timeout, `If-None-Match` / `If-Modified-Since` from the last good response, and a body cap of 10 MB. A 304 keeps the parsed calendar.
3. Parse and expand in a background isolate (`Isolate.run`, which initialises the zone database there too), because a large feed with a long-running series is a few hundred milliseconds of work on a Pi 5 (**assumed**; to be measured in the ICS task). The parsed calendar is kept, so a window change re-expands without refetching.
4. Poll every `calendarIcsPollMinutes`. On failure, retry after 1, 2, 4 … minutes capped at the poll interval, keep the last good events, and report `stale` with the error. A 4xx other than 408/429 is `error` and waits a full poll interval: a wrong URL does not get faster by retrying.

## Time zones

The display zone is the device zone. On the Pi that is `HubConfig.timezone` applied at boot: `main.dart` calls `TimezoneService.applyTimezone`, which runs `timedatectl set-timezone` or rewrites `/etc/localtime` (**verified**, `lib/services/timezone_service.dart:38-85`, `lib/main.dart:92-101`); an empty value leaves the system zone; on Android and desktop it is the OS zone. Dart's `DateTime.toLocal()` uses the process zone, so converting a UTC instant for display needs no zone database.

The zone database is needed only for ICS input: a `TZID=America/Chicago` `DTSTART` is a wall-clock time in a named zone, and its instants (and those of every recurrence, across DST changes) come from that zone's rules. See [ICS feeds](#ics-feeds) for the package.

HA needs no zone work: it sends offsets on every timed event, and all-day events are dates.

## The module

`lib/modules/calendar/calendar_module.dart`:

```dart
class CalendarModule implements HearthModule {
  @override String get id => 'calendar';
  @override String get name => 'Calendar';
  @override IconData get icon => Icons.calendar_month;
  @override int get defaultOrder => 5;     // right of Home, left of Controls (10)
  @override bool isConfigured(HubConfig c) =>
      c.calendarSources.any((s) => s.enabled);
  @override Widget buildScreen({required bool isActive}) =>
      CalendarScreen(isActive: isActive);
  @override Widget? buildSettingsSection() => null;
  @override bool get isCommunity => false;
}
```

It goes into `_staticModules` in `lib/modules/module_registry.dart`. It is not added to `HubConfig.defaultModulePlacements`: like Recipes, a user places it from Screens & Order once a source exists. With it placed, the default order becomes `Media(-10) ← AlarmClock(-5) ← Home → Calendar(5) → Controls(10) → …`; CLAUDE.md's "Screen order" line gets Calendar added in the screen task.

An unconfigured module shows a one-line prompt pointing to Settings → Calendar, the same pattern as the other modules.

## The settings plugin

`lib/plugins/calendar/calendar_plugin.dart`, id `hearth.calendar`, category `feature`, registered in `_firstPartyPlugins`. Always visible. Like the other plugins it renders the device panel and the `:8090` fragment from one definition.

- **Sources** — a `ListSection<CalendarSource>`. Each row shows a colour swatch, the name, the kind, and the source's live status (`ok`, `stale` with "last updated 10:42", `error` with the message).
  - *Add Home Assistant calendar*: an entity picker filtered to `calendar.*` (`ha_entity_picker_field.dart`), then name and colour prefilled from the entity and the registry.
  - *Add ICS URL*: URL, name, colour. Saving does one fetch and shows the feed's `X-WR-CALNAME` and event count, or the error, before it is stored.
  - Edit: name, colour, enabled. Kind and entity/URL are fixed once added; delete and re-add to change them.
- **ICS refresh interval** — select: 15 min, 30 min, 1 h, 6 h, 24 h.
- **Show upcoming events when idle** — the glance toggle.
- **Default view** — select.

The `ListSection` HTML render is read-only (`lib/plugins/framework/list_section.dart:11-15`), so adding a source on the portal needs plugin routes: `POST /api/plugin/hearth.calendar/sources`, `PUT …/sources/<id>`, `DELETE …/sources/<id>`, and `POST …/test` for the one-shot ICS check. The plugin is always visible, so no extra gate is needed, but each handler validates its input itself.

## Views

All four views share a header: `‹ Today ›`, the visible range ("October 12–18"), a view switcher, and a legend of source swatches that toggles each source on screen only (not saved). A tap on an event opens a read-only detail sheet: summary, time, location, description, source. No other gestures besides horizontal paging inside the view; the module itself lives in HubShell's PageView, so paging between ranges uses the arrows, not swipes, to avoid fighting the outer PageView.

Every view branches on the constraints from `LayoutBuilder`, never on `displayOrientation`.

### 1184x864 (landscape)

```
┌──────────────────────────────────────────────────────────────┐
│ ‹ Today ›  Oct 12–18, 2026        Day 3-Day [Week] Month  ●●● │
├──────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┤
│      │ Mon12 │ Tue13 │ Wed14 │ Thu15 │ Fri16 │ Sat17 │ Sun18 │
├──────┼───────┴───────┼───────┼───────┴───────┴───────┼───────┤  all-day band
│      │ Grandma visit │       │ School break          │       │  (max 3 rows,
├──────┼───────┬───────┼───────┼───────┬───────┬───────┼───────┤   "+2 more")
│  8am │ ▇▇▇▇▇ │       │ ▇▇▇▇▇ │       │       │       │       │
│  9am │ ▇▇▇▇▇ │ ▇▇▇   │       │       │       │       │       │
│ 10am │       │ ▇▇▇   │ ─now─ │       │       │       │       │
│  …   │  scrolls vertically, opens at 7am or the current hour   │
└──────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘
```

- **Week** is the default. Hours scroll; the view opens with 7 am at the top, or the current hour when today is visible. Overlapping timed events split the column width.
- **3-day**: the same grid with three wider columns starting today.
- **Day/agenda**: the left half a one-column time grid, the right half the agenda list of the next seven days.
- **Month**: six week rows, each day showing up to three event chips and "+n". Multi-day events draw as a continuous bar across days within a week row.

### 864x1184 and 800x1280 (portrait)

```
┌──────────────────────────────┐
│ ‹ Today ›  Oct 14–16         │
│ Day [3-Day] Week Month   ●●● │
├────┬─────────┬────────┬──────┤
│    │  Wed14  │ Thu15  │ Fri16│
├────┼─────────┴────────┼──────┤
│    │ School break     │      │
├────┼─────────┬────────┼──────┤
│ 8am│ ▇▇▇▇▇   │        │      │
│ 9am│         │ ▇▇▇▇   │      │
│ …  │                         │
└────┴─────────────────────────┘
```

- The header wraps to two lines.
- Below a usable width of about 900 px, **Week** shows as 3-day with a note "Week view needs a wider screen" in the switcher's tooltip, and the default view `week` opens as `3day`. Seven columns at 800 px leave about 100 px each, too narrow for a title.
- **Day/agenda** stacks: the time grid above, the agenda list below.
- **Month** keeps six rows, which become taller, and shows dots instead of chips under about 120 px per cell, with the day's list under the grid when a day is tapped.

The thresholds are logical pixels after `uiScale`. They are a starting point for the screen task to tune on the panel.

## The ambient glance

The idle state is HubShell returning to the Home page (`lib/app/hub_shell.dart:327-342`), and the clock and weather live on `HomeScreen` (`lib/screens/home/home_screen.dart:56-90`). CLAUDE.md calls these "ambient overlays"; in code they are part of Home.

The glance is a `ConsumerWidget`, `CalendarGlance`, added to the bottom column in `HomeScreen`, above the timer pill, when `calendarAmbientGlance` is on and there is at least one enabled source:

```
  ● 9:00  Dentist — Ava
  ● 15:30 Soccer practice
  ● Tomorrow  Grandma visit (all day)
```

- At most three lines: events that have not ended, from now until the end of tomorrow. All-day events of today come first. Nothing to show, nothing drawn (no "No events" line over a photo).
- Same text shadows as the clock (`home_screen.dart:15-19`), source colour as the dot.
- Tapping it jumps to the Calendar page when the module is placed in the swipe row.
- It watches `calendarEventsProvider` with `select` on the next three events, so a push that changes nothing later in the week does not rebuild it.
- Portrait: it sits full width above the weather/clock stack, unchanged.

## Test plan

Unit tests with fixtures in `test/fixtures/calendar/`.

**HA (`test/modules/calendar/ha_calendar_source_test.dart`)**, using the existing `FakeWebSocketChannel` pattern:

- Subscribe sends the right message; the `result` then `event` sequence fills the list.
- A second `event` replaces, not appends.
- `events: null` keeps the old list and marks `stale`.
- Socket closes, `auth_ok` again: a new subscribe goes out with a new id and the old id's events are ignored.
- `unknown_command` switches to REST; REST payload (`{"date"}` / `{"dateTime"}`, nulls present) parses to the same events as the WebSocket shape.
- `not_found` reports an error and does not retry.
- Window change unsubscribes the old id.
- `HomeAssistantService`: a calendar `event` is routed by id and never reaches the state cache; a `state_changed` event still does.

HA fixtures, captured as JSON in both shapes (WebSocket and REST):

- `ha_recurring_with_exception.json` — a weekly series with one instance moved (its own `recurrence_id`, different time) and one missing (deleted).
- `ha_timed_offsets.json` — timed events with a `-05:00` offset in a window that crosses the US DST change on 2026-11-01, showing that HA's offsets are used as sent.
- `ha_all_day_multi_day.json` — an all-day event over three days (exclusive end) and a one-day all-day event.

**ICS (`test/modules/calendar/ics_parse_test.dart`, `ics_expand_test.dart`)**:

- `ics_recurring_with_exceptions.ics` — `RRULE:FREQ=WEEKLY;BYDAY=MO,WE` with an `EXDATE` (multi-valued, with `TZID`), an `RDATE`, and a second `VEVENT` with the same `UID` and a `RECURRENCE-ID` that moves one instance (RFC 5545 §3.8.4.4, §3.8.5.1, §3.8.5.2).
- `ics_tzid.ics` — `DTSTART;TZID=America/Chicago` across the 2026-11-01 DST change (the wall time stays 09:00, the UTC instant moves), plus a `VTIMEZONE`, a `Z` (UTC) time, and a floating time (§3.3.5).
- `ics_tzid_windows.ics` — `TZID=Central Standard Time`, as Outlook writes it.
- `ics_all_day_multi_day.ics` — `DTSTART;VALUE=DATE` with a `DTEND` three days later, one with no `DTEND` (one day, §3.6.1), and one with `DURATION:P2D`.
- `ics_folding_escaping.ics` — folded lines, CRLF and bare LF, `\,` `\;` `\n` escapes (§3.1, §3.3.11).
- `ics_count_until.ics` — `COUNT=5` and `UNTIL` in UTC on a `TZID` event (the last instance must be kept), the window starting mid-series.
- `ics_wkst_su.ics` — a Google-style `RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=TU` expands instead of throwing.
- `ics_bad_event.ics` — one malformed `VEVENT` and an unknown `BEGIN:X-FOO` component among good events: the good events survive.
- Expansion is bounded: a `FREQ=DAILY` with no end over a one-month window yields 31 instances and returns quickly.
- `webcal://` and `webcals://` map to `https://`; 304 keeps the last calendar; a 404 is `error`, a timeout is `stale`.

**Merge (`calendar_providers_test.dart`)**: two sources, sort order, a disabled source excluded, per-source status carried, a failing source does not hide the other.

**Layouts (`test/portrait/module_calendar_portrait_test.dart`)**: `testLayouts` pumps each view at 1184x864, 864x1184 and 800x1280 with a dense week (overlaps, long titles, a three-day all-day event, more than three all-day rows) and asserts no overflow. The glance gets a case in `screens_portrait_test.dart`.

**Hardware pass**: on the Pi and on the Android tablet, with a real HA (a Google calendar and a Local Calendar) and a real ICS feed (a public holiday feed and a Google secret-address feed): events match HA's own calendar panel for the same week, a change made in Google appears within the expected refresh, the socket survives an HA restart and resubscribes, and the week view stays smooth while scrolling.

## Child tasks

In order. Each is one pull request.

1. **Data layer and HA source.** `models.dart`, the `HubConfig` fields, `HomeAssistantService.subscribe` with id routing and resubscribe, `HaCalendarSource` with the REST fallback, `calendarWindowProvider`, `calendarSourceEventsProvider`, `calendarEventsProvider`. HA tests and fixtures. No UI.
2. **ICS source.** The chosen packages, `IcsCalendarSource` (fetch, conditional GET, isolate parse and expand, EXDATE/RECURRENCE-ID/RDATE, Windows zone map, poll and backoff). ICS tests and fixtures. `assets/licenses/notices.json` entry for the Windows zone map if it is a bundled data file. Measure parse time on the Pi.
3. **Settings plugin.** `hearth.calendar`: the source list on device and portal, plugin routes, the ICS test fetch, colour defaults from the registry and `X-APPLE-CALENDAR-COLOR`.
4. **Screen.** `CalendarModule`, `CalendarScreen` with the four views and the detail sheet, registry entry, portrait tests, CLAUDE.md screen-order line.
5. **Ambient glance.** `CalendarGlance` on `HomeScreen`, its toggle, its portrait case.
6. **Hardware pass.** On the Pi and the tablet, recorded in this document.

Tasks 2 and 3 can run in parallel after 1; 4 needs 1 (and shows ICS once 2 lands); 5 needs 1.

## Decisions

- **Two source kinds, nothing else.** HA covers Google, CalDAV, Outlook and local calendars; ICS covers what HA does not have or what the household doesn't want in HA.
- **HA expands, Hearth expands ICS.** Hearth never applies an HA `rrule`.
- **WebSocket first, REST only on `unknown_command`.** Detected by capability, not by comparing `ha_version`, so a backport or a dev build still works.
- **No disk cache.** Fewer states to get wrong; a kiosk is rarely offline for long.
- **One shared window.** Simpler than per-view subscriptions, and the HA cost is one subscription per calendar.
