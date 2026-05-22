import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/plugins/hearth_plugin.dart';

void main() {
  group('HearthPlugin enums', () {
    test('PluginCategory has feature and device values', () {
      expect(PluginCategory.values.length, 2);
      expect(PluginCategory.values, contains(PluginCategory.feature));
      expect(PluginCategory.values, contains(PluginCategory.device));
    });

    test('PluginConfigStatus has four values', () {
      expect(PluginConfigStatus.values.length, 4);
      expect(PluginConfigStatus.values, contains(PluginConfigStatus.configured));
      expect(PluginConfigStatus.values, contains(PluginConfigStatus.needsSetup));
      expect(PluginConfigStatus.values, contains(PluginConfigStatus.partial));
      expect(PluginConfigStatus.values, contains(PluginConfigStatus.error));
    });
  });

  group('PageScreen', () {
    test('defaults placements to swipe-only', () {
      final p = PageScreen(build: ({required isActive}) => const SizedBox());
      expect(p.placements, ['swipe']);
    });

    test('accepts custom placements', () {
      final p = PageScreen(
        build: ({required isActive}) => const SizedBox(),
        placements: const ['menu1'],
      );
      expect(p.placements, ['menu1']);
    });
  });
}
