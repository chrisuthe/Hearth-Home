// Design tokens for the Calendar screen and the Home calendar glance.
//
// From the approved "Hearth Calendar redesign" canvas: solid source fills
// with dark text, name pills, and kiosk-sized touch targets. Values are
// unscaled logical pixels on the 1184x864 canvas; [HearthScaleScope] scales
// them like every other token.

import 'package:flutter/widgets.dart';

import '../theme/hearth_colors.dart';

class CalendarColors {
  const CalendarColors({
    required this.accent,
    required this.accentText,
    required this.onFill,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.textFaint,
    required this.gridLine,
    required this.divider,
    required this.control,
    required this.segmentTrack,
    required this.card,
    required this.todayTint,
    required this.nowTint,
    required this.weekendTint,
    required this.nowLine,
    required this.pillOffOutline,
    required this.pillOffText,
    required this.pillOffAvatar,
    required this.pillAvatar,
    required this.stale,
    required this.staleFill,
    required this.staleBorder,
    required this.error,
    required this.errorFill,
    required this.errorBorder,
    required this.bannerDetail,
    required this.sheet,
    required this.sheetBorder,
    required this.sheetHandle,
    required this.sheetIcon,
    required this.sheetSecondary,
    required this.emptyDisc,
    required this.glanceCard,
    required this.glanceBorder,
    required this.glanceLabel,
    required this.glanceTime,
    required this.glanceMeta,
  });

  /// Selected view, today's date, the now label.
  final Color accent;

  /// The accent as text on black: weekday and section labels for today.
  final Color accentText;

  /// Text on a solid source fill.
  final Color onFill;

  final Color text;

  /// Secondary text: weekday labels, agenda section headers.
  final Color textMuted;

  /// Tertiary text: hour labels, agenda end times.
  final Color textDim;

  /// A month cell number outside the month shown.
  final Color textFaint;

  final Color gridLine;
  final Color divider;

  /// Fill of the round header buttons.
  final Color control;

  /// Track behind the view switcher.
  final Color segmentTrack;

  /// Agenda row card.
  final Color card;

  /// Today's column in the time grid and the selected month cell.
  final Color todayTint;

  /// The agenda row of an event in progress.
  final Color nowTint;

  final Color weekendTint;

  /// White, so it stays visible across an accent-coloured event.
  final Color nowLine;

  /// Outline of a hidden source's pill.
  final Color pillOffOutline;
  final Color pillOffText;
  final Color pillOffAvatar;

  /// Initial circle on a solid pill.
  final Color pillAvatar;

  final Color stale;
  final Color staleFill;
  final Color staleBorder;
  final Color error;
  final Color errorFill;
  final Color errorBorder;

  /// Detail text inside a status banner.
  final Color bannerDetail;

  final Color sheet;
  final Color sheetBorder;
  final Color sheetHandle;
  final Color sheetIcon;
  final Color sheetSecondary;

  /// The not-configured icon disc.
  final Color emptyDisc;

  /// The Home glance card, over a photo that could be anything.
  final Color glanceCard;
  final Color glanceBorder;
  final Color glanceLabel;
  final Color glanceTime;
  final Color glanceMeta;

  /// Today's look.
  static const CalendarColors classic = CalendarColors(
    accent: Color(0xFF646CFF),
    accentText: Color(0xFF9EA3FF),
    onFill: Color(0xFF111116),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xC7FFFFFF),
    textDim: Color(0xA8FFFFFF),
    textFaint: Color(0x8FFFFFFF),
    gridLine: Color(0x21FFFFFF),
    divider: Color(0x1AFFFFFF),
    control: Color(0x24FFFFFF),
    segmentTrack: Color(0x1AFFFFFF),
    card: Color(0x12FFFFFF),
    todayTint: Color(0x21646CFF),
    nowTint: Color(0x4D646CFF),
    weekendTint: Color(0x0DFFFFFF),
    nowLine: Color(0xFFFFFFFF),
    pillOffOutline: Color(0x4DFFFFFF),
    pillOffText: Color(0x99FFFFFF),
    pillOffAvatar: Color(0x1FFFFFFF),
    pillAvatar: Color(0x33000000),
    stale: Color(0xFFF5B544),
    staleFill: Color(0x2EF5B544),
    staleBorder: Color(0x73F5B544),
    error: Color(0xFFFF8A8A),
    errorFill: Color(0x2EFF6B6B),
    errorBorder: Color(0x73FF6B6B),
    bannerDetail: Color(0xC7FFFFFF),
    sheet: Color(0xFF16161B),
    sheetBorder: Color(0x14FFFFFF),
    sheetHandle: Color(0x38FFFFFF),
    sheetIcon: Color(0x8FFFFFFF),
    sheetSecondary: Color(0xA3FFFFFF),
    emptyDisc: Color(0x24646CFF),
    glanceCard: Color(0x940C0C10),
    glanceBorder: Color(0x24FFFFFF),
    glanceLabel: Color(0xCCFFFFFF),
    glanceTime: Color(0xDBFFFFFF),
    glanceMeta: Color(0xB8FFFFFF),
  );

  /// Builds a palette from a theme's roles. The Home glance and the fixed
  /// pairings keep their Classic values.
  factory CalendarColors.derive(HearthColors base) {
    const c = classic;
    return CalendarColors(
      accent: base.accent,
      accentText: base.accentText,
      onFill: c.onFill,
      text: base.text,
      textMuted: base.textSecondary,
      textDim: base.textMuted,
      textFaint: base.textMuted,
      gridLine: base.inkAt(0.13),
      divider: base.inkAt(0.10),
      control: base.inkAt(0.14),
      segmentTrack: base.inkAt(0.10),
      card: base.inkAt(0.07),
      todayTint: base.accent.withValues(alpha: 0.13),
      nowTint: base.accent.withValues(alpha: 0.30),
      weekendTint: base.inkAt(0.05),
      nowLine: base.text,
      pillOffOutline: base.inkAt(0.30),
      pillOffText: base.textMuted,
      pillOffAvatar: base.inkAt(0.12),
      pillAvatar: c.pillAvatar,
      stale: base.warning,
      staleFill: base.warning.withValues(alpha: 0.18),
      staleBorder: base.warning.withValues(alpha: 0.45),
      error: base.danger,
      errorFill: base.danger.withValues(alpha: 0.18),
      errorBorder: base.danger.withValues(alpha: 0.45),
      bannerDetail: base.textSecondary,
      sheet: base.raised,
      sheetBorder: base.inkAt(0.08),
      sheetHandle: base.inkAt(0.22),
      sheetIcon: base.textMuted,
      sheetSecondary: base.textSecondary,
      emptyDisc: base.accent.withValues(alpha: 0.14),
      glanceCard: c.glanceCard,
      glanceBorder: c.glanceBorder,
      glanceLabel: c.glanceLabel,
      glanceTime: c.glanceTime,
      glanceMeta: c.glanceMeta,
    );
  }

  static CalendarColors of(BuildContext context) =>
      HearthColors.of(context).calendar;

  /// Events that have ended.
  static const double pastOpacity = 0.55;

  /// A source colour lightened for a solid fill that carries dark text.
  static Color fill(Color source) =>
      Color.lerp(source, const Color(0xFFFFFFFF), 0.25)!;
}

class CalendarSizes {
  CalendarSizes._();

  /// Header rows: arrows, Today and title; then pills and view switcher.
  static const double headerRow = 80;

  /// Round prev/next buttons and the Today pill.
  static const double control = 56;
  static const double segment = 52;
  static const double segmentMinWidth = 68;
  static const double pill = 52;
  static const double pillAvatar = 40;
  static const double pillMaxText = 180;

  static const double hourHeight = 72;
  static const double gutter = 64;
  static const double gutterLabelWidth = 56;
  static const double dayHeader = 64;
  static const double dayNumber = 44;
  static const double bandRow = 36;
  static const double bandBar = 32;
  static const double nowLine = 3;

  /// Lifts an hour label so it centres on its grid line.
  static const double hourLabelLift = 9;

  /// Space around an event block inside its column.
  static const double blockGap = 3;

  /// Stroke of an outline: a tentative event, a hidden source's pill.
  static const double outline = 2;
  static const double blockPadH = 10;
  static const double blockPadV = 7;

  /// Vertical padding of a block too short for [blockPadV].
  static const double blockPadVTight = 2;
  static const double nowLabelWidth = 54;
  static const double nowLabelHeight = 24;

  static const double agendaRow = 76;
  static const double agendaTimeWidth = 84;
  static const double agendaAvatar = 40;

  static const double monthWeekdayRow = 40;
  static const double monthDayNumber = 32;
  static const double monthDayNumberDots = 40;
  static const double monthChip = 24;
  static const double monthChipGap = 2;
  static const double monthMore = 16;
  static const double monthChipDot = 9;
  static const double monthDot = 10;
  static const int monthMaxChips = 3;
  static const int monthMaxDots = 4;

  static const double banner = 52;
  static const double sheetClose = 56;
  static const double sheetDot = 16;
  static const double sheetRow = 48;
  static const double sheetMaxWidth = 720;
  static const double emptyDisc = 112;
  static const double emptyIcon = 52;

  static const double glanceRow = 56;
  static const double glanceDot = 14;
  static const double glanceTimeWidth = 116;
  static const double glanceMinWidth = 520;
  static const double glanceMaxWidth = 680;
  static const double glanceBlur = 24;
}

class CalendarShadows {
  CalendarShadows._();

  /// Lifts the Home glance card off the photo.
  static const List<BoxShadow> glance = [
    BoxShadow(color: Color(0x59000000), blurRadius: 32, offset: Offset(0, 8)),
  ];

  /// A black keyline either side of the white now line.
  static const List<BoxShadow> nowLine = [
    BoxShadow(color: Color(0xFF000000), spreadRadius: 1),
  ];
}

class CalendarRadii {
  CalendarRadii._();

  static const double block = 10;
  static const double bar = 8;
  static const double chip = 7;
  static const double card = 16;
  static const double banner = 14;
  static const double sheet = 28;
  static const double glance = 24;
}

/// Type sizes the shared [HearthFont] ramp has no step for.
class CalendarType {
  CalendarType._();

  /// Bundled, and what the design was drawn in.
  static const String family = 'Inter';

  /// The root text style for the screen, the sheets and the glance, with
  /// figures that line up in columns. Every [Material] in them takes it as
  /// its `textStyle`, or Material would put the theme's face back.
  static const TextStyle base = TextStyle(
    fontFamily: family,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Color(0xFFFFFFFF), // theme-exempt: const Classic text, see [of]
  );

  /// [base] with the theme's calendar text colour.
  static TextStyle of(BuildContext context) =>
      base.copyWith(color: CalendarColors.of(context).text);

  static const double title = 26;
  static const double control = 17;
  static const double today = 18;
  static const double weekday = 14;
  static const double dayNumber = 24;
  static const double hourLabel = 14;
  static const double blockTitle = 16;
  static const double blockMeta = 14;
  static const double blockLineHeight = 1.25;
  static const double bar = 15;
  static const double agendaTime = 19;
  static const double agendaTitle = 20;
  static const double agendaMeta = 16;
  static const double agendaHeader = 14;
  static const double monthChip = 15;
  static const double monthMore = 14;
  static const double monthNumber = 17;
  static const double banner = 17;
  static const double sheetTitle = 32;
  static const double sheetBody = 18;
  static const double glance = 24;
  static const double glanceLabel = 14;
  static const double glanceNow = 17;
  static const double glanceMeta = 18;

  /// Line heights of wrapping body copy and the sheet title.
  static const double bodyHeight = 1.5;
  static const double titleHeight = 1.25;

  /// Letter spacing of the upper-case labels.
  static const double capsTracking = 1.1;
  static const double glanceTracking = 2;
}
