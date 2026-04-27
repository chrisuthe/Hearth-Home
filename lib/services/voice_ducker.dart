import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'sendspin/sendspin_service.dart';
import 'voice_assistant_service.dart';

/// Lowers the volume of locally-streaming music while the voice assistant
/// is actively listening or speaking, then restores it when the satellite
/// returns to idle. Today this only ducks sendspin (the only Pi-side
/// continuous music path); media_kit isn't used on the kiosk.
///
/// The duck is local-only — it goes to the AlsaAudioSink's per-stream
/// software volume, NOT to the Sendspin server's reported volume.
/// Reporting it would also dim other rooms in a multi-room group, which
/// is the opposite of what we want — only THIS Hearth's voice exchange
/// should dim THIS Hearth's playback.
class VoiceDucker {
  final SendspinService _sendspin;
  StreamSubscription<VoiceAssistantState>? _sub;
  bool _ducked = false;

  /// Multiplier applied while voice is active. 0.20 ≈ -14 dB — music
  /// stays audible enough that the user knows it didn't stop, but quiet
  /// enough that TTS sits clearly over it without competing.
  static const double _duckFactor = 0.20;

  VoiceDucker(this._sendspin);

  void start(Stream<VoiceAssistantState> voiceStateStream) {
    _sub = voiceStateStream.listen(_onState);
  }

  void _onState(VoiceAssistantState state) {
    final shouldDuck = state.state != VoiceState.idle;
    if (shouldDuck && !_ducked) {
      Log.i('Ducker', 'Voice ${state.state.name} → ducking sendspin to '
          '${(_duckFactor * 100).round()}%');
      _sendspin.setLocalDuckFactor(_duckFactor);
      _ducked = true;
    } else if (!shouldDuck && _ducked) {
      Log.i('Ducker', 'Voice idle → restoring sendspin to 100%');
      _sendspin.setLocalDuckFactor(1.0);
      _ducked = false;
    }
  }

  void dispose() {
    _sub?.cancel();
    if (_ducked) {
      // Belt-and-suspenders: don't leave music ducked if we're being torn
      // down mid-voice-exchange.
      _sendspin.setLocalDuckFactor(1.0);
    }
  }
}

final voiceDuckerProvider = Provider<VoiceDucker>((ref) {
  final sendspin = ref.watch(sendspinServiceProvider);
  final voice = ref.watch(voiceAssistantServiceProvider);
  final ducker = VoiceDucker(sendspin);
  ducker.start(voice.stateStream);
  ref.onDispose(ducker.dispose);
  return ducker;
});
