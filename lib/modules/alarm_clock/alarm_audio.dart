import 'dart:async';
import 'dart:io';
import '../../utils/logger.dart';

/// Plays bundled alarm tones via GStreamer on Linux, or logs on other platforms.
class AlarmAudioPlayer {
  Process? _process;
  bool _looping = false;

  /// Available builtin tone IDs. Each must have a corresponding OGG file
  /// in `assets/alarm_tones/<id>.ogg`. Adding a new tone = drop the OGG +
  /// add a row here + bump the assets list in pubspec.yaml.
  static const builtinTones = {
    'gentle_morning': 'Gentle Morning',
    'birds': 'Birdsong',
    'classic': 'Classic',
    'bright': 'Bright Day',
  };

  /// Start playing a looping alarm tone.
  Future<void> play(String toneId, {double volume = 0.7}) async {
    stop();
    _looping = true;
    // On Linux, use gst-launch-1.0 for OGG playback.
    // The tone files are bundled in the flutter assets directory.
    if (Platform.isLinux) {
      _playLoop(toneId, volume);
    } else {
      Log.i('AlarmAudio', 'Would play tone: $toneId at volume $volume');
    }
  }

  Future<void> _playLoop(String toneId, double volume) async {
    while (_looping) {
      try {
        // Use gst-launch-1.0 for OGG playback with volume control.
        // flutter-pi bundles assets directly under /opt/hearth/bundle/assets/
        // (no `flutter_assets/` prefix that vanilla Flutter desktop uses).
        _process = await Process.start('gst-launch-1.0', [
          'filesrc',
          'location=/opt/hearth/bundle/assets/alarm_tones/$toneId.ogg',
          '!', 'oggdemux', '!', 'vorbisdec',
          '!', 'volume', 'volume=${volume.toStringAsFixed(2)}',
          '!', 'autoaudiosink',
        ]);
        await _process!.exitCode;
      } catch (e) {
        Log.e('AlarmAudio', 'Playback failed: $e');
        break;
      }
    }
  }

  /// Stop playback.
  void stop() {
    _looping = false;
    _process?.kill();
    _process = null;
  }
}
