import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/ambient/photo_carousel.dart';
import 'package:hearth/services/immich_service.dart';

void main() {
  group('PhotoCarousel', () {
    testWidgets('shows placeholder when no photos are available', (tester) async {
      final controller = StreamController<PhotoFrame?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoStream: controller.stream,
            ),
          ),
        ),
      );

      // No photos pushed — placeholder should be visible.
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.text('Photos unavailable'), findsOneWidget);
    });

    testWidgets('hides placeholder once a photo arrives', (tester) async {
      final controller = StreamController<PhotoFrame?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoStream: controller.stream,
            ),
          ),
        ),
      );

      // Placeholder visible initially.
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);

      // Push a photo — use a network URL so Image.network is used
      // (avoids needing a real file on disk).
      controller.add(
        (path: 'http://example.com/photo.jpg', focal: kCenterFocalPoint),
      );
      await tester.pump();

      // Placeholder should be gone.
      expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
      expect(find.text('Photos unavailable'), findsNothing);
    });

    testWidgets('biases the image alignment toward the focal point',
        (tester) async {
      final controller = StreamController<PhotoFrame?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoStream: controller.stream,
            ),
          ),
        ),
      );

      // A top-biased face (y < 0.5) should pull the crop window upward —
      // a negative Alignment.y.
      controller.add(
        (path: 'http://example.com/portrait.jpg', focal: (x: 0.5, y: 0.2)),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect((image.alignment as Alignment).x, closeTo(0.0, 1e-9));
      expect((image.alignment as Alignment).y, closeTo(-0.6, 1e-9));
    });

    testWidgets('ignores null values from stream', (tester) async {
      final controller = StreamController<PhotoFrame?>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoCarousel(
              photoStream: controller.stream,
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
