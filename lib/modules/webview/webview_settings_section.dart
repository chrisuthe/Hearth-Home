import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import 'ha_dashboard_picker.dart';
import 'custom_url_editor.dart';

/// Settings card combining the HA dashboard picker and the custom URL list.
/// Shown in the Settings screen alongside other module settings.
class WebviewSettingsSection extends ConsumerWidget {
  const WebviewSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final config = ref.watch(hubConfigProvider);
    final haConfigured = config.haUrl.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: c.inkAt(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      // The tiles below paint ink on the nearest Material; without one of
      // their own it would land underneath this card's tint.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (haConfigured) ...[
              const HaDashboardPicker(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dark mode for HA dashboards'),
                subtitle: Text(
                  'Signal prefers-color-scheme: dark to Home Assistant',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                value: config.haDashboardDarkMode,
                onChanged: (v) => ref
                    .read(hubConfigProvider.notifier)
                    .update((c) => c.copyWith(haDashboardDarkMode: v)),
              ),
            ] else
              const _HaConfigPrompt(),
            const SizedBox(height: 24),
            const CustomUrlList(),
          ],
        ),
      ),
    );
  }
}

class _HaConfigPrompt extends StatelessWidget {
  const _HaConfigPrompt();

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.inkAt(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c.textFaint, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Configure Home Assistant connection first to auto-discover dashboards.',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
