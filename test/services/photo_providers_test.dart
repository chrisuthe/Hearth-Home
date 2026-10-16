import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/theme_providers.dart';
import 'package:hearth/config/hearth_theme_id.dart';
import 'package:hearth/config/screen_background.dart';
import 'package:hearth/services/immich_service.dart' show kCenterFocalPoint;
import 'package:hearth/services/photo_blur.dart';
import 'package:hearth/services/photo_providers.dart';

import 'photo_fixture.dart';

ProviderContainer _container(ScreenBackground background) {
  final c = ProviderContainer(
    overrides: [screenBackgroundProvider.overrideWithValue(background)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync());
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> writePhoto(String name) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(await redBluePng());
    return file.path;
  }

  testWidgets('a solid background yields null', (tester) async {
    await tester.runAsync(() async {
      final c = _container(ScreenBackground.solid);
      c.read(currentPhotoProvider.notifier).state =
          (path: await writePhoto('a.png'), focal: kCenterFocalPoint);
      expect(await c.read(blurredPhotoProvider.future), isNull);
    });
  });

  testWidgets('the sample is null for Solid unless the theme is Memories',
      (tester) async {
    await tester.runAsync(() async {
      final path = await writePhoto('a.png');
      final solid = _container(ScreenBackground.solid);
      solid.read(currentPhotoProvider.notifier).state =
          (path: path, focal: kCenterFocalPoint);
      expect(await solid.read(photoSampleProvider.future), isNull);

      final memories = ProviderContainer(overrides: [
        screenBackgroundProvider.overrideWithValue(ScreenBackground.solid),
        hearthThemeIdProvider.overrideWithValue(HearthThemeId.memories),
      ]);
      addTearDown(memories.dispose);
      memories.read(currentPhotoProvider.notifier).state =
          (path: path, focal: kCenterFocalPoint);
      expect((await memories.read(photoSampleProvider.future))!.width, 300);
    });
  });

  testWidgets('a photo that fails to decode yields a null sample',
      (tester) async {
    await tester.runAsync(() async {
      final file = File('${dir.path}/bad.png')..writeAsBytesSync([1, 2, 3]);
      final c = _container(ScreenBackground.blurred);
      c.read(currentPhotoProvider.notifier).state =
          (path: file.path, focal: kCenterFocalPoint);
      expect(await c.read(photoSampleProvider.future), isNull);
      expect(await c.read(blurredPhotoProvider.future), isNull);
    });
  });

  testWidgets('an http path yields null', (tester) async {
    await tester.runAsync(() async {
      final c = _container(ScreenBackground.blurred);
      c.read(currentPhotoProvider.notifier).state =
          (path: 'http://x/a.jpg', focal: kCenterFocalPoint);
      expect(await c.read(blurredPhotoProvider.future), isNull);
    });
  });

  testWidgets('a blurred background with a file yields a 300-wide image',
      (tester) async {
    await tester.runAsync(() async {
      final c = _container(ScreenBackground.blurred);
      c.read(currentPhotoProvider.notifier).state =
          (path: await writePhoto('a.png'), focal: kCenterFocalPoint);
      final image = await c.read(blurredPhotoProvider.future);
      expect(image!.width, 300);
    });
  });

  testWidgets('a new frame disposes the previous image', (tester) async {
    await tester.runAsync(() async {
      final c = _container(ScreenBackground.blurred);
      final notifier = c.read(currentPhotoProvider.notifier);
      notifier.state =
          (path: await writePhoto('a.png'), focal: kCenterFocalPoint);
      final first = (await c.read(blurredPhotoProvider.future))!;
      expect(first.debugDisposed, isFalse);

      notifier.state =
          (path: await writePhoto('b.png'), focal: kCenterFocalPoint);
      final second = (await c.read(blurredPhotoProvider.future))!;
      expect(first.debugDisposed, isTrue);
      expect(second.debugDisposed, isFalse);
    });
  });

  testWidgets('a change mid-decode disposes the superseded image',
      (tester) async {
    await tester.runAsync(() async {
      final pending = <Completer<ui.Image>>[];
      final c = ProviderContainer(overrides: [
        screenBackgroundProvider.overrideWithValue(ScreenBackground.blurred),
        photoDecodeProvider.overrideWithValue((bytes) {
          final completer = Completer<ui.Image>();
          pending.add(completer);
          return completer.future;
        }),
      ]);
      addTearDown(c.dispose);
      final notifier = c.read(currentPhotoProvider.notifier);

      notifier.state =
          (path: await writePhoto('a.png'), focal: kCenterFocalPoint);
      c.read(blurredPhotoProvider.future).ignore();
      while (pending.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      notifier.state =
          (path: await writePhoto('b.png'), focal: kCenterFocalPoint);
      final fresh = c.read(blurredPhotoProvider.future);
      while (pending.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final stale = await decodeSample(await redBluePng());
      pending[0].complete(stale);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stale.debugDisposed, isTrue);

      final current = await decodeSample(await redBluePng());
      pending[1].complete(current);
      final blurred = await fresh;
      expect(blurred, isNotNull);
      expect(blurred!.debugDisposed, isFalse);
      expect(current.debugDisposed, isFalse);
      expect(await c.read(photoSampleProvider.future), same(current));
    });
  });

  testWidgets('a photo change as the sample lands does not error the blur',
      (tester) async {
    await tester.runAsync(() async {
      final c = _container(ScreenBackground.blurred);
      final notifier = c.read(currentPhotoProvider.notifier);
      final a = await writePhoto('a.png');
      final b = await writePhoto('b.png');
      notifier.state = (path: a, focal: kCenterFocalPoint);

      // Change the photo the moment the first sample's data lands, before the
      // blur run resumes from awaiting it.
      var switched = false;
      c.listen<AsyncValue<ui.Image?>>(photoSampleProvider, (prev, next) {
        if (!switched && next.valueOrNull != null) {
          switched = true;
          notifier.state = (path: b, focal: kCenterFocalPoint);
          // Re-make the sample now, disposing the one the blur is about to use.
          c.read(photoSampleProvider);
        }
      });
      final blur = c.listen(blurredPhotoProvider, (_, _) {});
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(switched, isTrue);
      expect(blur.read().hasError, isFalse);
      final settled = await c.read(blurredPhotoProvider.future);
      expect(settled?.debugDisposed ?? false, isFalse);
    });
  });
}
