import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/ambient/photo_carousel.dart';
import 'package:hearth/services/immich_service.dart';

void main() {
  test('photoDecodeWidth is the longer physical side', () {
    expect(photoDecodeWidth(const Size(2368, 1728)), 2368);
    expect(photoDecodeWidth(const Size(1728, 2368)), 2368);
    expect(photoDecodeWidth(const Size(1184, 864)), 1184);
  });

  testWidgets('default provider is a ResizeImage at the decode width',
      (tester) async {
    final controller = StreamController<PhotoFrame?>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PhotoCarousel(photoStream: controller.stream)),
    ));
    controller.add((path: 'http://x/a.jpg', focal: kCenterFocalPoint));
    await tester.pump();

    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>());
    final view = tester.view;
    expect((provider as ResizeImage).width, photoDecodeWidth(view.physicalSize));
  });

  _decodeGateTests();
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

/// An image whose decode completes only when the test releases it.
class _GatedImage extends ImageProvider<_GatedImage> {
  final String path;
  final Completer<ImageInfo> gate;
  _GatedImage(this.path, this.gate);

  @override
  Future<_GatedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _GatedImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(gate.future);

  @override
  bool operator ==(Object other) => other is _GatedImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

void _decodeGateTests() {
  group('PhotoCarousel decode gating', () {
    late StreamController<PhotoFrame?> controller;
    late Map<String, Completer<ImageInfo>> gates;
    late List<PhotoFrame> started;

    PhotoFrame frame(String name) =>
        (path: 'http://x/$name.jpg', focal: kCenterFocalPoint);

    // Providers are keyed by path, so a previous test's decode would hit.
    setUp(() => PaintingBinding.instance.imageCache.clear());

    Future<void> pumpCarousel(WidgetTester tester) async {
      controller = StreamController<PhotoFrame?>.broadcast();
      addTearDown(controller.close);
      gates = {};
      started = [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PhotoCarousel(
            photoStream: controller.stream,
            onCrossfadeStart: started.add,
            imageProviderFor: (f, _) => _GatedImage(
                f.path, gates.putIfAbsent(f.path, () => Completer<ImageInfo>())),
          ),
        ),
      ));
      // The first photo shows immediately.
      controller.add(frame('a'));
      await tester.pump();
      expect(started, [frame('a')]);
      started.clear();
    }

    Finder fades() => find.descendant(
        of: find.byType(PhotoCarousel), matching: find.byType(FadeTransition));

    Future<void> release(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        final image = await createTestImage(width: 2, height: 2);
        gates['http://x/$name.jpg']!.complete(ImageInfo(image: image));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
    }

    testWidgets('crossfade waits for decode', (tester) async {
      await pumpCarousel(tester);
      controller.add(frame('b'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(fades(), findsNothing);
      expect(started, isEmpty);

      await release(tester, 'b');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fades(), findsOneWidget);
      expect(started, [frame('b')]);
      await tester.pumpAndSettle();
      expect(started, [frame('b')]);
    });

    testWidgets('newer frame wins', (tester) async {
      await pumpCarousel(tester);
      controller.add(frame('b'));
      await tester.pump();
      controller.add(frame('c'));
      await tester.pump();

      await release(tester, 'b');
      await release(tester, 'c');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fades(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(started, [frame('c')]);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as _GatedImage).path, frame('c').path);
    });

    testWidgets('a frame decoded mid-fade restarts the fade and wins',
        (tester) async {
      await pumpCarousel(tester);
      controller.add(frame('b'));
      await tester.pump();
      await release(tester, 'b');
      await tester.pump(const Duration(milliseconds: 500));
      expect(fades(), findsOneWidget);

      controller.add(frame('c'));
      await tester.pump();
      await release(tester, 'c');
      await tester.pumpAndSettle();
      expect(started, [frame('b'), frame('c')]);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as _GatedImage).path, frame('c').path);
    });
  });
}
