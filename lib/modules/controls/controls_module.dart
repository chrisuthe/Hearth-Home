import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'controls_screen.dart';

class ControlsModule implements HearthModule {
  @override String get id => 'controls';
  @override String get name => 'Controls';
  @override IconData get icon => Icons.lightbulb_outline;
  @override int get defaultOrder => 10;

  @override
  bool isConfigured(HubConfig config) =>
      config.haUrl.isNotEmpty && config.pinnedEntityIds.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const ControlsScreen();

  @override
  Widget? buildSettingsSection() => null;
}
