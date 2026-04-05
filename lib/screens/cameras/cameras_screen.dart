import 'package:flutter/material.dart';

/// Placeholder for the camera grid.
/// Will show Frigate MJPEG feeds and events in Task 13.
class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Cameras',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
      ),
    );
  }
}
