import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import '../../services/app_updater.dart';
import '../../services/installed_version.dart';
import '../../services/toast_service.dart';
import '../../services/update_service.dart';
import '../../app/tokens/tokens.dart';

/// The installed version: `/etc/hearth-version` on the Pi, the package
/// version on Android.
final installedVersionProvider =
    FutureProvider<String>((ref) => readInstalledVersion());

/// Shows current version, latest available version, and the auto-update toggle.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final config = ref.watch(hubConfigProvider);
    final installedVersion =
        ref.watch(installedVersionProvider).valueOrNull ?? '';
    final latestAsync = ref.watch(latestUpdateProvider);

    return Column(
      children: [
        // Current version tile.
        ListTile(
          leading: Icon(Icons.info_outline, color: c.textMuted, size: HearthIcon.md),
          title: const Text('Current Version', style: TextStyle(fontSize: HearthFont.body)),
          subtitle: Text(
            installedVersion.isEmpty ? 'Unknown' : installedVersion,
            style: TextStyle(
              fontSize: HearthFont.label,
              color: c.textMuted,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        ),

        // Latest version tile with async state.
        ListTile(
          leading: latestAsync.when(
            data: (info) {
              if (info == null) {
                return Icon(Icons.check_circle_outline,
                    color: c.success, size: HearthIcon.md);
              }
              final isNewer = info.isNewerThan(installedVersion);
              return Icon(
                isNewer ? Icons.system_update_alt : Icons.check_circle_outline,
                color: isNewer ? c.warning : c.success,
                size: HearthIcon.md,
              );
            },
            loading: () => const SizedBox(
              width: HearthSpacing.x6,
              height: HearthSpacing.x6,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (err, _) =>
                Icon(Icons.error_outline, color: c.textMuted, size: HearthIcon.md),
          ),
          title: const Text('Latest Version', style: TextStyle(fontSize: HearthFont.body)),
          subtitle: latestAsync.when(
            data: (info) {
              if (info == null) {
                return Text(
                  'Up to date',
                  style: TextStyle(
                    fontSize: HearthFont.label,
                    color: c.textMuted,
                  ),
                );
              }
              final isNewer = info.isNewerThan(installedVersion);
              return Text(
                isNewer ? 'v${info.version} available' : 'Up to date',
                style: TextStyle(
                  fontSize: HearthFont.label,
                  color: isNewer
                      ? c.warning
                      : c.textMuted,
                ),
              );
            },
            loading: () => Text(
              'Checking…',
              style: TextStyle(
                fontSize: HearthFont.label,
                color: c.textMuted,
              ),
            ),
            error: (err, _) => Text(
              'Could not check',
              style: TextStyle(
                fontSize: HearthFont.label,
                color: c.textMuted,
              ),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        ),

        // Force update button.
        _ForceUpdateTile(),

        // Auto-update toggle.
        SwitchListTile(
          secondary: Icon(Icons.autorenew, color: c.textMuted, size: HearthIcon.md),
          title: const Text('Auto-Update', style: TextStyle(fontSize: HearthFont.body)),
          subtitle: Text(
            config.autoUpdate ? 'Install updates automatically' : 'Manual updates only',
            style: TextStyle(
              fontSize: HearthFont.label,
              color: c.textMuted,
            ),
          ),
          value: config.autoUpdate,
          onChanged: (v) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(autoUpdate: v)),
          contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        ),

        // Update source toggle.
        SwitchListTile(
          secondary: Icon(Icons.dns_outlined, color: c.textMuted, size: HearthIcon.md),
          title: const Text('Use Gitea for Updates', style: TextStyle(fontSize: HearthFont.body)),
          subtitle: Text(
            config.updateSource == 'gitea'
                ? 'Checking registry.home for releases'
                : 'Checking GitHub for releases',
            style: TextStyle(
              fontSize: HearthFont.label,
              color: c.textMuted,
            ),
          ),
          value: config.updateSource == 'gitea',
          onChanged: (v) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(updateSource: v ? 'gitea' : 'github')),
          contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        ),

        // Gitea API token (only when Gitea is selected).
        if (config.updateSource == 'gitea')
          ListTile(
            leading: Icon(Icons.key, color: c.textMuted, size: HearthIcon.md),
            title: const Text('Gitea API Token', style: TextStyle(fontSize: HearthFont.body)),
            subtitle: Text(
              config.giteaApiToken.isEmpty ? 'Not set' : 'Configured',
              style: TextStyle(
                fontSize: HearthFont.label,
                color: c.textMuted,
              ),
            ),
            onTap: () async {
              final controller = TextEditingController(text: config.giteaApiToken);
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: context.hearthColors.raised,
                  title: const Text('Gitea API Token'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Paste token here'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
                  ],
                ),
              );
              if (result != null) {
                ref.read(hubConfigProvider.notifier)
                    .update((c) => c.copyWith(giteaApiToken: result));
              }
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
          ),
      ],
    );
  }
}

class _ForceUpdateTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ForceUpdateTile> createState() => _ForceUpdateTileState();
}

class _ForceUpdateTileState extends ConsumerState<_ForceUpdateTile> {
  bool _updating = false;

  Future<void> _triggerUpdate() async {
    if (_updating || kIsWeb) return;
    if (Platform.isAndroid) return _triggerAndroidUpdate();
    setState(() => _updating = true);
    ref.read(toastProvider.notifier).show(
      'Checking for updates...',
      icon: Icons.system_update_alt,
    );
    try {
      final result = await Process.run(
        'sudo', ['systemctl', 'start', 'hearth-updater.service'],
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
        result.exitCode == 0
            ? 'Update triggered'
            : 'Failed to trigger update',
        icon: result.exitCode == 0 ? Icons.check_circle : Icons.error_outline,
        type: result.exitCode == 0 ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
        'Update error: $e',
        icon: Icons.error_outline,
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _triggerAndroidUpdate() async {
    final s = await ref.read(appUpdaterProvider.notifier).apply();
    if (!mounted) return;
    final failed = s.phase == AppUpdatePhase.failed ||
        s.phase == AppUpdatePhase.needsPermission;
    ref.read(toastProvider.notifier).show(
          s.message,
          icon: failed ? Icons.error_outline : Icons.system_update_alt,
          type: failed ? ToastType.error : ToastType.info,
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    if (!kIsWeb && Platform.isAndroid) return _buildAndroid();
    return ListTile(
      leading: _updating
          ? const SizedBox(
              width: HearthSpacing.x6, height: HearthSpacing.x6,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.download, color: c.textMuted, size: HearthIcon.md),
      title: const Text('Force Update', style: TextStyle(fontSize: HearthFont.body)),
      subtitle: Text(
        'Download and install the latest bundle',
        style: TextStyle(
          fontSize: HearthFont.label,
          color: c.textMuted,
        ),
      ),
      onTap: _updating ? null : _triggerUpdate,
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }

  Widget _buildAndroid() {
    final c = context.hearthColors;
    final s = ref.watch(appUpdaterProvider);
    final busy = s.busy;
    final failed = s.phase == AppUpdatePhase.failed ||
        s.phase == AppUpdatePhase.needsPermission;
    return ListTile(
      leading: busy
          ? SizedBox(
              width: HearthSpacing.x6, height: HearthSpacing.x6,
              child: CircularProgressIndicator(
                  strokeWidth: 2, value: s.progress),
            )
          : Icon(failed ? Icons.error_outline : Icons.download,
              color: failed ? c.warning : c.textMuted,
              size: HearthIcon.md),
      title: const Text('Install Update', style: TextStyle(fontSize: HearthFont.body)),
      subtitle: Text(
        s.message.isEmpty
            ? 'Download the latest APK and confirm the install'
            : s.message,
        style: TextStyle(
          fontSize: HearthFont.label,
          color: failed ? c.warning : c.textMuted,
        ),
      ),
      onTap: busy ? null : _triggerAndroidUpdate,
      contentPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
    );
  }
}
