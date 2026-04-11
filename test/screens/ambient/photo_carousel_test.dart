import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/ambient/photo_carousel.dart';

void main() {
  group('PhotoCarousel', () {
    testWidgets('shows placeholder when no photos are available', (tester) async {
      final controller = StreamController<String?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoPathStream: controller.stream,
            ),
          ),
        ),
      );

      // No photos pushed — placeholder should be visible.
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.text('Photos unavailable'), findsOneWidget);
    });

    testWidgets('hides placeholder once a photo arrives', (tester) async {
      final controller = StreamController<String?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoPathStream: controller.stream,
            ),
          ),
        ),
      );

      // Placeholder visible initially.
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);

      // Push a photo path — use a network URL so Image.network is used
      // (avoids needing a real file on disk).
      controller.add('http://example.com/photo.jpg');
      await tester.pump();

      // Placeholder should be gone.
      expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
      expect(find.text('Photos unavailable'), findsNothing);
    });

    testWidgets('ignores null values from stream', (tester) async {
      final controller = StreamController<String?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoPathStream: controller.stream,
            ),
          ),
        ),
      );

      // Push null — should still show placeholder.
      controller.add(null);
      await tester.pump();

      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    });
  });
}
