import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/people.dart';

const _sam = Person(
  id: 'person:0011223344556677',
  name: 'sam',
  color: 0xFFE57373,
  haPersonEntityId: 'person.sam',
);

HaEntity _person(String state, {String? picture}) => HaEntity(
      entityId: 'person.sam',
      state: state,
      attributes: {'friendly_name': 'Sam', 'entity_picture': ?picture},
      lastChanged: DateTime(2026),
    );

void main() {
  group('personPresence', () {
    test('home, away, a zone, or nothing', () {
      expect(personPresence('home'), 'Home');
      expect(personPresence('not_home'), 'Away');
      expect(personPresence('Work'), 'Work');
      expect(personPresence('unknown'), isNull);
      expect(personPresence('unavailable'), isNull);
    });
  });

  group('personAvatarUrl', () {
    test('an uploaded picture resolves against the HA URL', () {
      expect(
          personAvatarUrl(
              _person('home', picture: '/api/image/serve/abc/512x512'),
              'https://ha.example.com:8123/'),
          'https://ha.example.com:8123/api/image/serve/abc/512x512');
    });

    test('an absolute URL is kept; none is null', () {
      expect(
          personAvatarUrl(_person('home', picture: 'https://cdn.example/s.png'),
              'http://ha'),
          'https://cdn.example/s.png');
      expect(personAvatarUrl(_person('home'), 'http://ha'), isNull);
      expect(personAvatarUrl(_person('home', picture: ''), 'http://ha'), isNull);
      expect(personAvatarUrl(_person('home', picture: '/api/x'), ''), isNull);
    });
  });

  group('resolvePerson', () {
    test('a linked person gets avatar and presence', () {
      final view = resolvePerson(
          _sam,
          'http://ha',
          _FakeHa({'person.sam': _person('home', picture: '/p.png')}));
      expect(view.name, 'sam', reason: 'the local name always shows');
      expect(view.initial, 'S');
      expect(view.avatarUrl, 'http://ha/p.png');
      expect(view.presence, 'Home');
      expect(view.isHome, isTrue);
    });

    test('unlinked, disconnected or unknown to HA: nothing extra', () {
      final ha = _FakeHa({'person.sam': _person('home', picture: '/p.png')});
      for (final view in [
        resolvePerson(_sam.copyWith(haPersonEntityId: ''), 'http://ha', ha),
        resolvePerson(_sam, 'http://ha', ha..connected = false),
        resolvePerson(_sam, 'http://ha', _FakeHa({})),
      ]) {
        expect(view.avatarUrl, isNull);
        expect(view.presence, isNull);
      }
    });
  });

  test('personViewProvider follows the entity live', () async {
    final ha = _FakeHa({'person.sam': _person('home')});
    final c = ProviderContainer(overrides: [
      hubConfigProvider.overrideWith(
          (ref) => _Notifier(const HubConfig(haUrl: 'http://ha', people: [_sam]))),
      homeAssistantServiceProvider.overrideWithValue(ha),
    ]);
    addTearDown(c.dispose);
    final seen = <String?>[];
    c.listen(personViewProvider(_sam.id), (_, v) => seen.add(v?.presence),
        fireImmediately: true);

    // Lets the stream deliver, then Riverpod rebuild the dependents.
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await settle();
    ha.push(_person('not_home'));
    await settle();
    ha.push(_person('Work'));
    await settle();
    ha.connected = false;
    ha.disconnect();
    await settle();
    expect(seen, ['Home', 'Away', 'Work', null]);
    expect(c.read(personViewProvider('person:nobody')), isNull);
  });

  test('importablePeople skips linked entities and other domains', () {
    final ha = _FakeHa({
      'person.sam': _person('home'),
      'person.alex': HaEntity(
          entityId: 'person.alex',
          state: 'home',
          attributes: const {'friendly_name': 'Alex'},
          lastChanged: DateTime(2026)),
      'todo.x': HaEntity(
          entityId: 'todo.x', state: '0', lastChanged: DateTime(2026)),
    });
    final added = importablePeople(const [_sam], ha, (used) => used.length);
    expect(added.single.name, 'Alex');
    expect(added.single.haPersonEntityId, 'person.alex');
    expect(added.single.color, 1);
  });
}

class _FakeHa extends HomeAssistantService {
  _FakeHa(Map<String, HaEntity> initial) : _fixed = {...initial};
  final Map<String, HaEntity> _fixed;
  bool connected = true;
  final _pushes = StreamController<HaEntity>.broadcast();
  final _drops = StreamController<void>.broadcast();

  void push(HaEntity e) {
    _fixed[e.entityId] = e;
    _pushes.add(e);
  }

  void disconnect() => _drops.add(null);

  @override
  Map<String, HaEntity> get entities => _fixed;

  @override
  bool get isConnected => connected;

  @override
  Stream<HaEntity> get entityStream => _pushes.stream;

  @override
  Stream<void> get onDisconnected => _drops.stream;
}

class _Notifier extends HubConfigNotifier {
  _Notifier(HubConfig initial) {
    state = initial;
  }
}
