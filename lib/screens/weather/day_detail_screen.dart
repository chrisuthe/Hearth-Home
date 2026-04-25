import 'package:flutter/material.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../models/weather_state.dart';
import '../../utils/weather_utils.dart';
import 'icons/wx_icon.dart';
import 'palette.dart';
import 'widgets/hourly_strip.dart';
import 'wx_cond.dart';

/// Fullscreen detail for a single day in the forecast. Shows day-level
/// stats (high/low, total precip, humidity, wind) plus an hourly strip
/// filtered to the hours that fall within the day's local date.
///
/// Opened by tapping a [ForecastCard] on the main weather screen.
class DayDetailScreen extends StatelessWidget {
  final DailyForecast day;
  final List<HourlyForecast> allHours;
  final bool use24h;
  const DayDetailScreen({
    super.key,
    required this.day,
    required this.allHours,
    this.use24h = false,
  });

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _title => _weekdayNames[day.date.weekday - 1];
  String get _subtitle =>
      '${_monthNames[day.date.month - 1]} ${day.date.day}';

  /// Filter the full hourly list to entries whose local-time date matches
  /// [day.date]'s local-time date. The [WeatherState] parser already calls
  /// `.toLocal()` on both, so a same-day comparison is correct.
  List<HourlyForecast> get _hoursForDay {
    return allHours.where((h) =>
        h.time.year == day.date.year &&
        h.time.month == day.date.month &&
        h.time.day == day.date.day).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cond = mapHaToWx(day.condition);
    final pal = palettes[cond]!;
    final hoursForDay = _hoursForDay;

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF0B1220),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _header(pal),
            const SizedBox(height: 32),
            _heroRow(pal, cond),
            const SizedBox(height: 32),
            _statGrid(),
            if (hoursForDay.isNotEmpty) ...[
              const SizedBox(height: 32),
              _sectionLabel('HOURLY'),
              const SizedBox(height: 12),
              HourlyStrip(hours: hoursForDay, palette: pal, use24h: use24h),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _header(ScenePalette pal) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_subtitle.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600,
            letterSpacing: 1.5, color: pal.ink.withValues(alpha: 0.7),
          )),
      const SizedBox(height: 6),
      Text(_title,
          style: TextStyle(
            fontFamily: 'Inter', fontSize: 56, fontWeight: FontWeight.w300,
            letterSpacing: -1.5, color: pal.ink, height: 1.0,
          )),
    ]);
  }

  Widget _heroRow(ScenePalette pal, WxCond cond) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      WxIcon(cond: cond, size: 110),
      const SizedBox(width: 30),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(conditionLabel(day.condition),
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w500,
              color: pal.ink,
            )),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${day.high.round()}°',
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 96, fontWeight: FontWeight.w200,
                letterSpacing: -3, height: 0.95, color: pal.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('${day.low.round()}°',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 36, fontWeight: FontWeight.w400,
                  color: pal.ink.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
        ]),
      ]),
    ]);
  }

  Widget _statGrid() {
    final stats = <_Stat>[
      if (day.precipitation != null)
        _Stat(WeatherIcons.raindrop, 'Chance of rain',
            '${day.precipitation!.round()}%'),
      if (day.precipitationAmount != null && day.precipitationAmount! > 0)
        _Stat(WeatherIcons.umbrella, 'Total rain',
            '${day.precipitationAmount!.toStringAsFixed(2)}"'),
      if (day.humidity != null)
        _Stat(WeatherIcons.humidity, 'Humidity',
            '${day.humidity!.round()}%'),
      if (day.windSpeed != null)
        _Stat(WeatherIcons.strong_wind, 'Wind',
            '${day.windSpeed!.round()} mph'),
    ];
    if (stats.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats.map(_statCard).toList(),
    );
  }

  Widget _statCard(_Stat s) {
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(children: [
        Icon(s.icon, color: const Color(0xFF7EB8FF), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.label,
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.6), letterSpacing: 0.4,
                )),
            const SizedBox(height: 2),
            Text(s.value,
                style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
        fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w700,
        letterSpacing: 1.5, color: Colors.white,
        shadows: [
          Shadow(color: Color(0xCC000000), blurRadius: 4),
          Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ));
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;
  const _Stat(this.icon, this.label, this.value);
}
