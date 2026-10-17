import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'lists_screen.dart';

class ListsModule implements HearthModule {
  @override String get id => 'lists';
  @override String get name => 'Lists';
  @override IconData get icon => Icons.checklist;
  @override int get defaultOrder => 7;

  @override
  bool isConfigured(HubConfig config) => config.todoLists.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) =>
      ListsScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;

  @override
  bool get isCommunity => false;

  @override
  bool get showsPhoto => false;
}
