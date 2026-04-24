import 'package:flutter/material.dart';

/// Vertical 3-stop sky gradient.
class SkyGradient extends StatelessWidget {
  final List<Color> stops;
  const SkyGradient(this.stops, {super.key});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: stops,
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}
