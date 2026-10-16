import 'dart:math';

/// One member of the household. Persisted in HubConfig.people; calendar
/// sources and chore lists point at one by [id].
class Person {
  /// `person:<16 hex>`; see [newPersonId].
  final String id;

  /// Always what Hearth shows. Linking to HA only pre-fills it.
  final String name;

  /// ARGB.
  final int color;

  /// The linked `person.*` entity, which supplies the avatar and presence;
  /// '' when not linked.
  final String haPersonEntityId;

  const Person({
    required this.id,
    this.name = '',
    this.color = defaultColor,
    this.haPersonEntityId = '',
  });

  static const defaultColor = 0xFF646CFF; // the accent indigo

  bool get isLinked => haPersonEntityId.isNotEmpty;

  Person copyWith({String? name, int? color, String? haPersonEntityId}) =>
      Person(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        haPersonEntityId: haPersonEntityId ?? this.haPersonEntityId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'haPersonEntityId': haPersonEntityId,
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: json['color'] as int? ?? defaultColor,
        haPersonEntityId: json['haPersonEntityId'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is Person &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.haPersonEntityId == haPersonEntityId;

  @override
  int get hashCode => Object.hash(id, name, color, haPersonEntityId);

  @override
  String toString() => 'Person($id, $name)';
}

String newPersonId() {
  final random = Random.secure();
  final hex = List.generate(
      8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return 'person:$hex';
}

/// The person with [id] in [people], or null.
Person? personById(List<Person> people, String id) {
  if (id.isEmpty) return null;
  for (final p in people) {
    if (p.id == id) return p;
  }
  return null;
}
