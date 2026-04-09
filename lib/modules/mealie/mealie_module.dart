import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../app/app.dart' show kDialogBackground;
import '../hearth_module.dart';
import 'mealie_screen.dart';

class MealieModule implements HearthModule {
  @override String get id => 'mealie';
  @override String get name => 'Recipes';
  @override IconData get icon => Icons.restaurant_menu;
  @override int get defaultOrder => 30;

  @override
  bool isConfigured(HubConfig config) =>
      config.mealieUrl.isNotEmpty && config.mealieToken.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const MealieScreen();

  @override
  Widget? buildSettingsSection() => const _MealieSettings();
}

class _MealieSettings extends ConsumerWidget {
  const _MealieSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MEALIE', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.4),
          letterSpacing: 1.2,
        )),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.restaurant_menu, color: Colors.white54, size: 22),
          title: const Text('Mealie URL', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.mealieUrl.isEmpty ? 'Not configured' : config.mealieUrl,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => _showTextInput(context, ref, 'Mealie URL', config.mealieUrl,
              'http://192.168.1.x:9925', (v) => ref.read(hubConfigProvider.notifier)
                  .update((c) => c.copyWith(mealieUrl: v))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        ListTile(
          leading: const Icon(Icons.key, color: Colors.white54, size: 22),
          title: const Text('Mealie API Token', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.mealieToken.isEmpty ? 'Not configured' : '\u2022' * 8,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => _showTextInput(context, ref, 'Mealie API Token', config.mealieToken,
              'Paste your Mealie API token', (v) => ref.read(hubConfigProvider.notifier)
                  .update((c) => c.copyWith(mealieToken: v)),
              obscure: true),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showTextInput(BuildContext context, WidgetRef ref, String title,
      String current, String hint, ValueChanged<String> onSave, {bool obscure = false}) {
    final controller = TextEditingController(text: current);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text(title),
        content: TextField(
          controller: controller, obscureText: obscure,
          decoration: InputDecoration(hintText: hint), autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); onSave(controller.text); },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
