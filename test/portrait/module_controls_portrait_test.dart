import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/services/home_assistant_service.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

HaEntity _entity(String id, String state, Map<String, dynamic> attrs) =>
    HaEntity(
      entityId: id,
      state: state,
      attributes: attrs,
      lastChanged: DateTime(2026, 10, 13),
    );

final _entities = <HaEntity>[
  for (var i = 0; i < 8; i++)
    _entity('light.room_$i', i.isEven ? 'on' : 'off', {
      'friendly_name': i == 1 ? kLongName : 'Room $i lights',
      if (i.isEven) 'brightness': 40 + i * 25,
    }),
  for (var i = 0; i < 3; i++)
    _entity('climate.zone_$i', const ['heat', 'cool', 'off'][i], {
      'friendly_name': i == 0 ? '$kLongName thermostat' : 'Zone $i thermostat',
      'temperature': 68 + i,
      'current_temperature': 70.4 + i,
      'hvac_mode': const ['heat', 'cool', 'off'][i],
    }),
  for (var i = 0; i < 6; i++)
    _entity('switch.outlet_$i', i.isOdd ? 'on' : 'off', {
      'friendly_name': i == 2 ? kLongName : 'Outlet $i',
    }),
  for (var i = 0; i < 5; i++)
    _entity(
        '${const ['fan', 'cover', 'lock', 'input_boolean', 'media_player'][i]}'
        '.thing_$i',
        i.isEven ? 'on' : 'off',
        {'friendly_name': i == 3 ? kLongName : 'Thing $i'}),
];

void main() {
  final screen = staticModule('controls').buildScreen(isActive: true);

  testLayouts('controls with Home Assistant disconnected',
      (tester, canvas) async {
    await pumpModule(tester, screen,
        config: const HubConfig(haUrl: ''),
        overrides: [
          homeAssistantServiceProvider
              .overrideWith((ref) => HomeAssistantService()),
          haEntitiesProvider.overrideWith((ref) => const Stream.empty()),
        ]);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testLayouts('controls with nothing pinned', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: [
      homeAssistantServiceProvider.overrideWith((ref) => FakeHomeAssistant()),
      haEntitiesProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    expect(find.text('No devices pinned'), findsOneWidget);
  });

  testLayouts('controls with 22 entities across domains',
      (tester, canvas) async {
    await pumpModule(
      tester,
      screen,
      config: HubConfig(
        haUrl: 'http://ha.local:8123',
        pinnedEntityIds: [for (final e in _entities) e.entityId],
      ),
      overrides: [
        homeAssistantServiceProvider
            .overrideWith((ref) => FakeHomeAssistant(_entities)),
        haEntitiesProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    expect(find.text('Lights'), findsOneWidget);

    // Walk the whole list so every card type lays out at this width.
    await tester.scrollUntilVisible(find.text('Climate'), 300);
    expectNoLayoutErrors(tester, 'climate cards');
    await tester.scrollUntilVisible(find.text('Switches'), 300);
    await tester.scrollUntilVisible(find.text('Other'), 300);
    await tester.scrollUntilVisible(find.text('Thing 4'), 300);
  });
}
