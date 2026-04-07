import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../services/update_service.dart';

/// Shows current version, latest available version, and the auto-update toggle.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final latestAsync = ref.watch(latestUpdateProvider);

    return Column(
      children: [
        // Current version tile.
        ListTile(
          leading: const Icon(Icons.info_outline, color: Colors.white54, size: 22),
          title: const Text('Current Version', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.currentVersion.isEmpty ? 'Unknown' : config.currentVersion,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),

        // Latest version tile with async state.
        ListTile(
          leading: latestAsync.when(
            data: (info) {
              if (info == null) {
                return const Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 22);
              }
              final isNewer = info.isNewerThan(config.currentVersion);
              return Icon(
                isNewer ? Icons.system_update_alt : Icons.check_circle_outline,
                color: isNewer ? Colors.amber : Colors.green,
                size: 22,
              );
            },
            loading: () => const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (err, _) =>
                const Icon(Icons.error_outline, color: Colors.white54, size: 22),
          ),
          title: const Text('Latest Version', style: TextStyle(fontSize: 15)),
          subtitle: latestAsync.when(
            data: (info) {
              if (info == null) {
                return Text(
                  'Up to date',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                );
              }
              final isNewer = info.isNewerThan(config.currentVersion);
              return Text(
                isNewer ? 'v${info.version} available' : 'Up to date',
                style: TextStyle(
                  fontSize: 13,
                  color: isNewer
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.4),
                ),
              );
            },
            loading: () => Text(
              'Checking…',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            error: (err, _) => Text(
              'Could not check',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),

        // Auto-update toggle.
        SwitchListTile(
          secondary: const Icon(Icons.autorenew, color: Colors.white54, size: 22),
          title: const Text('Auto-Update', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.autoUpdate ? 'Install updates automatically' : 'Manual updates only',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          value: config.autoUpdate,
          onChanged: (v) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(autoUpdate: v)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ],
    );
  }
}
