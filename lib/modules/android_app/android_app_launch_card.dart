import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/tokens/tokens.dart';
import '../../config/android_app_config.dart';
import '../../config/hub_config.dart';
import '../../services/android_apps.dart';
import '../../services/toast_service.dart';

/// Launches [app] in the layout the tablet is set to. Shows a toast when the
/// package is not installed.
Future<void> launchAndroidApp(WidgetRef ref, AndroidAppConfig app) async {
  final layout = ref.read(hubConfigProvider).androidAppLayout;
  final ok = await ref.read(androidAppsBridgeProvider).launch(
        app.packageName,
        layout,
      );
  if (!ok) {
    ref
        .read(toastProvider.notifier)
        .show('${app.name} is not installed', icon: Icons.error_outline);
  }
}

/// The page for an app tile: icon, name and an Open button. Launching is
/// always a tap, never a side effect of swiping onto the page.
class AndroidAppLaunchCard extends ConsumerWidget {
  const AndroidAppLaunchCard({super.key, required this.app});

  final AndroidAppConfig app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.hearthColors;
    final icon = ref.watch(androidAppIconProvider(app.packageName)).valueOrNull;
    final installed = ref.watch(installedAndroidAppsProvider);
    final missing = installed.maybeWhen(
      data: (apps) => !apps.any((a) => a.packageName == app.packageName),
      orElse: () => false,
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HearthSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: icon != null
                  ? Image.memory(icon, fit: BoxFit.contain)
                  : Icon(Icons.apps, size: 72, color: colors.textSecondary),
            ),
            const SizedBox(height: HearthSpacing.x4),
            Text(
              app.name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: HearthFont.titleLg,
                color: colors.text,
              ),
            ),
            if (missing) ...[
              const SizedBox(height: HearthSpacing.x2),
              Text(
                'Not installed',
                style: TextStyle(
                  fontSize: HearthFont.body,
                  color: colors.danger,
                ),
              ),
            ],
            const SizedBox(height: HearthSpacing.x6),
            FilledButton(
              onPressed: missing ? null : () => launchAndroidApp(ref, app),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}
