import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identity of the screen HubShell is currently showing.
///
/// The active page lives as private widget state (`_currentPage`) inside
/// HubShell and isn't observable from a service. This provider mirrors it so
/// non-widget code — notably [MqttService] — can read/publish the current
/// screen without reaching into HubShell.
class CurrentScreen {
  /// Screen id: a module id (e.g. "media"), or "home"/"settings" for the
  /// two non-module pages.
  final String id;

  /// Zero-based page index within HubShell's PageView.
  final int index;

  const CurrentScreen({required this.id, required this.index});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrentScreen && id == other.id && index == other.index;

  @override
  int get hashCode => Object.hash(id, index);
}

/// The screen HubShell is currently showing. HubShell updates this on every
/// page change; defaults to Home until the shell mounts.
final currentScreenProvider = StateProvider<CurrentScreen>(
  (ref) => const CurrentScreen(id: 'home', index: 0),
);
