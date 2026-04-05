import 'package:flutter/material.dart';

/// Placeholder for the ambient photo display.
/// Will be replaced with Ken Burns photo carousel + overlays in Task 9.
class AmbientScreen extends StatelessWidget {
  const AmbientScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Ambient Display',
          style: TextStyle(color: Colors.white54, fontSize: 24),
        ),
      ),
    );
  }
}
