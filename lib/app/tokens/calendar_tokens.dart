// Design tokens for the Calendar screen and the Home calendar glance.
//
// From the approved "Hearth Calendar redesign" canvas: solid source fills
// with dark text, name pills, and kiosk-sized touch targets. Values are
// unscaled logical pixels on the 1184x864 canvas; [HearthScaleScope] scales
// them like every other token.

import 'package:flutter/painting.dart';

class CalendarColors {
  CalendarColors._();

  /// Selected view, today's date, the now label.
  static const Color accent = Color(0xFF646CFF);

  /// The accent as text on black: weekday and section labels for today.
  static const Color accentText = Color(0xFF9EA3FF);

  /// Text on a solid source fill.
  static const Color onFill = Color(0xFF111116);

  static const Color text = Color(0xFFFFFFFF);

  /// Secondary text: weekday labels, agenda section headers.
  static const Color textMuted = Color(0xC7FFFFFF);

  /// Tertiary text: hour labels, agenda end times.
  static const Color textDim = Color(0xA8FFFFFF);

  /// A month cell number outside the month shown.
  static const Color textFaint = Color(0x73FFFFFF);

  static const Color gridLine = Color(0x21FFFFFF);
  static const Color divider = Color(0x1AFFFFFF);

  /// Fill of the round header buttons.
  static const Color control = Color(0x24FFFFFF);

  /// Track behind the view switcher.
  static const Color segmentTrack = Color(0x1AFFFFFF);

  /// Agenda row card.
  static const Color card = Color(0x12FFFFFF);

  /// Today's column in the time grid and the selected month cell.
  static const Color todayTint = Color(0x21646CFF);

  /// The agenda row of an event in progress.
  static const Color nowTint = Color(0x4D646CFF);

  static const Color weekendTint = Color(0x0DFFFFFF);

  /// White, so it stays visible across an accent-coloured event.
  static const Color nowLine = Color(0xFFFFFFFF);

  /// Outline of a hidden source's pill.
  static const Color pillOffOutline = Color(0x4DFFFFFF);
  static const Color pillOffText = Color(0x99FFFFFF);
  static const Color pillOffAvatar = Color(0x1FFFFFFF);

  /// Initial circle on a solid pill.
  static const Color pillAvatar = Color(0x33000000);

  static const Color stale = Color(0xFFF5B544);
  static const Color staleFill = Color(0x2EF5B544);
  static const Color staleBorder = Color(0x73F5B544);
  static const Color error = Color(0xFFFF7A7A);
  static const Color errorFill = Color(0x2EFF6B6B);
  static const Color errorBorder = Color(0x73FF6B6B);

  /// Detail text inside a status banner.
  static const Color bannerDetail = Color(0xC7FFFFFF);

  static const Color sheet = Color(0xFF16161B);
  static const Color sheetBorder = Color(0x14FFFFFF);
  static const Color sheetHandle = Color(0x38FFFFFF);
  static const Color sheetIcon = Color(0x8FFFFFFF);
  static const Color sheetSecondary = Color(0xA3FFFFFF);

  /// The not-configured icon disc.
  static const Color emptyDisc = Color(0x24646CFF);

  /// The Home glance card, over a photo that could be anything.
  static const Color glanceCard = Color(0x940C0C10);
  static const Color glanceBorder = Color(0x24FFFFFF);
  static const Color glanceLabel = Color(0xCCFFFFFF);
  static const Color glanceTime = Color(0xDBFFFFFF);
  static const Color glanceMeta = Color(0xB8FFFFFF);

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
