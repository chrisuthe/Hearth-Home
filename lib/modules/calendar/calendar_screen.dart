import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../utils/time_format.dart';
import 'calendar_layout.dart';
import 'calendar_month_view.dart';
import 'calendar_providers.dart';
import 'calendar_time_grid.dart';
import 'calendar_widgets.dart';
import 'models.dart';

/// Read-only calendar: day/agenda, 3-day, week and month over every enabled
/// source. Ranges change with the header arrows only — a horizontal swipe
/// belongs to HubShell's PageView.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.isActive = false});

  final bool isActive;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Null until the user picks one; until then the configured default.
  CalendarView? _view;
  DateTime _anchor = dateOnly(DateTime.now());

  /// Sources hidden from the legend. On screen only, never saved.
  final Set<String> _hidden = {};
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  CalendarView get _selectedView =>
      _view ??
      CalendarView.fromConfig(ref.read(hubConfigProvider).calendarDefaultView);

  void _go(CalendarView view, DateTime anchor) {
    setState(() {
      _view = view;
      _anchor = dateOnly(anchor);
    });
    _ensureWindow(view, _anchor);
  }

  /// Moves [calendarWindowProvider] when the page leaves it. Covers the
  /// 3-day fallback of week and day/agenda's seven-day list as well.
  void _ensureWindow(CalendarView view, DateTime anchor) {
    final DateTime start;
    final DateTime end;
    if (view == CalendarView.month) {
      final r = visibleRange(view, anchor);
      start = r.start;
      end = r.end;
    } else {
      final r = visibleRange(view, anchor);
      start = r.start.isBefore(anchor) ? r.start : anchor;
      final week = addDays(anchor, 7);
      end = r.end.isAfter(week) ? r.end : week;
    }
    final window = ref.read(calendarWindowProvider);
    if (!start.isBefore(window.start) && !end.isAfter(window.end)) return;
    final moved = defaultCalendarWindow(start);
    ref.read(calendarWindowProvider.notifier).state = DateTimeRange(
      start: moved.start,
      end: moved.end.isBefore(end) ? end : moved.end,
    );
  }

  void _setView(CalendarView view) {
    final today = dateOnly(DateTime.now());
    // Leaving month keeps today when it is in the month shown.
    final anchor =
        _selectedView == CalendarView.month &&
            today.year == _anchor.year &&
            today.month == _anchor.month
        ? today
        : _anchor;
    _go(view, anchor);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sources = ref.watch(
      hubConfigProvider.select((c) => c.calendarSources),
    );
    final enabled = sources.where((s) => s.enabled).toList();
    if (enabled.isEmpty) return const _NotConfigured();

    // The view the user picked or, until then, the configured default.
    final selected =
        _view ??
        CalendarView.fromConfig(
          ref.watch(hubConfigProvider.select((c) => c.calendarDefaultView)),
        );
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final merged = ref.watch(calendarEventsProvider);
    final events = merged.events
        .where((e) => !_hidden.contains(e.sourceId))
        .toList();

    final ctx = CalendarViewContext(
      sources: {for (final s in enabled) s.id: s},
      use24h: use24h,
      now: _now,
    );

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < kCalendarNarrowWidth;
          final view = selected == CalendarView.week && narrow
              ? CalendarView.threeDay
              : selected;
          final range = visibleRange(view, _anchor);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                narrow: narrow,
                view: view,
                label: rangeLabel(view, _anchor, range),
                sources: enabled,
                status: merged.sources,
                hidden: _hidden,
                onPrev: () => _go(selected, stepAnchor(view, _anchor, -1)),
                onNext: () => _go(selected, stepAnchor(view, _anchor, 1)),
                onToday: () => _go(selected, DateTime.now()),
                onView: _setView,
                onToggle: (id) => setState(
                  () => _hidden.contains(id)
                      ? _hidden.remove(id)
                      : _hidden.add(id),
                ),
              ),
              _StatusNotes(
                sources: enabled,
                status: merged.sources,
                use24h: use24h,
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(child: _body(view, range, events, ctx, narrow)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(
    CalendarView view,
    DateTimeRange range,
    List<CalendarEvent> events,
    CalendarViewContext ctx,
    bool narrow,
  ) {
    final key = ValueKey('${view.name}-${range.start}');
    switch (view) {
      case CalendarView.month:
        return CalendarMonthView(
          key: key,
          month: _anchor,
          events: events,
          ctx: ctx,
        );
      case CalendarView.threeDay:
      case CalendarView.week:
        final days = [
          for (var d = range.start; d.isBefore(range.end); d = addDays(d, 1)) d,
        ];
        return CalendarTimeGrid(key: key, days: days, events: events, ctx: ctx);
      case CalendarView.day:
        final grid = CalendarTimeGrid(
          key: key,
          days: [range.start],
          events: events,
          ctx: ctx,
        );
        final agenda = CalendarAgenda(
          start: range.start,
          events: events,
          ctx: ctx,
        );
        if (narrow) {
          return Column(
            children: [
              Expanded(child: grid),
              const Divider(height: 1, color: Colors.white12),
              Expanded(child: agenda),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: grid),
            const VerticalDivider(width: 1, color: Colors.white12),
            Expanded(child: agenda),
          ],
        );
    }
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_month,
            size: HearthIcon.xxl,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: HearthSpacing.x4),
          Text(
            'Calendar not configured',
            style: TextStyle(
              fontSize: HearthFont.bodyLg,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: HearthSpacing.x2),
          Text(
            'Add a calendar in Settings → Calendar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.narrow,
    required this.view,
    required this.label,
    required this.sources,
    required this.status,
    required this.hidden,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onView,
    required this.onToggle,
  });

  final bool narrow;
  final CalendarView view;
  final String label;
  final List<CalendarSource> sources;
  final Map<String, SourceEvents> status;
  final Set<String> hidden;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final void Function(CalendarView) onView;
  final void Function(String sourceId) onToggle;

  @override
  Widget build(BuildContext context) {
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: onPrev,
        ),
        TextButton(
          onPressed: onToday,
          child: const Text(
            'Today',
            style: TextStyle(fontSize: HearthFont.body, color: Colors.white),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: onNext,
        ),
      ],
    );
    final title = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: HearthFont.title,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    final switcher = _ViewSwitcher(view: view, narrow: narrow, onView: onView);
    final legend = Wrap(
      spacing: HearthSpacing.x2,
      runSpacing: HearthSpacing.x1,
      children: [
        for (final s in sources)
          _LegendChip(
            source: s,
            status: status[s.id] ?? const SourceEvents(),
            hidden: hidden.contains(s.id),
            onTap: () => onToggle(s.id),
          ),
      ],
    );

    // HubShell's mic toggle sits over the top-left corner of every page, so
    // the header starts clear of it.
    const padding = EdgeInsets.fromLTRB(
      HearthSpacing.x20,
      HearthSpacing.x2,
      HearthSpacing.x3,
      HearthSpacing.x2,
    );
    if (narrow) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                nav,
                const SizedBox(width: HearthSpacing.x2),
                Expanded(child: title),
              ],
            ),
            const SizedBox(height: HearthSpacing.x1),
            Wrap(
              spacing: HearthSpacing.x4,
              runSpacing: HearthSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [switcher, legend],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Row(
        children: [
          nav,
          const SizedBox(width: HearthSpacing.x2),
          Expanded(child: title),
          switcher,
          const SizedBox(width: HearthSpacing.x4),
          Flexible(child: legend),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.view,
    required this.narrow,
    required this.onView,
  });

  final CalendarView view;
  final bool narrow;
  final void Function(CalendarView) onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(HearthSpacing.x5),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in CalendarView.values)
            _segment(v, narrow && v == CalendarView.week),
        ],
      ),
    );
  }

  Widget _segment(CalendarView v, bool fallsBack) {
    final selected = v == view;
    final button = InkWell(
      borderRadius: BorderRadius.circular(HearthSpacing.x4),
      onTap: () => onView(v),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.x3,
          vertical: HearthSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: selected ? kCalendarAccent : null,
          borderRadius: BorderRadius.circular(HearthSpacing.x4),
        ),
        child: Text(
          v.label,
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: Colors.white.withValues(alpha: fallsBack ? 0.4 : 0.9),
          ),
        ),
      ),
    );
    if (!fallsBack) return button;
    return Tooltip(
      message: 'Week view needs a wider screen; showing 3 days',
      child: button,
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.source,
    required this.status,
    required this.hidden,
    required this.onTap,
  });

  final CalendarSource source;
  final SourceEvents status;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(source.color);
    final name = source.name.isNotEmpty ? source.name : source.id;
    final (icon, iconColor, note) = switch (status.status) {
      SourceStatus.loading => (Icons.sync, Colors.white54, 'loading'),
      SourceStatus.ok => (null, null, null),
      SourceStatus.stale => (Icons.history, Colors.amber, 'not up to date'),
      SourceStatus.error => (Icons.error_outline, Colors.redAccent, 'error'),
    };
    return Tooltip(
      message: [name, ?note, if (hidden) 'hidden'].join(' · '),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HearthSpacing.x4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HearthSpacing.x2,
            vertical: HearthSpacing.x1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: hidden ? null : color,
                  border: Border.all(color: color, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: HearthSpacing.x1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HearthFont.label,
                    color: Colors.white.withValues(alpha: hidden ? 0.4 : 0.85),
                    decoration: hidden ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: HearthSpacing.x1),
                Icon(icon, size: HearthIcon.xs, color: iconColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line per source that is stale or failing, so an empty day reads as
/// "can't reach" rather than "nothing on".
class _StatusNotes extends StatelessWidget {
  const _StatusNotes({
    required this.sources,
    required this.status,
    required this.use24h,
  });

  final List<CalendarSource> sources;
  final Map<String, SourceEvents> status;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    for (final s in sources) {
      final st = status[s.id];
      if (st == null) continue;
      final name = s.name.isNotEmpty ? s.name : s.id;
      final String text;
      final Color color;
      switch (st.status) {
        case SourceStatus.loading:
        case SourceStatus.ok:
          continue;
        case SourceStatus.stale:
          final since = st.lastOk == null
              ? ''
              : ', showing events from ${formatTime(st.lastOk!.toLocal(), use24h)}';
          text =
              "$name: can't update$since"
              '${st.error == null ? '' : ' (${st.error})'}';
          color = Colors.amber;
        case SourceStatus.error:
          text = "$name: ${st.error ?? "can't reach"}";
          color = Colors.redAccent;
      }
      lines.add(
        Padding(
          padding: const EdgeInsets.only(bottom: HearthSpacing.x1),
          child: Row(
            children: [
              Icon(
                st.status == SourceStatus.stale
                    ? Icons.history
                    : Icons.error_outline,
                size: HearthIcon.xs,
                color: color,
              ),
              const SizedBox(width: HearthSpacing.x2),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: HearthFont.label, color: color),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x4,
        0,
        HearthSpacing.x4,
        HearthSpacing.x1,
      ),
      child: Column(children: lines),
    );
  }
}
