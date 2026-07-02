import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'live_tv_screen.dart';

/// Plex Live TV — a client-initiated module (browse channels → tune → play).
/// Distinct from the cast-sink Plex path: Hearth acts as a Plex *client* here.
class LiveTvModule implements HearthModule {
  @override
  String get id => 'livetv';
  @override
  String get name => 'Live TV';
  @override
  IconData get icon => Icons.live_tv;
  @override
  int get defaultOrder => 15;

  /// Needs the Plex plugin paired (an account token) to browse/tune.
  @override
  bool isConfigured(HubConfig config) => config.plexAuthToken.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) =>
      LiveTvScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;
}
