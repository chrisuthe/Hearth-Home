import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/video/mpv_log_filter.dart';
import 'package:hearth/utils/logger.dart';

void main() {
  late MpvLogFilter filter;

  setUp(() => filter = MpvLogFilter());

  group('level mapping', () {
    test('error and fatal log at error, with the mpv prefix', () {
      final error = filter.log('ffmpeg/video', 'error', 'h264: no frame!');
      expect(error!.level, LogLevel.error);
      expect(error.message, 'mpv: [ffmpeg/video] h264: no frame!');

      expect(filter.log('cplayer', 'fatal', 'out of memory')!.level,
          LogLevel.error);
    });

    test('warn logs at warn', () {
      final line = filter.log('vd', 'warn', 'Falling back to software decoding.');
      expect(line!.level, LogLevel.warn);
      expect(line.message, 'mpv: [vd] Falling back to software decoding.');
    });

    test('anything below warn is dropped', () {
      for (final level in ['info', 'v', 'debug', 'trace', 'status', '']) {
        expect(filter.log('cplayer', level, 'VO: [gpu] 2560x1440 yuv420p'),
            isNull,
            reason: level);
      }
    });

    test('empty text is dropped', () {
      expect(filter.log('cplayer', 'error', ''), isNull);
      expect(filter.error(''), isNull);
    });

    test('a stream error logs at error', () {
      final line = filter.error('Failed to open rtsp://cam.local/stream.');
      expect(line!.level, LogLevel.error);
      expect(line.message, 'mpv: Failed to open rtsp://cam.local/stream.');
    });
  });

  group('known-benign messages', () {
    // prefix, level, text — as captured during healthy live RTSP playback.
    const healthy = [
      ('cplayer', 'error', 'Cannot seek in this stream.'),
      ('cplayer', 'error', "You can force it with '--force-seekable=yes'."),
      ('lavf', 'error', 'Failed to create file cache.'),
      (
        'ffmpeg/video',
        'error',
        'h264_mediacodec: Both surface and native_window are NULL'
      ),
      ('ffmpeg/video', 'warn', 'h264_mediacodec: Input packet is missing PTS'),
      ('playlist', 'warn', 'Reading plaintext playlist.'),
      ('ffmpeg', 'error', 'NULL: SEI type 5 size 277 truncated at 243'),
      (
        'media_kit',
        'error',
        'error: property not found _setProperty(osc, 1)'
      ),
    ];

    test('are demoted to debug from the log stream', () {
      for (final (prefix, level, text) in healthy) {
        expect(MpvLogFilter().log(prefix, level, text)!.level, LogLevel.debug,
            reason: text);
      }
    });

    test('are demoted to debug from the error stream', () {
      expect(filter.error('Cannot seek in this stream.')!.level,
          LogLevel.debug);
      expect(
          filter.error("You can force it with '--force-seekable=yes'.")!.level,
          LogLevel.debug);
    });

    test('a healthy open produces no warn or error line', () {
      final lines = [
        for (final (prefix, level, text) in healthy)
          filter.log(prefix, level, text),
        filter.error('Cannot seek in this stream.'),
        filter.error("You can force it with '--force-seekable=yes'."),
      ].nonNulls;
      expect(
          lines.where((l) =>
              l.level == LogLevel.error || l.level == LogLevel.warn),
          isEmpty);
    });

    test('a truncated SEI of any size is benign', () {
      expect(
          filter
              .log('ffmpeg', 'error', 'NULL: SEI type 5 size 1024 truncated at 96')!
              .level,
          LogLevel.debug);
    });

    test('real failures near the benign ones still log at error', () {
      for (final (prefix, text) in const [
        ('ffmpeg', 'tcp: Connection to tcp://10.0.0.9:554 failed: Connection refused'),
        ('stream', 'Failed to open rtsp://10.0.0.9:554/cam.'),
        ('vd', 'Could not open codec.'),
        ('ffmpeg/video', 'h264_mediacodec: Failed to configure codec'),
        ('lavf', 'Failed to create file.'),
        ('cplayer', 'Cannot seek backward in linear streams!'),
      ]) {
        expect(MpvLogFilter().log(prefix, 'error', text)!.level, LogLevel.error,
            reason: text);
      }
    });
  });

  group('stream.error echoes', () {
    test('an error already seen on the log stream is not logged twice', () {
      expect(filter.log('vd', 'error', 'Could not open codec.'), isNotNull);
      expect(filter.error('Could not open codec.'), isNull);
    });

    test('nor when the error stream delivers first', () {
      expect(filter.error('Could not open codec.'), isNotNull);
      expect(filter.log('vd', 'error', 'Could not open codec.'), isNull);
    });

    test('a repeat of the same failure is logged again', () {
      filter.log('vd', 'error', 'Could not open codec.');
      filter.error('Could not open codec.');
      expect(filter.log('vd', 'error', 'Could not open codec.'), isNotNull);
      expect(filter.error('Could not open codec.'), isNull);
    });

    test('an error with no log counterpart is still logged', () {
      filter.log('vd', 'error', 'Could not open codec.');
      expect(filter.error('Failed to open http://host/a.mp4.'), isNotNull);
    });

    test('a warning does not swallow a matching error', () {
      filter.log('vd', 'warn', 'Could not open codec.');
      expect(filter.error('Could not open codec.'), isNotNull);
    });
  });

  group('redaction', () {
    const url = 'http://pms:32400/video/start.m3u8?X-Plex-Token=abc123&path=/x';

    test('log lines have secret query parameters redacted', () {
      final line = filter.log('stream', 'error', 'Failed to open $url.');
      expect(line!.message, isNot(contains('abc123')));
      expect(line.message, contains('X-Plex-Token=REDACTED&path=/x'));
    });

    test('error lines have secret query parameters redacted', () {
      final line = filter.error('Failed to open http://nas/v.mp4?token=s3cret.');
      expect(line!.message, isNot(contains('s3cret')));
      expect(line.message, contains('token=REDACTED'));
    });

    test('demoted lines are redacted too', () {
      final line = filter.log('playlist', 'warn',
          'Reading plaintext playlist. http://h/p.m3u?api_key=k9');
      expect(line!.level, LogLevel.debug);
      expect(line.message, isNot(contains('k9')));
    });
  });
}
