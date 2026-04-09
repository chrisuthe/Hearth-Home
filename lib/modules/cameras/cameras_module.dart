import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'cameras_screen.dart';

class CamerasModule implements HearthModule {
  @override String get id => 'cameras';
  @override String get name => 'Cameras';
  @override IconData get icon => Icons.videocam;
  @override int get defaultOrder => 20;

  @override
  bool isConfigured(HubConfig config) => config.frigateUrl.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => CamerasScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;
}
