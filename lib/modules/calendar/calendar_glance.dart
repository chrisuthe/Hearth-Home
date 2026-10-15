import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/calendar_tokens.dart';
import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../utils/time_format.dart';
import 'calendar_providers.dart';
import 'calendar_widgets.dart' show NowTag;
import 'models.dart';

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

/// The next events on the idle Home screen, above the timer pill, on a
/// frosted card so they read over any photo. Draws
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
    Color colorOf(CalendarEvent e) => Color(
      sources
          .firstWhere(
            (s) => s.id == e.sourceId,
            orElse: () =>
                const CalendarSource(id: '', kind: CalendarSourceKind.ha),
          )
          .color,
    );
    bool isTomorrow(CalendarEvent e) =>
        !(e.allDay ? e.start : e.start.toLocal()).isBefore(tomorrow);

    final rows = <Widget>[];
    String? section;
    for (final e in events) {
      final label = isTomorrow(e) ? 'TOMORROW' : 'TODAY';
      if (label != section) {
        rows.add(_SectionLabel(label: label, divided: section != null));
        section = label;
      }
      final now = !e.allDay && !e.start.isAfter(_now);
      rows.add(
        _GlanceRow(
          event: e,
          color: colorOf(e),
          now: now,
          when: e.allDay ? 'All day' : formatTime(e.start.toLocal(), use24h),
          until: now ? 'until ${formatTime(e.end.toLocal(), use24h)}' : null,
        ),
      );
    }

    final radius = BorderRadius.circular(CalendarRadii.glance);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: HearthSpacing.x5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: CalendarSizes.glanceMinWidth,
            maxWidth: CalendarSizes.glanceMaxWidth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: CalendarShadows.glance,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CalendarSizes.glanceBlur,
                  sigmaY: CalendarSizes.glanceBlur,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    HearthSpacing.x3,
                    HearthSpacing.x3,
                    HearthSpacing.x3,
                    HearthSpacing.x2,
                  ),
                  decoration: BoxDecoration(
                    color: CalendarColors.glanceCard,
                    border: Border.all(color: CalendarColors.glanceBorder),
                    borderRadius: radius,
                  ),
                  child: DefaultTextStyle.merge(
                    style: CalendarType.base,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: rows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  /// A rule above it, between today's events and tomorrow's.
  final bool divided;

  const _SectionLabel({required this.label, required this.divided});

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(top: divided ? HearthSpacing.x2 : 0),
    padding: EdgeInsets.fromLTRB(
      HearthSpacing.x3,
      divided ? HearthSpacing.x3 : 0,
      HearthSpacing.x3,
      HearthSpacing.x1,
    ),
    decoration: divided
        ? const BoxDecoration(
            border: Border(top: BorderSide(color: CalendarColors.glanceBorder)),
          )
        : null,
    child: Text(
      label,
      style: const TextStyle(
        fontSize: CalendarType.glanceLabel,
        fontWeight: FontWeight.w700,
        letterSpacing: CalendarType.glanceTracking,
        color: CalendarColors.glanceLabel,
      ),
    ),
  );
}

class _GlanceRow extends StatelessWidget {
  final CalendarEvent event;
  final Color color;
  final bool now;
  final String when;
  final String? until;

  const _GlanceRow({
    required this.event,
    required this.color,
    required this.now,
    required this.when,
    this.until,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CalendarSizes.glanceRow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3),
        child: Row(
          children: [
            Container(
              width: CalendarSizes.glanceDot,
              height: CalendarSizes.glanceDot,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: HearthSpacing.x3),
            SizedBox(
              width: CalendarSizes.glanceTimeWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: now
                    ? const NowTag(fontSize: CalendarType.glanceNow)
                    : Text(
                        when,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: CalendarType.glance,
                          fontWeight: FontWeight.w500,
                          color: CalendarColors.glanceTime,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: HearthSpacing.x3),
            Expanded(
              child: Text(
                event.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: CalendarType.glance,
                  fontWeight: FontWeight.w600,
                  color: CalendarColors.text,
                ),
              ),
            ),
            if (until != null) ...[
              const SizedBox(width: HearthSpacing.x3),
              Text(
                until!,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: CalendarType.glanceMeta,
                  color: CalendarColors.glanceMeta,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
