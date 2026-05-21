import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import 'ha_dashboard_picker.dart';
import 'custom_url_editor.dart';

/// Settings card combining the HA dashboard picker and the custom URL list.
/// Shown in the Settings screen alongside other module settings.
class WebviewSettingsSection extends ConsumerWidget {
  const WebviewSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final haConfigured = config.haUrl.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (haConfigured)
            const HaDashboardPicker()
          else
            const _HaConfigPrompt(),
          const SizedBox(height: 24),
          const CustomUrlList(),
        ],
      ),
    );
  }
}

class _HaConfigPrompt extends StatelessWidget {
  const _HaConfigPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.white38, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Configure Home Assistant connection first to auto-discover dashboards.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
