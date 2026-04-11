import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
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
  Widget? buildSettingsSection() => null;
}
