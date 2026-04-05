import 'package:flutter/material.dart';

/// Placeholder for the settings screen.
/// Will show connection config and display settings in Task 14.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Settings',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
      ),
    );
  }
}
