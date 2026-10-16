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
import 'package:hearth/plugins/lists/lists_plugin.dart';
import 'package:hearth/plugins/lists/todo_lists.dart';
import 'package:hearth/plugins/plugin_registry.dart';
import 'package:hearth/services/home_assistant_service.dart';

const _groceries = TodoListConfig(
  entityId: 'todo.groceries',
  name: 'Groceries',
  color: 0xFF646CFF,
);

const _alex = TodoListConfig(
  entityId: 'todo.alex',
  name: 'Alex chores',
  color: 0xFFE57373,
  personId: 'person:alex',
);

const _alexP = Person(id: 'person:alex', name: 'Alex');
const _samP = Person(id: 'person:sam', name: 'Sam');

const _haConfig = HubConfig(
  haUrl: 'http://ha',
  haToken: 't',
  people: [_alexP, _samP],
);

String _html(HubConfig config) => ListsPlugin().buildSettingsHtml(
  WebContext(
    config: config,
    apiBearerToken: 'test',
    pluginActionPrefix: '/api/plugin/hearth.lists',
  ),
);

HaEntity _todo(String id, String name, String state, int features) => HaEntity(
  entityId: id,
  state: state,
  attributes: {'friendly_name': name, 'supported_features': features},
  lastChanged: DateTime(2026),
);

void main() {
  group('ListsPlugin', () {
    test('identity and registration', () {
      final p = ListsPlugin();
      expect(p.id, 'hearth.lists');
      expect(p.name, 'Lists');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
      expect(p.isVisible(const HubConfig()), isTrue);
      expect(firstPartyPlugins.whereType<ListsPlugin>(), hasLength(1));
    });

    test('statusFor needs a list', () {
      final p = ListsPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.needsSetup);
      expect(
        p.statusFor(const HubConfig(todoLists: [_groceries])),
        PluginConfigStatus.configured,
      );
    });
  });

  group('todo_lists rules', () {
    test('validateTodoEntityId takes todo.* only', () {
      expect(validateTodoEntityId('todo.groceries'), isNull);
      expect(validateTodoEntityId('calendar.family'), isNotNull);
      expect(validateTodoEntityId('todo.'), isNotNull);
    });

    test('todoListStatus reads the cached entity', () {
      final ha = _FakeHa({
        'todo.groceries': _todo('todo.groceries', 'G', '2', 0),
        'todo.done': _todo('todo.done', 'D', '0', 0),
        'todo.off': _todo('todo.off', 'O', 'unavailable', 0),
      });
      expect(todoListStatus(const HubConfig(), ha, 'todo.groceries'), (
        label: 'Home Assistant is not configured',
        bad: true,
      ));
      expect(
        todoListStatus(
          _haConfig,
          _FakeHa({}, connected: false),
          'todo.groceries',
        ),
        (label: "Can't reach Home Assistant", bad: true),
      );
      expect(todoListStatus(_haConfig, ha, 'todo.groceries'), (
        label: '2 open',
        bad: false,
      ));
      expect(todoListStatus(_haConfig, ha, 'todo.done'), (
        label: 'All done',
        bad: false,
      ));
      expect(todoListStatus(_haConfig, ha, 'todo.off'), (
        label: 'Unavailable',
        bad: true,
      ));
      expect(todoListStatus(_haConfig, ha, 'todo.gone'), (
        label: 'Not found in Home Assistant',
        bad: true,
      ));
    });

    test('todoFeaturesLabel names what the list supports', () {
      expect(todoFeaturesLabel(const TodoFeatures(0)), '');
      expect(
        todoFeaturesLabel(const TodoFeatures(1 | 2 | 4 | 8 | 16)),
        'add · edit · reorder · due dates',
      );
      expect(todoFeaturesLabel(const TodoFeatures(32)), 'due dates');
    });

    test('todoListKindLabel is the person or "List"', () {
      expect(todoListKindLabel(_groceries, const [_alexP]), 'List');
      expect(todoListKindLabel(_alex, const [_alexP]), 'Alex');
      expect(todoListKindLabel(_alex, const []), 'List');
    });
  });

  group('buildSettingsHtml', () {
    test('renders the list panel and the glance toggle', () {
      final html = _html(const HubConfig(todoChoreGlance: true));
      expect(html, contains('data-config-path="todoLists"'));
      expect(html, contains('id="lists-panel"'));
      expect(html, contains('+ Add list'));
      expect(html, contains('id="lst-add-person"'));
      expect(html, contains('id="lst-edit-person"'));
      expect(
        RegExp(
          r'<input[^>]*data-config-path="todoChoreGlance"[^>]*checked',
        ).hasMatch(html),
        isTrue,
      );
    });

    test('the add form reuses the entity picker, filtered to todo and '
        'not auto-saved', () {
      final html = _html(const HubConfig());
      expect(html, contains('/api/plugin/hearth.ha/entities?domains=todo'));
      final input = RegExp(
        r'<input[^>]*id="haep-lists-entity-input"[^>]*>',
      ).firstMatch(html)!.group(0)!;
      expect(input, contains('data-no-auto-save'));
      expect(input, isNot(contains('data-config-path')));
    });

    test('the script reaches each route', () {
      final html = _html(const HubConfig());
      expect(html, contains("call('GET', 'lists')"));
      expect(html, contains("call('POST', 'lists'"));
      expect(html, contains("call('PUT', 'lists/'"));
      expect(html, contains("call('DELETE', 'lists/'"));
    });
  });

  group('device panel', () {
    late _MemoryHubConfigNotifier notifier;

    Future<void> pumpPanel(
      WidgetTester tester,
      HubConfig config, {
      Map<String, HaEntity> entities = const {},
    }) async {
      notifier = _MemoryHubConfigNotifier(config);
      await tester.binding.setSurfaceSize(const Size(1184, 864));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((_) => notifier),
            homeAssistantServiceProvider.overrideWithValue(_FakeHa(entities)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, _) => SingleChildScrollView(
                  child: ListsPlugin().buildSettingsWidget(ref),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final haEntities = {
      'todo.groceries': _todo('todo.groceries', 'Groceries', '3', 1 | 4 | 8),
      'todo.alex': _todo('todo.alex', 'Alex', '0', 1 | 4 | 16),
      'todo.sam': _todo('todo.sam', 'Sam list', '1', 1),
      'light.kitchen': _todo('light.kitchen', 'Kitchen', 'on', 0),
    };

    testWidgets('lists each with person, status and features', (tester) async {
      await pumpPanel(
        tester,
        _haConfig.copyWith(todoLists: [_groceries, _alex]),
        entities: haEntities,
      );
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('List · 3 open'), findsOneWidget);
      expect(find.text('add · edit · reorder'), findsOneWidget);
      expect(find.text('Alex chores'), findsOneWidget);
      expect(find.text('Alex · All done'), findsOneWidget);
      expect(find.text('add · edit · due dates'), findsOneWidget);
    });

    testWidgets('adds a todo entity, named from HA, person blank', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _haConfig.copyWith(todoLists: [_groceries]),
        entities: haEntities,
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-entity')));
      await tester.pumpAndSettle();
      // Already added, or not a to-do list.
      expect(find.textContaining('todo.groceries'), findsNothing);
      expect(find.textContaining('light.kitchen'), findsNothing);
      await tester.tap(find.text('Sam list (todo.sam)').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Sam list'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        notifier.state.todoLists.last,
        TodoListConfig(
          entityId: 'todo.sam',
          name: 'Sam list',
          color: calendarPalette[1],
        ),
      );
    });

    testWidgets('adds a chore list with a person', (tester) async {
      await pumpPanel(tester, _haConfig, entities: haEntities);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-entity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam list (todo.sam)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-person')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Sam's chores").last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(notifier.state.todoLists.single.personId, 'person:sam');
      expect(notifier.state.todoLists.single.isChore, isTrue);
    });

    testWidgets('edits name, colour and person', (tester) async {
      await pumpPanel(
        tester,
        _haConfig.copyWith(todoLists: [_alex]),
        entities: haEntities,
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('todo.alex'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('list-name')), 'Jobs');
      await tester.tap(find.byKey(const ValueKey('list-person')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No one (a plain list)').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('swatch-${calendarColorHex(calendarPalette[3])}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        notifier.state.todoLists.single,
        TodoListConfig(
          entityId: 'todo.alex',
          name: 'Jobs',
          color: calendarPalette[3],
        ),
      );
    });

    testWidgets('deletes a list', (tester) async {
      await pumpPanel(
        tester,
        _haConfig.copyWith(todoLists: [_groceries, _alex]),
        entities: haEntities,
      );
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(notifier.state.todoLists, [_alex]);
    });

    testWidgets('the chore glance toggle is off by default', (tester) async {
      await pumpPanel(tester, _haConfig);
      final toggle = find.widgetWithText(
        SwitchListTile,
        "Show today's chores when idle",
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(notifier.state.todoChoreGlance, isTrue);
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
  _MemoryHubConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
