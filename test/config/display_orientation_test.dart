import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/display_orientation.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  group('DisplayOrientation', () {
    test('wire values are the documented five', () {
      expect(DisplayOrientation.values.map((o) => o.wire), [
        'auto',
        'landscape',
        'portrait',
        'landscapeFlipped',
        'portraitFlipped',
      ]);
    });

    test('fromWire round-trips every value', () {
      for (final o in DisplayOrientation.values) {
        expect(DisplayOrientation.fromWire(o.wire), o);
      }
    });

    test('fromWire maps unknown and null to auto', () {
      expect(DisplayOrientation.fromWire(null), DisplayOrientation.auto);
      expect(DisplayOrientation.fromWire(''), DisplayOrientation.auto);
      expect(DisplayOrientation.fromWire('sideways'), DisplayOrientation.auto);
      expect(DisplayOrientation.fromWire('Portrait'), DisplayOrientation.auto);
    });

    test('maps to flutter-pi rotation degrees', () {
      expect(DisplayOrientation.auto.piRotationDegrees, 0);
      expect(DisplayOrientation.landscape.piRotationDegrees, 0);
      expect(DisplayOrientation.portrait.piRotationDegrees, 90);
      expect(DisplayOrientation.landscapeFlipped.piRotationDegrees, 180);
      expect(DisplayOrientation.portraitFlipped.piRotationDegrees, 270);
    });

    test('maps to Android preferred orientations', () {
      expect(DisplayOrientation.auto.androidOrientations,
          unorderedEquals(DeviceOrientation.values));
      expect(DisplayOrientation.landscape.androidOrientations,
          [DeviceOrientation.landscapeLeft]);
      expect(DisplayOrientation.portrait.androidOrientations,
          [DeviceOrientation.portraitUp]);
      expect(DisplayOrientation.landscapeFlipped.androidOrientations,
          [DeviceOrientation.landscapeRight]);
      expect(DisplayOrientation.portraitFlipped.androidOrientations,
          [DeviceOrientation.portraitDown]);
    });

    test('every value has a label', () {
      final labels = DisplayOrientation.values.map((o) => o.label).toSet();
      expect(labels, hasLength(DisplayOrientation.values.length));
    });
  });

  group('HubConfig.displayOrientation', () {
    test('defaults to auto', () {
      expect(const HubConfig().displayOrientation, 'auto');
    });

    test('round-trips every value through JSON', () {
      for (final o in DisplayOrientation.values) {
        final restored = HubConfig.fromJson(
            HubConfig(displayOrientation: o.wire).toJson());
        expect(restored.displayOrientation, o.wire);
      }
    });

    test('missing key loads as auto', () {
      final json = const HubConfig().toJson()..remove('displayOrientation');
      expect(HubConfig.fromJson(json).displayOrientation, 'auto');
    });

    test('unknown or mistyped value loads as auto', () {
      final json = const HubConfig().toJson();
      expect(
          HubConfig.fromJson({...json, 'displayOrientation': 'sideways'})
              .displayOrientation,
          'auto');
      expect(
          HubConfig.fromJson({...json, 'displayOrientation': 90})
              .displayOrientation,
          'auto');
    });

    test('copyWith sets it and otherwise preserves it', () {
      const config = HubConfig(displayOrientation: 'portrait');
      expect(config.copyWith(immichUrl: 'http://x').displayOrientation,
          'portrait');
      expect(
          config.copyWith(displayOrientation: 'landscapeFlipped')
              .displayOrientation,
          'landscapeFlipped');
    });
  });
}
