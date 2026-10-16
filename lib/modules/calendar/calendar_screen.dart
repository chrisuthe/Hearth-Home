import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/calendar_tokens.dart';
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
      child: DefaultTextStyle.merge(
        style: CalendarType.base,
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
                _StatusBanners(
                  sources: enabled,
                  status: merged.sources,
                  use24h: use24h,
                ),
                const Divider(height: 1, color: CalendarColors.divider),
                Expanded(child: _body(view, range, events, ctx, narrow)),
              ],
            );
          },
        ),
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
              const Divider(height: 1, color: CalendarColors.divider),
              Expanded(child: agenda),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: grid),
            const VerticalDivider(width: 1, color: CalendarColors.divider),
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
    child: DefaultTextStyle.merge(
      style: CalendarType.base,
      child: Center(
        child: Padding(
          padding: HearthSpacing.allX6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: CalendarSizes.emptyDisc,
                height: CalendarSizes.emptyDisc,
                decoration: const BoxDecoration(
                  color: CalendarColors.emptyDisc,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  size: CalendarSizes.emptyIcon,
                  color: CalendarColors.accentText,
                ),
              ),
              const SizedBox(height: HearthSpacing.x6),
              const Text(
                'Calendar not configured',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: HearthFont.headline,
                  fontWeight: FontWeight.w600,
                  color: CalendarColors.text,
                ),
              ),
              const SizedBox(height: HearthSpacing.x3),
              const Text(
                'Add a Home Assistant calendar or an ICS link in '
                'Settings › Calendar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: HearthFont.bodyLg,
                  height: CalendarType.bodyHeight,
                  color: CalendarColors.sheetSecondary,
                ),
              ),
            ],
          ),
        ),
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
    final controlStyle = IconButton.styleFrom(
      backgroundColor: CalendarColors.control,
      foregroundColor: CalendarColors.text,
      fixedSize: const Size.square(CalendarSizes.control),
    );
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous',
          style: controlStyle,
          iconSize: HearthIcon.md,
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
        ),
        const SizedBox(width: HearthSpacing.x2),
        TextButton(
          onPressed: onToday,
          style: TextButton.styleFrom(
            backgroundColor: CalendarColors.control,
            foregroundColor: CalendarColors.text,
            minimumSize: const Size(0, CalendarSizes.control),
            padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x5),
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Today',
            style: TextStyle(
              fontFamily: CalendarType.family,
              fontSize: CalendarType.today,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: HearthSpacing.x2),
        IconButton(
          tooltip: 'Next',
          style: controlStyle,
          iconSize: HearthIcon.md,
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    );
    // The year reads as context, so it steps back.
    final year = RegExp(r'^(.*?)(,? \d{4})$').firstMatch(label);
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: year?.group(1) ?? label),
          if (year != null)
            TextSpan(
              text: year.group(2),
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                color: CalendarColors.textDim,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: CalendarType.title,
        fontWeight: FontWeight.w600,
        color: CalendarColors.text,
      ),
    );
    final pills = Wrap(
      spacing: HearthSpacing.x2,
      runSpacing: HearthSpacing.x2,
      children: [
        for (final s in sources)
          _SourcePill(
            source: s,
            status: status[s.id] ?? const SourceEvents(),
            hidden: hidden.contains(s.id),
            onTap: () => onToggle(s.id),
          ),
      ],
    );
    final switcher = _ViewSwitcher(view: view, narrow: narrow, onView: onView);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // HubShell's mic toggle sits over the top-left corner of every page,
        // so the first row starts clear of it.
        SizedBox(
          height: CalendarSizes.headerRow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HearthSpacing.x20,
              0,
              HearthSpacing.x4,
              0,
            ),
            child: Row(
              children: [
                nav,
                const SizedBox(width: HearthSpacing.x5),
                Expanded(child: title),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HearthSpacing.x4,
            0,
            HearthSpacing.x4,
            HearthSpacing.x3,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: HearthSpacing.x3,
            runSpacing: HearthSpacing.x2,
            children: [pills, switcher],
          ),
        ),
      ],
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
        color: CalendarColors.segmentTrack,
        borderRadius: BorderRadius.circular(CalendarSizes.segment),
      ),
      padding: const EdgeInsets.all(HearthSpacing.x1),
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
    final button = Material(
      textStyle: CalendarType.base,
      color: selected ? CalendarColors.accent : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => onView(v),
        child: Container(
          height: CalendarSizes.segment,
          constraints: const BoxConstraints(
            minWidth: CalendarSizes.segmentMinWidth,
          ),
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3),
          alignment: Alignment.center,
          child: Text(
            v.label,
            style: TextStyle(
              fontSize: CalendarType.control,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fallsBack ? CalendarColors.textFaint : CalendarColors.text,
            ),
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

/// A source as a pill in its fill colour, with its initial. Tapping hides
/// its events on screen only; a hidden pill turns to an outline.
class _SourcePill extends StatelessWidget {
  const _SourcePill({
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
    final fill = CalendarColors.fill(Color(source.color));
    final name = source.name.isNotEmpty ? source.name : source.id;
    final (icon, note) = switch (status.status) {
      SourceStatus.loading => (Icons.sync, 'loading'),
      SourceStatus.ok => (null, null),
      SourceStatus.stale => (Icons.history, 'not up to date'),
      SourceStatus.error => (Icons.error_outline, 'error'),
    };
    final foreground = hidden
        ? CalendarColors.pillOffText
        : CalendarColors.onFill;
    final shape = StadiumBorder(
      side: hidden
          ? const BorderSide(
              color: CalendarColors.pillOffOutline,
              width: CalendarSizes.outline,
            )
          : BorderSide.none,
    );
    return Tooltip(
      message: [name, ?note, if (hidden) 'hidden'].join(' · '),
      child: Material(
        textStyle: CalendarType.base,
        color: hidden ? Colors.transparent : fill,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            height: CalendarSizes.pill,
            padding: const EdgeInsets.fromLTRB(
              (CalendarSizes.pill - CalendarSizes.pillAvatar) / 2,
              0,
              HearthSpacing.x4,
              0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: CalendarSizes.pillAvatar,
                  height: CalendarSizes.pillAvatar,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hidden
                        ? CalendarColors.pillOffAvatar
                        : CalendarColors.pillAvatar,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    sourceInitial(name),
                    style: TextStyle(
                      fontSize: CalendarType.control,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: HearthSpacing.x2),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: CalendarSizes.pillMaxText,
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CalendarType.control,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                      decoration: hidden ? TextDecoration.lineThrough : null,
                      decorationColor: foreground,
                    ),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: HearthSpacing.x2),
                  Icon(icon, size: HearthIcon.sm, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One banner per source that is stale or failing, so an empty day reads
/// as "can't reach" rather than "nothing on".
class _StatusBanners extends StatelessWidget {
  const _StatusBanners({
    required this.sources,
    required this.status,
    required this.use24h,
  });

  final List<CalendarSource> sources;
  final Map<String, SourceEvents> status;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[];
    for (final s in sources) {
      final st = status[s.id];
      if (st == null) continue;
      final name = s.name.isNotEmpty ? s.name : s.id;
      final String headline;
      final String? detail;
      final Color color;
      final Color fill;
      final Color border;
      final IconData icon;
      switch (st.status) {
        case SourceStatus.loading:
        case SourceStatus.ok:
          continue;
        case SourceStatus.stale:
          headline = st.lastOk == null
              ? "$name can't update"
              : "$name can't update — showing events from "
                    '${formatTime(st.lastOk!.toLocal(), use24h)}';
          detail = st.error;
          color = CalendarColors.stale;
          fill = CalendarColors.staleFill;
          border = CalendarColors.staleBorder;
          icon = Icons.history;
        case SourceStatus.error:
          headline = "$name can't be reached";
          detail = st.error;
          color = CalendarColors.error;
          fill = CalendarColors.errorFill;
          border = CalendarColors.errorBorder;
          icon = Icons.error_outline;
      }
      banners.add(
        Container(
          constraints: const BoxConstraints(minHeight: CalendarSizes.banner),
          margin: const EdgeInsets.only(bottom: HearthSpacing.x2),
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x4),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(CalendarRadii.banner),
          ),
          child: Row(
            children: [
              Icon(icon, size: HearthIcon.sm, color: color),
              const SizedBox(width: HearthSpacing.x3),
              Flexible(
                child: Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: CalendarType.banner,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: HearthSpacing.x3),
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: CalendarType.banner,
                      color: CalendarColors.bannerDetail,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x4,
        0,
        HearthSpacing.x4,
        HearthSpacing.x1,
      ),
      child: Column(children: banners),
    );
  }
}
