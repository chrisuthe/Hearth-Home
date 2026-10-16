import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../config/hub_config.dart';
import '../../services/mqtt_service.dart';
import '../framework/fields/password_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// MQTT discovery integration plugin.
///
/// Owns the `mqttBrokerUrl`, `mqttUsername`, `mqttPassword`,
/// `mqttDiscoveryPrefix` and `mqttDeviceName` HubConfig fields, and shows the
/// app-seeded `mqttDeviceId` read-only. The heavy lifting (connecting,
/// publishing discovery + state, handling inbound commands) lives in
/// [MqttService]; this plugin surfaces the connection settings and a live
/// connection-status indicator.
class MqttPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.mqtt';

  @override
  String get name => 'MQTT';

  @override
  IconData get icon => Icons.cast_connected;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 90;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.mqttBrokerUrl.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) => const _MqttPanel();

  @override
  String buildSettingsHtml(WebContext ctx) {
    final broker = const TextSettingField(
      configPath: 'mqttBrokerUrl',
      label: 'Broker URL',
      hint: 'mqtt://192.168.1.x:1883',
    ).buildHtml(ctx);
    final username = const TextSettingField(
      configPath: 'mqttUsername',
      label: 'Username',
      hint: 'Optional',
    ).buildHtml(ctx);
    final password = const PasswordSettingField(
      configPath: 'mqttPassword',
      label: 'Password',
      hint: 'Optional',
    ).buildHtml(ctx);
    final prefix = const TextSettingField(
      configPath: 'mqttDiscoveryPrefix',
      label: 'Discovery Prefix',
      hint: 'homeassistant',
    ).buildHtml(ctx);
    final name = const TextSettingField(
      configPath: 'mqttDeviceName',
      label: 'Device Name',
      hint: _nameHint,
    ).buildHtml(ctx);
    final deviceId = _escapeHtml(_deviceIdLabel(ctx.config));
    return '''
$broker$username$password$prefix$name
<div class="field">
  <label>Device ID</label>
  <div class="hint" style="font-size:13px;color:#e0e0e0">$deviceId</div>
</div>
''';
  }
}

const _nameHint = 'Defaults to the hostname, or the tablet model';

// Topics are hearth/<id>/..., so users need it to build HA automations.
String _deviceIdLabel(HubConfig config) => config.mqttDeviceId.isEmpty
    ? 'Assigned when a broker is first configured'
    : config.mqttDeviceId;

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

class _MqttPanel extends ConsumerWidget {
  const _MqttPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final config = ref.watch(hubConfigProvider);
    final status = ref.watch(mqttServiceProvider).status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusRow(
          status: status,
          configured: config.mqttBrokerUrl.isNotEmpty,
        ),
        const SizedBox(height: 8),
        const TextSettingField(
          configPath: 'mqttBrokerUrl',
          label: 'Broker URL',
          hint: 'mqtt://192.168.1.x:1883',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'mqttUsername',
          label: 'Username',
          hint: 'Optional',
        ).buildWidget(ref),
        const PasswordSettingField(
          configPath: 'mqttPassword',
          label: 'Password',
          hint: 'Optional',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'mqttDiscoveryPrefix',
          label: 'Discovery Prefix',
          hint: 'homeassistant',
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'mqttDeviceName',
          label: 'Device Name',
          hint: _nameHint,
        ).buildWidget(ref),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device ID',
                  style: TextStyle(color: c.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              SelectableText(_deviceIdLabel(config),
                  style: TextStyle(color: c.text)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final MqttStatus status;
  final bool configured;
  const _StatusRow({required this.status, required this.configured});

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final (color, label) = switch (status) {
      MqttStatus.connected => (Colors.green, 'Connected'),
      MqttStatus.connecting => (Colors.amber, 'Connecting…'),
      MqttStatus.disconnected => configured
          ? (Colors.redAccent, 'Disconnected')
          : (c.textFaint, 'Not configured'),
    };
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
      ],
    );
  }
}
