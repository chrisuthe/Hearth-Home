import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/hearth_notification.dart';
import 'package:hearth/services/notification_service.dart';

void main() {
  // A notification factory with sensible defaults for tests.
  HearthNotification make({
    String id = 'n1',
    NotificationSource source = NotificationSource.ha,
    NotificationPriority priority = NotificationPriority.info,
    bool sticky = true,
    bool muted = false,
    VoidCallback? onDismiss,
  }) {
    return HearthNotification(
      id: id,
      source: source,
      sourceLabel: defaultSourceLabel(source),
      priority: priority,
      title: 'Title $id',
      body: 'Body $id',
      sticky: sticky,
      muted: muted,
      timestamp: DateTime(2026, 1, 1, 9, 30),
      onDismiss: onDismiss,
    );
  }

  group('NotificationService', () {
    late List<HearthNotification> chimed;
    late NotificationService service;

    NotificationService build({
      bool suppressed = false,
      Duration transientLifetime = const Duration(milliseconds: 20),
    }) {
      chimed = [];
      return NotificationService(
        playChime: (n) async => chimed.add(n),
        isChimeSuppressed: () => suppressed,
        transientLifetime: transientLifetime,
      );
    }

    setUp(() => service = build());
    tearDown(() => service.dispose());

    test('starts empty', () {
      expect(service.notifications, isEmpty);
      expect(service.hasActive, false);
    });

    test('ingest adds a card', () {
      service.ingest(make());
      expect(service.notifications, hasLength(1));
      expect(service.hasActive, true);
      expect(service.notifications.first.title, 'Title n1');
    });

    test('ingest keeps oldest first, newest last', () {
      service.ingest(make(id: 'a'));
      service.ingest(make(id: 'b'));
      service.ingest(make(id: 'c'));
      expect(service.notifications.map((n) => n.id), ['a', 'b', 'c']);
    });

    test('ingest plays the chime for a normal card', () {
      service.ingest(make(priority: NotificationPriority.alert));
      expect(chimed, hasLength(1));
      expect(chimed.first.chimeLabel, 'Ember Alert');
    });

    test('ingest does not chime when the card is muted', () {
      service.ingest(make(muted: true));
      expect(chimed, isEmpty);
    });

    test('ingest does not chime when suppressed (night mode)', () {
      service = build(suppressed: true);
      service.ingest(make());
      expect(chimed, isEmpty);
    });

    test('ingest does not chime for timer-sourced cards', () {
      // TimerService owns the looping fired-timer beep.
      service.ingest(make(source: NotificationSource.timer));
      expect(chimed, isEmpty);
    });

    test('re-ingesting the same id replaces rather than stacks', () {
      service.ingest(make(id: 'x', sticky: false));
      service.ingest(make(id: 'x'));
      expect(service.notifications, hasLength(1));
      expect(service.notifications.first.sticky, true);
    });

    test('dismiss removes one card', () {
      service.ingest(make(id: 'a'));
      service.ingest(make(id: 'b'));
      service.dismiss('a');
      expect(service.notifications.map((n) => n.id), ['b']);
    });

    test('dismiss is idempotent for an unknown id', () {
      service.ingest(make(id: 'a'));
      service.dismiss('nope');
      service.dismiss('a');
      service.dismiss('a');
      expect(service.notifications, isEmpty);
    });

    test('dismiss invokes the card onDismiss callback', () {
      var called = 0;
      service.ingest(make(id: 'a', onDismiss: () => called++));
      service.dismiss('a');
      expect(called, 1);
    });

    test('clearAll empties the deck and fires each onDismiss once', () {
      var called = 0;
      service.ingest(make(id: 'a', onDismiss: () => called++));
      service.ingest(make(id: 'b', onDismiss: () => called++));
      service.clearAll();
      expect(service.notifications, isEmpty);
      expect(called, 2);
    });

    test('sticky cards persist (no auto-dismiss)', () async {
      service.ingest(make(id: 'a', sticky: true));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(service.notifications, hasLength(1));
    });

    test('transient cards auto-dismiss after their lifetime', () async {
      service.ingest(make(id: 'a', sticky: false));
      expect(service.notifications, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(service.notifications, isEmpty);
    });

    test('dismissing a transient card cancels its auto-dismiss timer', () async {
      var called = 0;
      service.ingest(make(id: 'a', sticky: false, onDismiss: () => called++));
      service.dismiss('a');
      // Wait past the lifetime — onDismiss must not fire a second time.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(called, 1);
    });
  });
}
