import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/people/people_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/widgets/person_avatar.dart';

const _sam = Person(
  id: 'person:0011223344556677',
  name: 'Sam',
  haPersonEntityId: 'person.sam',
);
const _alex = Person(id: 'person:8899aabbccddeeff', name: 'Alex');

const _haConfig = HubConfig(haUrl: 'http://ha', haToken: 't');

String _html(HubConfig config) => PeoplePlugin().buildSettingsHtml(
      WebContext(
        config: config,
        apiBearerToken: 'test',
        pluginActionPrefix: '/api/plugin/hearth.people',
      ),
    );

HaEntity _person(String id, String name, String state) => HaEntity(
      entityId: id,
      state: state,
      attributes: {'friendly_name': name},
      lastChanged: DateTime(2026),
    );

void main() {
  group('registration', () {
    test('a first-party feature plugin, ordered before Calendar', () {
      final plugins = sortPlugins(firstPartyPlugins);
      final ids = [for (final p in plugins) p.id];
      expect(ids, contains('hearth.people'));
      expect(ids.indexOf('hearth.people'), lessThan(ids.indexOf('hearth.calendar')));
      final plugin = plugins.firstWhere((p) => p.id == 'hearth.people');
      expect(plugin.category, PluginCategory.feature);
      expect(plugin.isCommunity, isFalse);
    });

    test('configured once anyone is in the registry', () {
      final plugin = PeoplePlugin();
      expect(plugin.statusFor(const HubConfig()),
          PluginConfigStatus.needsSetup);
      expect(plugin.statusFor(const HubConfig(people: [_alex])),
          PluginConfigStatus.configured);
    });
  });

  group('buildSettingsHtml', () {
    test('renders the registry, import, and a person-only picker', () {
      final html = _html(const HubConfig());
      expect(html, contains('data-config-path="people"'));
      expect(html, contains('id="people-panel"'));
      expect(html, contains('Import from Home Assistant'));
      expect(html, contains('/api/plugin/hearth.ha/entities?domains=person'));
      final input = RegExp(r'<input[^>]*id="haep-people-entity-input"[^>]*>')
          .firstMatch(html)!
          .group(0)!;
      expect(input, contains('data-no-auto-save'));
    });

    test('the script reaches each route', () {
      final html = _html(const HubConfig());
      expect(html, contains("call('GET', 'people')"));
      expect(html, contains("call('POST', 'people'"));
      expect(html, contains("call('PUT', 'people/'"));
      expect(html, contains("call('DELETE', 'people/'"));
      expect(html, contains("call('POST', 'import')"));
    });
  });

  group('device panel', () {
    late _MemoryHubConfigNotifier notifier;

    Future<void> pumpPanel(
      WidgetTester tester,
      HubConfig config, {
      Map<String, HaEntity> entities = const {},
      bool connected = true,
    }) async {
      notifier = _MemoryHubConfigNotifier(config);
      await tester.binding.setSurfaceSize(const Size(1184, 864));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((_) => notifier),
            homeAssistantServiceProvider
                .overrideWithValue(_FakeHa(entities, connected: connected)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, _) => SingleChildScrollView(
                  child: PeoplePlugin().buildSettingsWidget(ref),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final haPeople = {
      'person.sam': _person('person.sam', 'Sam Smith', 'home'),
      'person.alex': _person('person.alex', 'Alex Jones', 'not_home'),
      'todo.groceries': _person('todo.groceries', 'Groceries', '1'),
    };

    testWidgets('lists people with avatar, link and presence', (tester) async {
      await pumpPanel(tester, _haConfig.copyWith(people: [_sam, _alex]),
          entities: haPeople);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('person.sam · Home'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Not linked to Home Assistant'), findsOneWidget);
      expect(find.byType(PersonAvatar), findsNWidgets(2));
      expect(find.byKey(const ValueKey('presence-dot')), findsOneWidget);
    });

    testWidgets('adds a person linked to HA, the name pre-filled',
        (tester) async {
      await pumpPanel(tester, _haConfig.copyWith(people: [_sam]),
          entities: haPeople);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('person-entity')));
      await tester.pumpAndSettle();
      // Sam is linked already; a todo entity is no person.
      expect(find.textContaining('(person.sam)'), findsNothing);
      expect(find.textContaining('todo.groceries'), findsNothing);
      await tester.tap(find.text('Alex Jones (person.alex)').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Alex Jones'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('person-name')), 'Alex');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      final added = notifier.state.people.last;
      expect(added.name, 'Alex', reason: 'the local name wins');
      expect(added.haPersonEntityId, 'person.alex');
      expect(added.color, calendarPalette[1]);
    });

    testWidgets('edits name, colour and unlinks', (tester) async {
      await pumpPanel(tester, _haConfig.copyWith(people: [_sam]),
          entities: haPeople);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('person-name')), 'Sammy');
      await tester.tap(find.byKey(const ValueKey('person-entity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not linked').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          ValueKey('swatch-${calendarColorHex(calendarPalette[4])}')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(notifier.state.people.single,
          Person(id: _sam.id, name: 'Sammy', color: calendarPalette[4]));
    });

    testWidgets('deleting clears their chore lists', (tester) async {
      await pumpPanel(
        tester,
        _haConfig.copyWith(people: const [
          _sam,
          _alex,
        ], todoLists: [
          TodoListConfig(entityId: 'todo.sam', personId: _sam.id),
        ]),
        entities: haPeople,
      );
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(notifier.state.people, [_alex]);
      expect(notifier.state.todoLists.single.personId, '');
    });

    testWidgets('import adds each unlinked HA person once', (tester) async {
      await pumpPanel(tester, _haConfig.copyWith(people: [_sam]),
          entities: haPeople);
      await tester.tap(find.byKey(const ValueKey('people-import')));
      await tester.pumpAndSettle();
      expect(notifier.state.people.map((p) => p.haPersonEntityId),
          ['person.sam', 'person.alex']);
      expect(notifier.state.people.last.name, 'Alex Jones');
      expect(find.text('Added 1 person.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('people-import')));
      await tester.pumpAndSettle();
      expect(notifier.state.people, hasLength(2));
      expect(find.text('Everyone in Home Assistant is already here.'),
          findsOneWidget);
    });

    testWidgets('import while HA is down changes nothing', (tester) async {
      await pumpPanel(tester, _haConfig, entities: haPeople, connected: false);
      await tester.tap(find.byKey(const ValueKey('people-import')));
      await tester.pumpAndSettle();
      expect(notifier.state.people, isEmpty);
      expect(find.text("Can't reach Home Assistant"), findsOneWidget);
    });
  });
}

class _FakeHa extends HomeAssistantService {
  _FakeHa(this._fixed, {this.connected = true});
  final Map<String, HaEntity> _fixed;
  final bool connected;

  @override
  Map<String, HaEntity> get entities => _fixed;

  @override
  bool get isConnected => connected;
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  _MemoryHubConfigNotifier(HubConfig initial) {
    state = initial;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
