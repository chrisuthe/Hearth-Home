import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import 'framework/plugin_router.dart';
import 'framework/web_context.dart';

/// Top-level grouping for plugins in the sidebar.
///
///   * [feature] — external services (HA, Immich, etc.) and feature plugins
///     (Webviews, Alarm Clock, Sendspin). Community-contributed plugins land
///     here by convention.
///   * [device] — settings about the kiosk itself (Display, Audio, Voice,
///     Network, System, Screens & Order).
enum PluginCategory { feature, device }

/// Plugin configuration status — drives the sidebar status dot and any
/// in-panel banner.
enum PluginConfigStatus {
  /// All required fields set, no runtime errors.
  configured,

  /// Required fields incomplete.
  needsSetup,

  /// Optional fields missing — works but not at full capability.
  partial,

  /// Active runtime error (HA disconnected, can't reach Frigate, etc.).
  error,
}

/// A swipe-able PageView screen contributed by a plugin.
///
/// Subsumes today's [HearthModule.buildScreen] cleanly. Plugins that don't
/// have a screen return `null` from [HearthPlugin.pageScreen].
class PageScreen {
  /// Returns the screen widget. [isActive] mirrors today's HearthModule
  /// contract — true when this screen is the current PageView page.
  final Widget Function({required bool isActive}) build;

  /// Where the screen can be placed in HubShell. Subset of:
  /// `['swipe', 'menu1', 'menu2']`. Default: swipe only.
  final List<String> placements;

  const PageScreen({required this.build, this.placements = const ['swipe']});
}

/// Contract every settings owner implements.
///
/// One plugin = one sidebar entry = one settings panel rendered on both
/// surfaces (Flutter on-device, HTML on the web portal). Optionally
/// contributes a PageView screen and/or backend HTTP routes.
///
/// See `docs/specs/2026-05-22-settings-unification-design.md` for the
/// full design rationale.
abstract class HearthPlugin {
  /// Stable identifier. Namespace: `hearth.<name>` for first-party,
  /// `community.<name>` for contributed plugins.
  String get id;

  /// Human display name shown in sidebar and panel header.
  String get name;

  /// Icon used in the sidebar row and panel header.
  IconData get icon;

  /// Determines sidebar category.
  PluginCategory get category;

  /// Sort order within category. First-party uses multiples of 10
  /// (10, 20, 30, ...); community plugins use whatever — natural sort
  /// applies.
  int get order;

  /// True for community-contributed plugins. UI surfaces this as a
  /// trust badge.
  bool get isCommunity;

  /// Whether this plugin appears as a sidebar entry, given the current
  /// config. Default `true` — every plugin is always visible. Override to
  /// gate a plugin behind a config flag (e.g. Capture appears only when
  /// `captureToolsEnabled` is set). Filtered where the sidebar lists are
  /// built, on both surfaces; routes are NOT auto-gated, so a hidden
  /// plugin's handlers must enforce the same gate themselves.
  bool isVisible(HubConfig config) => true;

  /// Configuration status derived from the current HubConfig.
  PluginConfigStatus statusFor(HubConfig config);

  /// Flutter widget rendered when this plugin is selected on-device.
  Widget buildSettingsWidget(WidgetRef ref);

  /// HTML fragment rendered when this plugin is selected in the web portal.
  /// See [WebContext] for what the plugin can read.
  String buildSettingsHtml(WebContext ctx);

  /// If non-null, this plugin contributes a swipe-able screen to HubShell.
  PageScreen? get pageScreen => null;

  /// Plugins with backend actions register their routes here. Default
  /// implementation registers nothing.
  void registerHttpRoutes(PluginRouter router) {}

  /// Other plugin IDs this plugin requires to be configured. The framework
  /// shows a dependency banner if a required plugin is unconfigured.
  List<String> get dependencies => const [];
}
