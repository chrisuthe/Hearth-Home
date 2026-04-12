import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/toast_service.dart';

void main() {
  late ToastNotifier notifier;

  setUp(() {
    notifier = ToastNotifier();
  });

  tearDown(() {
    notifier.dispose();
  });

  test('show() sets state to the toast message', () {
    notifier.show('Hello');
    expect(notifier.state, isNotNull);
    expect(notifier.state!.message, 'Hello');
    expect(notifier.state!.type, ToastType.info);
  });

  test('show() accepts optional parameters', () {
    notifier.show(
      'Success!',
      icon: Icons.check,
      duration: const Duration(seconds: 5),
      type: ToastType.success,
    );
    expect(notifier.state!.message, 'Success!');
    expect(notifier.state!.icon, Icons.check);
    expect(notifier.state!.duration, const Duration(seconds: 5));
    expect(notifier.state!.type, ToastType.success);
  });

  test('auto-dismisses after duration', () async {
    notifier.show('Brief', duration: const Duration(milliseconds: 50));
    expect(notifier.state, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.state, isNull);
  });

  test('queues second toast and shows it after first dismisses', () async {
    notifier.show('First', duration: const Duration(milliseconds: 50));
    notifier.show('Second', duration: const Duration(milliseconds: 50));

    expect(notifier.state!.message, 'First');

    // Wait for the first toast to auto-dismiss.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.state, isNotNull);
    expect(notifier.state!.message, 'Second');

    // Wait for the second toast to auto-dismiss.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.state, isNull);
  });

  test('dismiss() clears current and shows next in queue', () {
    notifier.show('First', duration: const Duration(seconds: 10));
    notifier.show('Second', duration: const Duration(seconds: 10));

    expect(notifier.state!.message, 'First');
    notifier.dismiss();
    expect(notifier.state!.message, 'Second');
  });

  test('dismiss() with empty queue sets state to null', () {
    notifier.show('Only', duration: const Duration(seconds: 10));
    notifier.dismiss();
    expect(notifier.state, isNull);
  });

  test('created timestamp is set', () {
    final before = DateTime.now();
    notifier.show('Timestamped');
    final after = DateTime.now();
    expect(notifier.state!.created.isAfter(before.subtract(const Duration(milliseconds: 1))), isTrue);
    expect(notifier.state!.created.isBefore(after.add(const Duration(milliseconds: 1))), isTrue);
  });
}
