import 'package:flutter/material.dart';

/// Placeholder for the home screen.
/// Will show clock, weather, scene buttons, and now-playing bar in Task 10.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Home',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
      ),
    );
  }
}
