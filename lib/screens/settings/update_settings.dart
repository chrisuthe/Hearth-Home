import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../services/update_service.dart';

/// Reads installed version from /etc/hearth-version (written by the OTA updater).
final installedVersionProvider = Provider<String>((ref) {
  if (kIsWeb) return '';
  try {
    return File('/etc/hearth-version').readAsStringSync().trim();
  } catch (_) {
    return '';
  }
});

/// Shows current version, latest available version, and the auto-update toggle.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final installedVersion = ref.watch(installedVersionProvider);
    final latestAsync = ref.watch(latestUpdateProvider);

    return Column(
      children: [
        // Current version tile.
        ListTile(
          leading: const Icon(Icons.info_outline, color: Colors.white54, size: 22),
          title: const Text('Current Version', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            installedVersion.isEmpty ? 'Unknown' : installedVersion,
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
              final isNewer = info.isNewerThan(installedVersion);
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
              final isNewer = info.isNewerThan(installedVersion);
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

        // Force update button.
        _ForceUpdateTile(),

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

class _ForceUpdateTile extends StatefulWidget {
  @override
  State<_ForceUpdateTile> createState() => _ForceUpdateTileState();
}

class _ForceUpdateTileState extends State<_ForceUpdateTile> {
  bool _updating = false;

  Future<void> _triggerUpdate() async {
    if (_updating || kIsWeb) return;
    setState(() => _updating = true);
    try {
      final result = await Process.run(
        'sudo', ['systemctl', 'start', 'hearth-updater.service'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.exitCode == 0
              ? 'Update triggered — the app will restart if a new version is found'
              : 'Failed to trigger update'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _updating
          ? const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download, color: Colors.white54, size: 22),
      title: const Text('Force Update', style: TextStyle(fontSize: 15)),
      subtitle: Text(
        'Download and install the latest bundle',
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      onTap: _updating ? null : _triggerUpdate,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
