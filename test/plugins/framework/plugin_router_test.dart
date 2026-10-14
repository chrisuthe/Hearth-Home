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

    test('registers PUT and DELETE handlers', () {
      final router = PluginRouter();
      router.register('hearth.test');
      router.put('foo', (req) async {});
      router.delete('foo', (req) async {});
      expect(router.resolve('PUT', '/api/plugin/hearth.test/foo'), isNotNull);
      expect(
          router.resolve('DELETE', '/api/plugin/hearth.test/foo'), isNotNull);
      expect(router.resolve('GET', '/api/plugin/hearth.test/foo'), isNull);
    });

    test(':name segments match one segment and are decoded', () {
      final router = PluginRouter();
      router.register('hearth.test');
      router.put('items/:id', (req) async {});
      final match =
          router.match('PUT', '/api/plugin/hearth.test/items/ha%3Acalendar.x');
      expect(match, isNotNull);
      expect(match!.params, {'id': 'ha:calendar.x'});
      expect(router.match('PUT', '/api/plugin/hearth.test/items'), isNull);
      expect(router.match('PUT', '/api/plugin/hearth.test/items/'), isNull);
      expect(router.match('PUT', '/api/plugin/hearth.test/items/a/b'), isNull);
      expect(router.match('PUT', '/api/plugin/hearth.other/items/a'), isNull);
    });

    test('an exact route wins over a :name route', () {
      final router = PluginRouter();
      router.register('hearth.test');
      Future<void> exact(req) async {}
      router.get('items/:id', (req) async {});
      router.get('items/all', exact);
      final match = router.match('GET', '/api/plugin/hearth.test/items/all');
      expect(match!.handler, same(exact));
      expect(match.params, isEmpty);
    });
  });
}
