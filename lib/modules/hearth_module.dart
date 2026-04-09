import 'package:flutter/material.dart';
import '../config/hub_config.dart';

/// Interface for pluggable Hearth screen modules.
///
/// Each optional screen (Cameras, Controls, Media, Recipes) implements
/// this interface. The module registry collects all implementations and
/// HubShell builds the PageView dynamically from enabled modules.
abstract class HearthModule {
  /// Unique identifier stored in config (e.g., 'mealie', 'cameras').
  String get id;

  /// Display name shown in Settings (e.g., 'Recipes', 'Cameras').
  String get name;

  /// Icon for page indicators and module settings toggles.
  IconData get icon;

  /// Default sort position in the PageView. Lower = further left from Home.
  /// Negative = left of Home, positive = right of Home.
  int get defaultOrder;

  /// Whether this module has enough config to function.
  /// A module can be enabled but not configured — it shows a setup prompt.
  bool isConfigured(HubConfig config);

  /// The main screen widget for the PageView.
  Widget buildScreen({required bool isActive});

  /// Settings section widget, or null if the module needs no settings.
  Widget? buildSettingsSection();
}
