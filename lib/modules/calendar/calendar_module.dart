import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'calendar_screen.dart';

class CalendarModule implements HearthModule {
  @override String get id => 'calendar';
  @override String get name => 'Calendar';
  @override IconData get icon => Icons.calendar_month;
  @override int get defaultOrder => 5;

  @override
  bool isConfigured(HubConfig config) =>
      config.calendarSources.any((s) => s.enabled);

  @override
  Widget buildScreen({required bool isActive}) =>
      CalendarScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;
}
