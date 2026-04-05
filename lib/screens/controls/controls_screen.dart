import 'package:flutter/material.dart';

/// Placeholder for device controls.
/// Will show light cards and climate cards in Task 12.
class ControlsScreen extends StatelessWidget {
  const ControlsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Controls',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
      ),
    );
  }
}
