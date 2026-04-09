import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'media_screen.dart';

class MediaModule implements HearthModule {
  @override String get id => 'media';
  @override String get name => 'Music';
  @override IconData get icon => Icons.music_note;
  @override int get defaultOrder => -10;

  @override
  bool isConfigured(HubConfig config) => config.musicAssistantUrl.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const MediaScreen();

  @override
  Widget? buildSettingsSection() => null;
}
