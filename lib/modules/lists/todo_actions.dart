import '../../services/home_assistant_service.dart';
import 'models.dart';

/// Writes to HA to-do lists. Each returns null on success, or the message to
/// show. Nothing changes locally: the subscription's next push is the truth.
///
/// Items are always addressed by uid, and a field is sent only when the
/// list supports it; HA rejects an unsupported field even as null.
class TodoActions {
  final HomeAssistantService _ha;
  final TodoFeatures Function(String entityId) _features;

  TodoActions(this._ha, this._features);

  Future<String?> add(String entityId, String summary,
      {TodoDue? due, String? description}) {
    final features = _features(entityId);
    return _call(entityId, 'add_item', {
      'item': summary,
      if (due != null) ..._due(features, due),
      if (description != null && features.canSetDescription)
        'description': description,
    });
  }

  /// Sends what differs between [from] and [to], and nothing when nothing
  /// does.
  Future<String?> update(String entityId, TodoItem from, TodoItem to) async {
    final uid = from.uid;
    if (uid == null) return _noUid;
    final features = _features(entityId);
    final data = <String, dynamic>{
      if (to.summary != from.summary) 'rename': to.summary,
      if (to.status != from.status)
        'status': to.status == TodoStatus.completed ? 'completed' : 'needs_action',
      if (to.description != from.description && features.canSetDescription)
        'description': to.description,
      if (to.due != from.due) ..._due(features, to.due),
    };
    if (data.isEmpty) return null;
    return _call(entityId, 'update_item', {'item': uid, ...data});
  }

  Future<String?> remove(String entityId, TodoItem item) async {
    final uid = item.uid;
    if (uid == null) return _noUid;
    return _call(entityId, 'remove_item', {'item': uid});
  }

  Future<String?> clearCompleted(String entityId) =>
      _call(entityId, 'remove_completed_items', {});

  /// Moves [uid] to just after [previousUid], or to the top when null.
  Future<String?> move(String entityId, String uid, {String? previousUid}) =>
      _send({
        'type': 'todo/item/move',
        'entity_id': entityId,
        'uid': uid,
        'previous_uid': ?previousUid,
      });

  static const _noUid = "Home Assistant gave this item no id, so it can't be changed";

  /// The due field the list supports for [due]; a clear (null) uses
  /// `due_date` when the list has it, else `due_datetime`.
  static Map<String, dynamic> _due(TodoFeatures features, TodoDue? due) {
    if (due == null) {
      if (features.canSetDueDate) return {'due_date': null};
      if (features.canSetDueTime) return {'due_datetime': null};
      return const {};
    }
    if (due.hasTime) {
      // UTC with `Z`: the instant the user picked; HA converts it to its zone.
      return features.canSetDueTime
          ? {'due_datetime': due.value.toIso8601String()}
          : const {};
    }
    final d = due.value;
    return features.canSetDueDate
        ? {
            'due_date': '${d.year.toString().padLeft(4, '0')}-'
                '${d.month.toString().padLeft(2, '0')}-'
                '${d.day.toString().padLeft(2, '0')}'
          }
        : const {};
  }

  Future<String?> _call(
          String entityId, String service, Map<String, dynamic> data) =>
      _send({
        'type': 'call_service',
        'domain': 'todo',
        'service': service,
        'service_data': data,
        'target': {'entity_id': entityId},
      });

  Future<String?> _send(Map<String, dynamic> message) async {
    final reply = await _ha.request(message);
    if (reply.success) return null;
    // The write may still have landed; the next push shows it if it did.
    if (reply.errorCode == 'timeout') return "Couldn't confirm the change";
    return reply.errorMessage ?? reply.errorCode ?? 'Home Assistant refused the change';
  }
}
