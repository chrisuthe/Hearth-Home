import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/video/media_kit_player.dart';

void main() {
  group('hwdecFor', () {
    test('Android decodes RTSP camera feeds in software', () {
      expect(hwdecFor('rtsp://10.0.2.3:8554/DrivewayPTZ', android: true), 'no');
      expect(hwdecFor('rtsps://192.168.1.1:7441/abc?enableSrtp', android: true),
          'no');
    });

    test('Android keeps the default for everything else', () {
      expect(hwdecFor('http://plex:32400/video/:/transcode/x.m3u8',
              android: true),
          isNull);
      expect(hwdecFor('http://10.0.2.3:1984/api/stream.mp4?src=x',
              android: true),
          isNull);
    });

    test('other platforms keep the default, RTSP included', () {
      expect(hwdecFor('rtsp://10.0.2.3:8554/DrivewayPTZ', android: false),
          isNull);
    });
  });
}
