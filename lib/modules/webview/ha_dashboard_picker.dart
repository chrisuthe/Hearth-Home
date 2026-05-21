import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../config/webview_config.dart';
import '../../services/ha_lovelace_service.dart';

/// Lists HA Lovelace dashboards discovered via the WebSocket API and lets
/// the user toggle which ones appear as webview screens in Hearth.
///
/// Auto-fetches dashboards on first build. A manual "Refresh" button
/// re-fetches.
class HaDashboardPicker extends ConsumerStatefulWidget {
  const HaDashboardPicker({super.key});

  @override
  ConsumerState<HaDashboardPicker> createState() => _HaDashboardPickerState();
}

class _HaDashboardPickerState extends ConsumerState<HaDashboardPicker> {
  late Future<List<HaDashboard>> _dashboardsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _dashboardsFuture = ref.read(haLovelaceServiceProvider).listDashboards();
  }

  IconData _materialIconFor(String? mdiIcon) {
    // Best-effort mapping for common HA defaults.
    switch (mdiIcon) {
      case 'mdi:view-dashboard':
        return Icons.dashboard;
      case 'mdi:lightbulb':
        return Icons.lightbulb_outline;
      case 'mdi:thermometer':
        return Icons.thermostat;
      case 'mdi:home':
        return Icons.home;
      case 'mdi:flash':
        return Icons.bolt;
      case 'mdi:security':
        return Icons.security;
      case 'mdi:map':
        return Icons.map;
      default:
        return Icons.dashboard;
    }
  }

  void _toggle(HaDashboard dashboard, bool enable) {
    final config = ref.read(hubConfigProvider);
    final notifier = ref.read(hubConfigProvider.notifier);
    final webviewId = 'webview:ha:${dashboard.urlPath}';
    final exists = config.webviews.any((w) => w.id == webviewId);

    if (enable && !exists) {
      final newConfig = WebviewConfig(
        id: webviewId,
        url: dashboard.fullUrlOn(config.haUrl),
        name: dashboard.title,
        iconCodePoint: _materialIconFor(dashboard.icon).codePoint,
        source: WebviewSource.haDashboard,
        order: config.webviews.length,
      );
      notifier.update((c) => c.copyWith(webviews: [...c.webviews, newConfig]));
    } else if (!enable && exists) {
      notifier.update((c) => c.copyWith(
            webviews: c.webviews.where((w) => w.id != webviewId).toList(),
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.dashboard, color: Color(0xFF03A9F4), size: 18),
            const SizedBox(width: 8),
            const Text('Home Assistant dashboards',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(_refresh),
              child: const Text('Refresh'),
            ),
          ],
        ),
        FutureBuilder<List<HaDashboard>>(
          future: _dashboardsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF646CFF))),
              );
            }
            final dashboards = snapshot.data ?? const [];
            if (dashboards.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'No dashboards found. Check HA connection in settings.',
                    style: TextStyle(color: Colors.white54)),
              );
            }
            return Column(
              children: dashboards.map((d) {
                final webviewId = 'webview:ha:${d.urlPath}';
                final enabled =
                    config.webviews.any((w) => w.id == webviewId);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.title,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(d.urlPath,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  value: enabled,
                  onChanged: (v) => _toggle(d, v),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
