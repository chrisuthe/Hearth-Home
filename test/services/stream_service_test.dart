import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/stream_service.dart';

void main() {
  group('StreamState', () {
    test('starts in idle phase with null fields', () {
      const s = StreamState();
      expect(s.phase, StreamPhase.idle);
      expect(s.filename, isNull);
      expect(s.startedAt, isNull);
      expect(s.targetHost, isNull);
      expect(s.targetPort, isNull);
      expect(s.errorMessage, isNull);
    });

    test('copyWith replaces only the provided fields', () {
      const s = StreamState(phase: StreamPhase.active, targetHost: 'a');
      final next = s.copyWith(phase: StreamPhase.stopping);
      expect(next.phase, StreamPhase.stopping);
      expect(next.targetHost, 'a');
    });

    test('equality is structural', () {
      const a = StreamState(phase: StreamPhase.active, targetPort: 1234);
      const b = StreamState(phase: StreamPhase.active, targetPort: 1234);
      const c = StreamState(phase: StreamPhase.error, targetPort: 1234);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
