import '../../models/ha_entity.dart';
import '../calendar/models.dart' show CalendarSource;

/// One configured HA to-do list. Persisted in HubConfig.todoLists.
class TodoListConfig {
  /// `todo.groceries`; unique within the config.
  final String entityId;

  /// Display name; defaults to the entity's friendly_name.
  final String name;

  /// ARGB.
  final int color;

  /// '' for a plain list; a name makes it that person's chore list.
  final String person;

  const TodoListConfig({
    required this.entityId,
    this.name = '',
    this.color = CalendarSource.defaultColor,
    this.person = '',
  });

  bool get isChore => person.isNotEmpty;

  TodoListConfig copyWith({String? name, int? color, String? person}) =>
      TodoListConfig(
        entityId: entityId,
        name: name ?? this.name,
        color: color ?? this.color,
        person: person ?? this.person,
      );

  Map<String, dynamic> toJson() => {
        'entityId': entityId,
        'name': name,
        'color': color,
        'person': person,
      };

  factory TodoListConfig.fromJson(Map<String, dynamic> json) => TodoListConfig(
        entityId: json['entityId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: json['color'] as int? ?? CalendarSource.defaultColor,
        person: json['person'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is TodoListConfig &&
      other.entityId == entityId &&
      other.name == name &&
      other.color == color &&
      other.person == person;

  @override
  int get hashCode => Object.hash(entityId, name, color, person);
}

enum TodoStatus { needsAction, completed }

/// A due date, or a due instant when [hasTime].
class TodoDue {
  /// !hasTime: local midnight of the date, untouched by any zone;
  /// hasTime: a UTC instant.
  final DateTime value;
  final bool hasTime;

  const TodoDue._(this.value, this.hasTime);

  factory TodoDue.date(DateTime day) =>
      TodoDue._(DateTime(day.year, day.month, day.day), false);

  factory TodoDue.instant(DateTime at) => TodoDue._(at.toUtc(), true);

  /// HA's `due`: a string with a `T` is a datetime, as HA's frontend reads it.
  static TodoDue? tryParse(Object? raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return raw.contains('T') ? TodoDue.instant(parsed) : TodoDue.date(parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is TodoDue && other.value == value && other.hasTime == hasTime;

  @override
  int get hashCode => Object.hash(value, hasTime);

  @override
  String toString() => 'TodoDue(${hasTime ? value : '${value.year}-'
      '${value.month}-${value.day}'})';
}

/// One item of an HA to-do list, in HA's order.
class TodoItem {
  /// null: shown, but no action is offered.
  final String? uid;
  final String summary;
  final TodoStatus status;
  final TodoDue? due;
  final String? description;

  /// When it was completed; HA 2025.12+, and only some integrations.
  final DateTime? completed;

  const TodoItem({
    this.uid,
    this.summary = '',
    this.status = TodoStatus.needsAction,
    this.due,
    this.description,
    this.completed,
  });

  /// Parses either shape: the subscription's (every field, nulls included)
  /// or `get_items`' (nulls omitted, every value a string).
  factory TodoItem.fromJson(Map<String, dynamic> json) {
    final completed = json['completed'];
    return TodoItem(
      uid: json['uid'] as String?,
      summary: json['summary'] as String? ?? '',
      status: json['status'] == 'completed'
          ? TodoStatus.completed
          : TodoStatus.needsAction,
      due: TodoDue.tryParse(json['due']),
      description: json['description'] as String?,
      completed:
          completed is String ? DateTime.tryParse(completed)?.toUtc() : null,
    );
  }

  /// Items of one push; anything that is not an object is skipped.
  static List<TodoItem> parseItems(List<dynamic> raw) => [
        for (final e in raw)
          if (e is Map<String, dynamic>) TodoItem.fromJson(e),
      ];

  @override
  bool operator ==(Object other) =>
      other is TodoItem &&
      other.uid == uid &&
      other.summary == summary &&
      other.status == status &&
      other.due == due &&
      other.description == description &&
      other.completed == completed;

  @override
  int get hashCode =>
      Object.hash(uid, summary, status, due, description, completed);

  @override
  String toString() => 'TodoItem($uid, $summary, ${status.name}, $due)';
}

/// Bit flags from the entity's `supported_features` attribute
/// (`TodoListEntityFeature`).
class TodoFeatures {
  final int bits;

  const TodoFeatures(this.bits);

  /// 0 until the entity reaches the cache.
  factory TodoFeatures.of(HaEntity? entity) =>
      TodoFeatures((entity?.attributes['supported_features'] as num?)?.toInt() ?? 0);

  bool get canAdd => bits & 1 != 0;
  bool get canDelete => bits & 2 != 0;
  bool get canUpdate => bits & 4 != 0;
  bool get canMove => bits & 8 != 0;
  bool get canSetDueDate => bits & 16 != 0;
  bool get canSetDueTime => bits & 32 != 0;
  bool get canSetDescription => bits & 64 != 0;

  @override
  bool operator ==(Object other) => other is TodoFeatures && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;
}

enum ListStatus { loading, ok, stale, error }

/// What one list currently has. A lost connection keeps [items] and moves to
/// [ListStatus.stale].
class TodoListState {
  final List<TodoItem> items;
  final ListStatus status;
  final String? error;

  const TodoListState({
    this.items = const [],
    this.status = ListStatus.loading,
    this.error,
  });
}
