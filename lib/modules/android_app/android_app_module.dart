import 'package:flutter/material.dart';
import '../../config/android_app_config.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'android_app_launch_card.dart';

/// A [HearthModule] for one installed Android app. Produced by
/// `modulesForConfig` on Android only. Its screen is a launch card; in an
/// edge menu `HubShell` launches the app directly.
class AndroidAppModule implements HearthModule {
  final AndroidAppConfig config;

  const AndroidAppModule(this.config);

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  IconData get icon => Icons.apps;

  @override
  int get defaultOrder => 200;

  @override
  bool isConfigured(HubConfig hubConfig) => true;

  @override
  Widget buildScreen({required bool isActive}) =>
      AndroidAppLaunchCard(app: config);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;

  @override
  bool get showsPhoto => false;
}
