import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../../config/webview_config.dart';
import '../hearth_module.dart';
import 'webview_screen.dart';

/// A [HearthModule] backed by a single [WebviewConfig]. One instance per
/// configured webview is produced by `allModulesProvider`.
///
/// The shared Settings UI for managing webviews lives in
/// `webview_settings_section.dart` (added in Task 13); individual
/// `WebviewModule` instances return `null` from [buildSettingsSection]
/// to avoid duplicating that UI per webview.
class WebviewModule implements HearthModule {
  final WebviewConfig config;

  const WebviewModule({required this.config});

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  IconData get icon => config.icon;

  @override
  int get defaultOrder => config.defaultOrder;

  @override
  bool isConfigured(HubConfig hubConfig) => config.url.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) =>
      WebviewScreen(config: config, isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;
}
