import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'home_assistant_service.dart';

/// A single Lovelace dashboard as reported by HA's
/// `lovelace/dashboards/list` WebSocket command.
class HaDashboard {
  final String urlPath;
  final String title;
  final String? icon;
  final bool showInSidebar;
  final bool requireAdmin;
  final String mode;

  const HaDashboard({
    required this.urlPath,
    required this.title,
    required this.icon,
    required this.showInSidebar,
    required this.requireAdmin,
    required this.mode,
  });

  /// Construct the full URL for this dashboard on the given HA host.
  /// Strips trailing slash from [haUrl] for consistent joining.
  String fullUrlOn(String haUrl) {
    final base =
        haUrl.endsWith('/') ? haUrl.substring(0, haUrl.length - 1) : haUrl;
    return '$base/$urlPath';
  }
}

/// Discovers Lovelace dashboards via the existing HA WebSocket connection.
///
/// Note: HA's default "Overview" dashboard is not returned by
/// `lovelace/dashboards/list` — that command only lists user-created
/// dashboards. Callers that want to expose Overview must add it manually.
class HaLovelaceService {
  final HomeAssistantService _ha;

  HaLovelaceService(this._ha);

  /// Calls `lovelace/dashboards/list` over the existing HA WebSocket
  /// connection. Returns the parsed dashboard list, or an empty list
  /// on any error.
  Future<List<HaDashboard>> listDashboards() async {
    if (!_ha.isConnected) {
      return const [];
    }
    try {
      final raw = await _ha.sendCommand({'type': 'lovelace/dashboards/list'});
      if (raw is! List) return const [];
      return parseDashboards(raw.cast<dynamic>());
    } catch (e, st) {
      Log.e('HALovelace', 'listDashboards failed: $e\n$st');
      return const [];
    }
  }

  /// Pure helper, exposed for unit testing without a live HA connection.
  static List<HaDashboard> parseDashboards(List<dynamic> raw) {
    return raw.cast<Map<String, dynamic>>().map((m) {
      return HaDashboard(
        urlPath: m['url_path'] as String? ?? 'lovelace',
        title: m['title'] as String? ?? 'Unnamed',
        icon: m['icon'] as String?,
        showInSidebar: m['show_in_sidebar'] as bool? ?? true,
        requireAdmin: m['require_admin'] as bool? ?? false,
        mode: m['mode'] as String? ?? 'storage',
      );
    }).toList();
  }
}

final haLovelaceServiceProvider = Provider<HaLovelaceService>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  return HaLovelaceService(ha);
});
