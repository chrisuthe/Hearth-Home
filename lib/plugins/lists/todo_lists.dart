import '../../config/hub_config.dart';
import '../../config/person.dart';
import '../../modules/lists/models.dart';
import '../../services/home_assistant_service.dart';

/// Rules shared by the Lists plugin's device panel and its portal routes, so
/// both surfaces add, edit and describe lists the same way. Colours come from
/// Calendar's palette (`calendar_sources.dart`).

/// Null when [entityId] is a `todo.*` entity id; otherwise why not.
String? validateTodoEntityId(String entityId) =>
    RegExp(r'^todo\.[a-z0-9_]+$').hasMatch(entityId)
    ? null
    : 'Pick a todo.* entity';

/// "Alex" for a chore list, "List" for a plain one.
String todoListKindLabel(TodoListConfig list, List<Person> people) =>
    personById(people, list.personId)?.name ?? 'List';

/// Null when [personId] is '' or someone in [people]; otherwise why not.
String? validateListPersonId(String personId, List<Person> people) =>
    personId.isEmpty || personById(people, personId) != null
    ? null
    : 'no person $personId';

/// One line for a list's live state, read from the entity HA caches: a
/// `todo.*` entity's state is its count of open items.
({String label, bool bad}) todoListStatus(
  HubConfig config,
  HomeAssistantService ha,
  String entityId,
) {
  if (config.haUrl.isEmpty || config.haToken.isEmpty) {
    return (label: 'Home Assistant is not configured', bad: true);
  }
  if (!ha.isConnected) return (label: "Can't reach Home Assistant", bad: true);
  final entity = ha.entities[entityId];
  if (entity == null) return (label: 'Not found in Home Assistant', bad: true);
  final open = int.tryParse(entity.state);
  if (open == null) return (label: 'Unavailable', bad: true);
  return (label: open == 0 ? 'All done' : '$open open', bad: false);
}

/// What a list supports, as "add · edit · reorder · due dates"; empty when
/// it supports none of them (or the entity is not cached yet).
String todoFeaturesLabel(TodoFeatures f) => [
  if (f.canAdd) 'add',
  if (f.canUpdate) 'edit',
  if (f.canMove) 'reorder',
  if (f.canSetDueDate || f.canSetDueTime) 'due dates',
].join(' · ');
