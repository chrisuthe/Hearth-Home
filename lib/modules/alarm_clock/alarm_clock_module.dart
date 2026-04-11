import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'alarm_clock_screen.dart';

class AlarmClockModule implements HearthModule {
  @override String get id => 'alarm_clock';
  @override String get name => 'Alarms';
  @override IconData get icon => Icons.alarm;
  @override int get defaultOrder => -5;

  @override
  bool isConfigured(HubConfig config) => true; // No external config needed.

  @override
  Widget buildScreen({required bool isActive}) => const AlarmClockScreen();

  @override
  Widget? buildSettingsSection() => null;
}
