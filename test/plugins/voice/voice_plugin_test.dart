import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/voice/voice_plugin.dart';

void main() {
  group('VoicePlugin', () {
    test('id, name, category, and order are correct', () {
      final p = VoicePlugin();
      expect(p.id, 'hearth.voice');
      expect(p.name, 'Voice');
      expect(p.category, PluginCategory.device);
      expect(p.order, 30);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = VoicePlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
      expect(
        p.statusFor(const HubConfig(micMuted: true, showVoiceFeedback: false)),
        PluginConfigStatus.configured,
      );
    });

    test('buildSettingsHtml renders the micMuted checkbox', () {
      final p = VoicePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      expect(html, contains('data-config-path="micMuted"'));
      expect(html, contains('Mute microphone'));
    });

    test('buildSettingsHtml renders the showVoiceFeedback checkbox', () {
      final p = VoicePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      expect(html, contains('data-config-path="showVoiceFeedback"'));
      expect(html, contains('Show voice feedback'));
    });

    test('buildSettingsHtml reflects current config values', () {
      final p = VoicePlugin();
      final muted = p.buildSettingsHtml(const WebContext(
        config: HubConfig(micMuted: true, showVoiceFeedback: false),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      // micMuted=true -> checkbox checked
      expect(
        RegExp(r'data-config-path="micMuted"[^>]*\bchecked\b').hasMatch(muted),
        isTrue,
      );
      // showVoiceFeedback=false -> checkbox NOT checked
      expect(
        RegExp(r'data-config-path="showVoiceFeedback"[^>]*\bchecked\b')
            .hasMatch(muted),
        isFalse,
      );
    });

    test('pageScreen is null', () {
      final p = VoicePlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
