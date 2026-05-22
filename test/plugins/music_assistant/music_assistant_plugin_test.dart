import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/music_assistant/music_assistant_plugin.dart';

void main() {
  group('MusicAssistantPlugin', () {
    test('id and category are correct', () {
      final p = MusicAssistantPlugin();
      expect(p.id, 'hearth.music_assistant');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns configured when URL, token, and zone are set', () {
      final p = MusicAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          musicAssistantUrl: 'http://192.168.1.5:8095',
          musicAssistantToken: 'tok',
          defaultMusicZone: 'media_player.living_room',
        )),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns needsSetup when URL is empty', () {
      final p = MusicAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          musicAssistantToken: 'tok',
          defaultMusicZone: 'media_player.living_room',
        )),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns needsSetup when token is empty', () {
      final p = MusicAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          musicAssistantUrl: 'http://192.168.1.5:8095',
          defaultMusicZone: 'media_player.living_room',
        )),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns partial when URL+token set but zone is null', () {
      final p = MusicAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          musicAssistantUrl: 'http://192.168.1.5:8095',
          musicAssistantToken: 'tok',
        )),
        PluginConfigStatus.partial,
      );
    });

    test('statusFor returns partial when URL+token set but zone is empty', () {
      final p = MusicAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          musicAssistantUrl: 'http://192.168.1.5:8095',
          musicAssistantToken: 'tok',
          defaultMusicZone: '',
        )),
        PluginConfigStatus.partial,
      );
    });

    test('buildSettingsHtml emits URL, token, and zone inputs', () {
      final p = MusicAssistantPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          musicAssistantUrl: 'http://192.168.1.5:8095',
          musicAssistantToken: 'tok-value',
          defaultMusicZone: 'media_player.living_room',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.music_assistant',
      ));
      expect(html, contains('Music Assistant URL'));
      expect(html, contains('value="http://192.168.1.5:8095"'));
      expect(html, contains('data-config-path="musicAssistantUrl"'));
      expect(html, contains('Music Assistant Token'));
      expect(html, contains('type="password"'));
      expect(html, contains('data-config-path="musicAssistantToken"'));
      expect(html, contains('Default Music Zone'));
      expect(html, contains('value="media_player.living_room"'));
      expect(html, contains('data-config-path="defaultMusicZone"'));
    });

    test('pageScreen is null (Media module migration deferred)', () {
      final p = MusicAssistantPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
