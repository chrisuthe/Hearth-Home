import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'protect_screen.dart';

/// UniFi Protect camera screen module. Separate from the Frigate Cameras
/// module — the two coexist as distinct screens. Placed just right of Cameras
/// (order 25) by default; users move it via Screens & Order.
class ProtectModule implements HearthModule {
  @override String get id => 'protect';
  @override String get name => 'Protect';
  @override IconData get icon => Icons.security;
  @override int get defaultOrder => 25;

  @override
  bool isConfigured(HubConfig config) =>
      config.unifiProtectUrl.isNotEmpty &&
      config.unifiProtectApiKey.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) =>
      ProtectScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;
}
