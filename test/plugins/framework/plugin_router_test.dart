import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/plugins/framework/plugin_router.dart';

void main() {
  group('PluginRouter', () {
    test('registers GET handler under plugin namespace', () {
      final router = PluginRouter();
      router.register('hearth.test');
      router.get('foo', (req) async {});
      final route = router.resolve('GET', '/api/plugin/hearth.test/foo');
      expect(route, isNotNull);
    });

    test('returns null for unknown route', () {
      final router = PluginRouter();
      final route = router.resolve('GET', '/api/plugin/hearth.test/foo');
      expect(route, isNull);
    });

    test('namespace is scoped per plugin', () {
      final router = PluginRouter();
      router.register('hearth.a');
      router.get('foo', (req) async {});
      router.register('hearth.b');
      router.get('bar', (req) async {});
      expect(router.resolve('GET', '/api/plugin/hearth.a/foo'), isNotNull);
      expect(router.resolve('GET', '/api/plugin/hearth.b/bar'), isNotNull);
      expect(router.resolve('GET', '/api/plugin/hearth.a/bar'), isNull);
    });

    test('matches POST separately from GET on the same path', () {
      final router = PluginRouter();
      router.register('hearth.test');
      router.get('foo', (req) async {});
      expect(router.resolve('GET', '/api/plugin/hearth.test/foo'), isNotNull);
      expect(router.resolve('POST', '/api/plugin/hearth.test/foo'), isNull);
    });
  });
}
