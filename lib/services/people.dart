import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/hub_config.dart';
import '../config/person.dart';
import '../models/ha_entity.dart';
import 'home_assistant_service.dart';

/// A [Person] as Hearth shows them: the local name and colour, plus what the
/// linked `person.*` entity adds. See docs/specs/2026-10-15-people-design.md.
class PersonView {
  final Person person;

  /// Absolute; null when unlinked or the entity has no `entity_picture`.
  final String? avatarUrl;

  /// 'Home', 'Away' or a zone name; null when unlinked, HA is not connected,
  /// or HA does not know where they are.
  final String? presence;

  const PersonView(this.person, {this.avatarUrl, this.presence});

  String get name => person.name;
  int get color => person.color;
  bool get isHome => presence == 'Home';

  /// The first letter of the name, for an avatar without a picture.
  String get initial {
    final name = person.name.trim();
    return name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is PersonView &&
      other.person == person &&
      other.avatarUrl == avatarUrl &&
      other.presence == presence;

  @override
  int get hashCode => Object.hash(person, avatarUrl, presence);
}

/// The view of [person] from the entities HA has cached.
PersonView resolvePerson(
  Person person,
  String haUrl,
  HomeAssistantService ha,
) {
  final entity = person.isLinked && ha.isConnected
      ? ha.entities[person.haPersonEntityId]
      : null;
  if (entity == null) return PersonView(person);
  return PersonView(
    person,
    avatarUrl: personAvatarUrl(entity, haUrl),
    presence: personPresence(entity.state),
  );
}

/// `entity_picture` made absolute. HA stores it as given: an uploaded
/// picture's `/api/image/serve/…` path, which HA serves without auth, or
/// any URL an admin typed.
String? personAvatarUrl(HaEntity entity, String haUrl) {
  final picture = entity.attributes['entity_picture'];
  if (picture is! String || picture.isEmpty) return null;
  final base = Uri.tryParse(haUrl);
  final ref = Uri.tryParse(picture);
  if (ref == null) return null;
  if (ref.hasScheme) return picture;
  if (base == null || !base.hasScheme) return null;
  // The HA URL may be typed as its WebSocket; pictures are plain HTTP.
  final http = switch (base.scheme) {
    'ws' => base.replace(scheme: 'http'),
    'wss' => base.replace(scheme: 'https'),
    _ => base,
  };
  return http.resolveUri(ref).toString();
}

/// A person entity's state as presence. HA copies the winning tracker's
/// state: `home`, `not_home`, or a zone's friendly name; `unknown` when no
/// tracker has a state.
String? personPresence(String state) => switch (state) {
      'home' => 'Home',
      'not_home' => 'Away',
      'unknown' || 'unavailable' || '' => null,
      _ => state,
    };

/// The view of the person with [personId]; null when there is none. Follows
/// the entity's state live.
final personViewProvider =
    Provider.autoDispose.family<PersonView?, String>((ref, personId) {
  final person = ref.watch(
      hubConfigProvider.select((c) => personById(c.people, personId)));
  if (person == null) return null;
  final haUrl = ref.watch(hubConfigProvider.select((c) => c.haUrl));
  final ha = ref.watch(homeAssistantServiceProvider);
  if (person.isLinked) {
    // Recomputed on every entity push and connection change; dependents
    // rebuild only when the view itself changes.
    ref.watch(haEntitiesProvider);
    ref.watch(_haConnectionProvider);
  }
  return resolvePerson(person, haUrl, ha);
});

/// Ticks on each HA connect and disconnect.
final _haConnectionProvider = StreamProvider.autoDispose<bool>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  final controller = StreamController<bool>();
  final subs = [
    ha.onAuthenticated.listen((_) => controller.add(true)),
    ha.onDisconnected.listen((_) => controller.add(false)),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });
  return controller.stream;
});

/// The `person.*` entities HA has cached, by name.
List<HaEntity> haPersonEntities(HomeAssistantService ha) =>
    ha.entities.values.where((e) => e.domain == 'person').toList()
      ..sort((a, b) => a.name.compareTo(b.name));

/// One new [Person] for each `person.*` entity no person links to yet,
/// named after it and coloured from [nextColor].
List<Person> importablePeople(
  List<Person> existing,
  HomeAssistantService ha,
  int Function(List<int> used) nextColor,
) {
  final linked = {for (final p in existing) p.haPersonEntityId};
  final used = [for (final p in existing) p.color];
  final added = <Person>[];
  for (final e in haPersonEntities(ha)) {
    if (linked.contains(e.entityId)) continue;
    final color = nextColor(used);
    used.add(color);
    added.add(Person(
      id: newPersonId(),
      name: e.name,
      color: color,
      haPersonEntityId: e.entityId,
    ));
  }
  return added;
}

/// Null when [entityId] is a `person.*` entity id; otherwise why not.
String? validatePersonEntityId(String entityId) =>
    RegExp(r'^person\.[a-z0-9_]+$').hasMatch(entityId)
        ? null
        : 'Pick a person.* entity';
