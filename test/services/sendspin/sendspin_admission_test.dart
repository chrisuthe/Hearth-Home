import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_admission.dart';

AdmissionCandidate _c(Set<String> activities, [String? serverId]) =>
    AdmissionCandidate(activities: activities, serverId: serverId);

void main() {
  group('decideAdmission', () {
    test('the first connection is admitted whatever it declares', () {
      for (final activities in [
        <String>{},
        {'pairing'},
        {'playback'},
      ]) {
        expect(
          decideAdmission(
              current: null,
              incoming: _c(activities, 'a'),
              lastPlaybackServerId: null),
          AdmissionDecision.admit,
        );
      }
    });

    test('equal or higher rank takes the kiosk', () {
      expect(
        decideAdmission(
            current: _c({'playback'}, 'a'),
            incoming: _c({'playback'}, 'b'),
            lastPlaybackServerId: 'a'),
        AdmissionDecision.displaceCurrent,
      );
      expect(
        decideAdmission(
            current: _c({}, 'a'),
            incoming: _c({'playback'}, 'b'),
            lastPlaybackServerId: null),
        AdmissionDecision.displaceCurrent,
      );
      expect(
        decideAdmission(
            current: _c({}, 'a'),
            incoming: _c({'pairing'}, 'b'),
            lastPlaybackServerId: null),
        AdmissionDecision.displaceCurrent,
      );
    });

    test('lower rank is refused', () {
      expect(
        decideAdmission(
            current: _c({'playback'}, 'a'),
            incoming: _c({}, 'b'),
            lastPlaybackServerId: null),
        AdmissionDecision.rejectIncoming,
      );
      expect(
        decideAdmission(
            current: _c({'playback'}, 'a'),
            incoming: _c({'pairing'}, 'b'),
            lastPlaybackServerId: null),
        AdmissionDecision.rejectIncoming,
      );
    });

    test('a pairing attempt is not displaced, even by playback', () {
      for (final incoming in [
        {'playback'},
        {'pairing'},
        {'playback', 'pairing'},
        <String>{},
      ]) {
        expect(
          decideAdmission(
              current: _c({'pairing'}, 'a'),
              incoming: _c(incoming, 'b'),
              lastPlaybackServerId: 'b'),
          AdmissionDecision.rejectIncoming,
          reason: 'incoming $incoming',
        );
      }
      expect(
        decideAdmission(
            current: _c({'playback', 'pairing'}, 'a'),
            incoming: _c({'playback'}, 'b'),
            lastPlaybackServerId: null),
        AdmissionDecision.rejectIncoming,
      );
    });

    group('two idle servers', () {
      test('the last one that played takes the kiosk back', () {
        expect(
          decideAdmission(
              current: _c({}, 'a'),
              incoming: _c({}, 'b'),
              lastPlaybackServerId: 'b'),
          AdmissionDecision.displaceCurrent,
        );
      });

      test('otherwise the existing one is kept', () {
        expect(
          decideAdmission(
              current: _c({}, 'a'),
              incoming: _c({}, 'b'),
              lastPlaybackServerId: 'a'),
          AdmissionDecision.rejectIncoming,
        );
        expect(
          decideAdmission(
              current: _c({}, 'a'),
              incoming: _c({}, 'b'),
              lastPlaybackServerId: 'c'),
          AdmissionDecision.rejectIncoming,
        );
        expect(
          decideAdmission(
              current: _c({}, 'a'),
              incoming: _c({}, 'b'),
              lastPlaybackServerId: null),
          AdmissionDecision.rejectIncoming,
        );
      });

      test('a reconnect from the last-playback server does not displace '
          'itself', () {
        expect(
          decideAdmission(
              current: _c({}, 'a'),
              incoming: _c({}, 'a'),
              lastPlaybackServerId: 'a'),
          AdmissionDecision.rejectIncoming,
        );
      });
    });
  });
}
