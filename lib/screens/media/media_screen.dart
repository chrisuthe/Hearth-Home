import 'package:flutter/material.dart';

/// Placeholder for the media playback screen.
/// Will show album art, controls, zone picker in Task 11.
class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Media',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
      ),
    );
  }
}
