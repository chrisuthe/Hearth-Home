import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// DLNA / UPnP MediaRenderer integration.
///
/// Advertises Hearth on the LAN as a standard MediaRenderer so a UPnP/DLNA
/// *control point* can push a video URL and have it play full-screen on the
/// kiosk. Working control points: BubbleUPnP (Android), Windows "Cast to
/// Device" (Play To), Hi-Fi Cast, mconnect, Home Assistant's DLNA DMR.
///
/// NOT control points (they will never list Hearth): Plex — a DLNA *server*,
/// it exposes a library to players but can't cast to a renderer; and VLC —
/// its "Renderer" menu discovers Chromecast only, not UPnP renderers.
///
/// Owns:
///   * `dlnaEnabled`  (with side-effect: seed `dlnaUuid` on first enable)
///   * `dlnaRendererName` (the UPnP friendlyName)
///
/// `dlnaUuid` is internal — not surfaced as a field; written by the enable
/// toggle's [BoolSettingField.writeOverride] when the user first flips the
/// toggle on with an empty uuid. It mirrors how [SendspinPlugin] seeds
/// `sendspinClientId`.
///
/// Web caveat (matches Sendspin): the web portal's enable checkbox posts
/// `dlnaEnabled` directly and does NOT seed `dlnaUuid` — users must toggle once
/// on-device to seed the uuid. (`dlnaUuid` is web read-only in `/api/config`.)
class DlnaPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.dlna';

  @override
  String get name => 'DLNA Cast';

  @override
  IconData get icon => Icons.cast;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 85;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.dlnaRendererName.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoolSettingField(
          label: 'Enable DLNA Renderer',
          icon: Icons.cast,
          configPath: 'dlnaEnabled',
          disabledReason: (c) =>
              c.dlnaRendererName.isEmpty ? 'Set a renderer name first' : null,
          writeOverride: (ref, value) async {
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update((c) {
              if (value && c.dlnaUuid.isEmpty) {
                return c.copyWith(
                  dlnaEnabled: true,
                  dlnaUuid: HubConfig.generateUuid(),
                );
              }
              return c.copyWith(dlnaEnabled: value);
            });
          },
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'dlnaRendererName',
          label: 'Renderer Name',
          hint: 'Hearth',
        ).buildWidget(ref),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final enable = BoolSettingField(
      label: 'Enable DLNA Renderer',
      configPath: 'dlnaEnabled',
      disabledReason: (c) =>
          c.dlnaRendererName.isEmpty ? 'Set a renderer name first' : null,
      // No writeOverride on the web side: the auto-save helper writes the bool
      // directly and does not seed dlnaUuid. Toggle once on-device to seed it.
    );
    const rendererName = TextSettingField(
      configPath: 'dlnaRendererName',
      label: 'Renderer Name',
      hint: 'Hearth',
    );
    return enable.buildHtml(ctx) + rendererName.buildHtml(ctx);
  }
}
