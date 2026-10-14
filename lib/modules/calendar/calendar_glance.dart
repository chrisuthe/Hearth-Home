import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../utils/time_format.dart';
import 'calendar_providers.dart';
import 'models.dart';

/// Same as the Home clock's, for legibility over full-bleed photos.
const _textShadows = [
  Shadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0xB4000000)),
  Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x82000000)),
];

/// At most three events that have not ended, from [now] to the end of
/// tomorrow. Today's all-day events come first; the rest keep [events]'
/// order, which is sorted by start.
List<CalendarEvent> upcomingEvents(List<CalendarEvent> events, DateTime now) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final dayAfter = DateTime(now.year, now.month, now.day + 2);
  final todayAllDay = <CalendarEvent>[];
  final rest = <CalendarEvent>[];
  for (final e in events) {
    if (!e.end.isAfter(now) || !e.start.isBefore(dayAfter)) continue;
    if (e.allDay && e.start.isBefore(tomorrow)) {
      todayAllDay.add(e);
    } else {
      rest.add(e);
    }
  }
  return [...todayAllDay, ...rest].take(3).toList();
}

/// The next events on the idle Home screen, above the timer pill. Draws
/// nothing when the glance is off, no source is enabled, or nothing is left
/// before the end of tomorrow.
class CalendarGlance extends ConsumerStatefulWidget {
  /// Opens the Calendar page; null when it is not in the swipe row.
  final VoidCallback? onTap;

  const CalendarGlance({super.key, this.onTap});

  @override
  ConsumerState<CalendarGlance> createState() => _CalendarGlanceState();
}

class _CalendarGlanceState extends ConsumerState<CalendarGlance> {
  // The tick that drops an ended event lives here, so it rebuilds only the
  // glance — never HomeScreen or HubShell.
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = ref.watch(
      hubConfigProvider.select(
        (c) =>
            c.calendarAmbientGlance && c.calendarSources.any((s) => s.enabled),
      ),
    );
    // Off means unwatched, so the sources only run while the Calendar page
    // is built.
    if (!shown) return const SizedBox.shrink();

    // A record compares by value, so a push that leaves the next three
    // events unchanged does not rebuild.
    final next = ref.watch(
      calendarEventsProvider.select((m) {
        final e = upcomingEvents(m.events, _now);
        return (
          e.isNotEmpty ? e[0] : null,
          e.length > 1 ? e[1] : null,
          e.length > 2 ? e[2] : null,
        );
      }),
    );
    final events = [next.$1, next.$2, next.$3].nonNulls.toList();
    if (events.isEmpty) return const SizedBox.shrink();

    final sources = ref.watch(
      hubConfigProvider.select((c) => c.calendarSources),
    );
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final tomorrow = DateTime(_now.year, _now.month, _now.day + 1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: HearthSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in events)
              _GlanceLine(
                event: e,
                color: Color(
                  sources
                      .firstWhere(
                        (s) => s.id == e.sourceId,
                        orElse: () => const CalendarSource(
                          id: '',
                          kind: CalendarSourceKind.ha,
                        ),
                      )
                      .color,
                ),
                when: _whenLabel(e, tomorrow, use24h),
              ),
          ],
        ),
      ),
    );
  }

  String _whenLabel(CalendarEvent e, DateTime tomorrow, bool use24h) {
    final start = e.allDay ? e.start : e.start.toLocal();
    final isTomorrow = !start.isBefore(tomorrow);
    if (e.allDay) return isTomorrow ? 'Tomorrow' : 'Today';
    final time = formatTime(start, use24h);
    return isTomorrow ? 'Tomorrow $time' : time;
  }
}

class _GlanceLine extends StatelessWidget {
  final CalendarEvent event;
  final Color color;
  final String when;

  const _GlanceLine({
    required this.event,
    required this.color,
    required this.when,
  });

  @override
  Widget build(BuildContext context) {
    final title = event.allDay ? '${event.summary} (all day)' : event.summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.x1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Color(0x82000000)),
              ],
            ),
          ),
          const SizedBox(width: HearthSpacing.x3),
          Text(
            when,
            style: TextStyle(
              fontSize: HearthFont.title,
              color: Colors.white.withValues(alpha: 0.8),
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: _textShadows,
            ),
          ),
          const SizedBox(width: HearthSpacing.x3),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: HearthFont.title,
                shadows: _textShadows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
