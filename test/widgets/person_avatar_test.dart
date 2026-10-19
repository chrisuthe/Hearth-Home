import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/services/people.dart';
import 'package:hearth/widgets/person_avatar.dart';

const _ava = Person(id: 'person:ava', name: 'Ava');

Future<void> _pump(WidgetTester tester, PersonAvatar avatar) =>
    tester.pumpWidget(MaterialApp(home: Center(child: avatar)));

void main() {
  for (final (presence, icon) in [
    ('Home', Icons.home_rounded),
    ('Away', Icons.directions_walk),
    ('Work', Icons.place),
  ]) {
    testWidgets('the icon badge shows $icon for $presence', (tester) async {
      await _pump(
        tester,
        PersonAvatar(
          view: PersonView(_ava, presence: presence),
          size: 56,
          presenceIcon: true,
        ),
      );
      expect(find.byKey(const ValueKey('presence-icon')), findsOneWidget);
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.byKey(const ValueKey('presence-dot')), findsNothing);
    });
  }

  testWidgets('no badge when HA does not know where they are', (tester) async {
    await _pump(
      tester,
      const PersonAvatar(view: PersonView(_ava), size: 56, presenceIcon: true),
    );
    expect(find.byKey(const ValueKey('presence-icon')), findsNothing);
    expect(find.byKey(const ValueKey('presence-dot')), findsNothing);
  });

  testWidgets('the dot stays the default', (tester) async {
    await _pump(
      tester,
      const PersonAvatar(view: PersonView(_ava, presence: 'Home')),
    );
    expect(find.byKey(const ValueKey('presence-dot')), findsOneWidget);
    expect(find.byKey(const ValueKey('presence-icon')), findsNothing);
  });
}
