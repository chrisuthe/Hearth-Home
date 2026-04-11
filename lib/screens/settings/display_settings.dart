import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../config/hub_config.dart';

/// Settings tile for choosing the display profile.
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({super.key});

  static const _profiles = {
    'auto': 'Auto-detect',
    'amoled-11': '11" AMOLED (1184x864)',
    'rpi-7': 'RPi 7" Touchscreen (800x480)',
    'hdmi': 'HDMI Monitor (native)',
  };

  Future<void> _showProfilePicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: kDialogBackground,
        title: const Text('Display Profile'),
        children: _profiles.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.key),
            child: Row(
              children: [
                if (entry.key == current)
                  const Icon(Icons.check, size: 18, color: Colors.amber)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 12),
                Text(entry.value),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (result != null) {
      await ref
          .read(hubConfigProvider.notifier)
          .update((c) => c.copyWith(displayProfile: result));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final label = _profiles[config.displayProfile] ?? config.displayProfile;

    return ListTile(
      leading: const Icon(Icons.monitor, color: Colors.white54, size: 22),
      title: const Text('Display Profile', style: TextStyle(fontSize: 15)),
      subtitle: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => _showProfilePicker(context, ref, config.displayProfile),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
