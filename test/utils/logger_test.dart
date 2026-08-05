import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/utils/logger.dart';

void main() {
  group('redactSecrets', () {
    test('redacts X-Plex-Token without touching the rest of the URL', () {
      final out = redactSecrets(
          'http://h:32400/video/:/transcode/universal/start.m3u8'
          '?path=%2Flibrary%2Fmetadata%2F28213&X-Plex-Token=EXcyy1vKSaE4prX2'
          '&X-Plex-Product=Hearth');
      expect(out, isNot(contains('EXcyy1vKSaE4prX2')));
      expect(out, contains('X-Plex-Token=REDACTED'));
      // Everything else must survive — the URL is the diagnostic.
      expect(out, contains('path=%2Flibrary%2Fmetadata%2F28213'));
      expect(out, contains('X-Plex-Product=Hearth'));
    });

    test('redacts a token in any position, including last', () {
      expect(redactSecrets('http://h/a?b=1&token=abc123'),
          'http://h/a?b=1&token=REDACTED');
      expect(redactSecrets('http://h/a?X-Plex-Token=abc123'),
          'http://h/a?X-Plex-Token=REDACTED');
    });

    test('leaves URLs without credentials unchanged', () {
      const clean = 'http://h:32400/library/parts/29913/1553708798/file.mkv';
      expect(redactSecrets(clean), clean);
    });
  });
}
