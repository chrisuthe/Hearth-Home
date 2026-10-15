import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/calendar/calendar_providers.dart';
import '../../modules/calendar/ics_calendar_source.dart';
import '../../modules/calendar/models.dart';
import '../../services/home_assistant_service.dart';

/// Rules and defaults shared by the Calendar plugin's device panel and its
/// portal routes, so both surfaces add and edit sources the same way.

/// Default source colours, led by the accent indigo.
const calendarPalette = <int>[
  0xFF646CFF,
  0xFFE57373,
  0xFF4DB6AC,
  0xFFFFB74D,
  0xFF81C784,
  0xFFBA68C8,
  0xFF4FC3F7,
  0xFFF06292,
];

/// The first palette colour no source uses yet; past eight, the palette
/// repeats.
int nextPaletteColor(List<CalendarSource> existing) =>
    nextFreePaletteColor([for (final s in existing) s.color]);

/// [nextPaletteColor] over bare colours, for other palette users (Lists).
int nextFreePaletteColor(List<int> used) {
  for (final c in calendarPalette) {
    if (!used.contains(c)) return c;
  }
  return calendarPalette[used.length % calendarPalette.length];
}

/// An opaque ARGB colour from an ARGB int or a `#rrggbb` / `#rrggbbaa`
/// string (Apple writes the alpha last). Null when [value] is neither.
int? parseCalendarColor(Object? value) {
  if (value is int) {
    return value >= 0 && value <= 0xFFFFFFFF ? value | 0xFF000000 : null;
  }
  if (value is! String) return null;
  final m = RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$')
      .firstMatch(value.trim());
  if (m == null) return null;
  return 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

/// `#rrggbb` for an ARGB colour.
String calendarColorHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

const _icsSchemes = {'http', 'https', 'webcal', 'webcals'};

/// Null when [url] is an http, https, webcal or webcals URL with a host;
/// otherwise why not.
String? validateIcsUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !_icsSchemes.contains(uri.scheme.toLowerCase())) {
    return 'Use an http, https or webcal URL';
  }
  if (uri.host.isEmpty) return 'The URL has no host';
  return null;
}

/// Null when [entityId] is a `calendar.*` entity id; otherwise why not.
String? validateCalendarEntityId(String entityId) =>
    RegExp(r'^calendar\.[a-z0-9_]+$').hasMatch(entityId)
        ? null
        : 'Pick a calendar.* entity';

String haSourceId(String entityId) => 'ha:$entityId';

String newIcsSourceId() {
  final random = Random.secure();
  final hex = List.generate(
      8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return 'ics:$hex';
}

/// The name for an ICS source the user left unnamed.
String icsFallbackName(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  return host.isEmpty ? 'Calendar' : host;
}

String calendarKindLabel(CalendarSourceKind kind) => switch (kind) {
      CalendarSourceKind.ha => 'Home Assistant',
      CalendarSourceKind.ics => 'ICS feed',
    };

/// One line for a source's live state, as both surfaces show it.
String calendarStatusLabel(
  SourceEvents? status, {
  required bool enabled,
  required bool use24Hour,
}) {
  if (!enabled) return 'Off';
  if (status == null) return 'Loading…';
  final when = status.lastOk == null ? null : _time(status.lastOk!, use24Hour);
  return switch (status.status) {
    SourceStatus.loading => 'Loading…',
    SourceStatus.ok => when == null ? 'Up to date' : 'Updated $when',
    SourceStatus.stale => [
        if (when != null) 'Last updated $when',
        if (status.error != null) status.error!,
      ].join(' · '),
    SourceStatus.error => status.error ?? 'Error',
  };
}

String _time(DateTime t, bool use24Hour) {
  final local = t.toLocal();
  final mm = local.minute.toString().padLeft(2, '0');
  if (use24Hour) return '${local.hour.toString().padLeft(2, '0')}:$mm';
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$h:$mm ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// The live status of a configured source, or null before its provider
/// has a value.
SourceEvents? calendarSourceStatus(
  T Function<T>(ProviderListenable<T>) read,
  String sourceId,
) =>
    read(calendarSourceEventsProvider(sourceId)).valueOrNull;

/// One test fetch of an ICS URL. Throws [IcsProbeException]. Tests override.
final calendarIcsProbeProvider =
    Provider<Future<IcsProbe> Function(String url)>((ref) {
  return (url) => IcsCalendarSource.probe(url, dio: ref.read(icsDioProvider));
});

/// Defaults for a new HA source: the entity's friendly name and the colour
/// from its registry options (`options.calendar.color`), each null when HA
/// has none. Tests override.
final calendarHaDefaultsProvider =
    Provider<Future<({String? name, int? color})> Function(String entityId)>(
        (ref) {
  return (entityId) async {
    final ha = ref.read(homeAssistantServiceProvider);
    final entity = ha.entities[entityId];
    final name = entity?.attributes['friendly_name'] as String?;
    int? color;
    final result = await ha.sendCommand({
      'type': 'config/entity_registry/get_entries',
      'entity_ids': [entityId],
    });
    if (result is Map) {
      final entry = result[entityId];
      if (entry is Map) {
        final options = entry['options'];
        final calendar = options is Map ? options['calendar'] : null;
        color = parseCalendarColor(calendar is Map ? calendar['color'] : null);
      }
    }
    return (name: name, color: color);
  };
});
