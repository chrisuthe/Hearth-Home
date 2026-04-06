import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/ha_entity.dart';
import '../../services/home_assistant_service.dart';
import 'light_card.dart';
import 'climate_card.dart';

class ControlsScreen extends ConsumerStatefulWidget {
  const ControlsScreen({super.key});

  @override
  ConsumerState<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends ConsumerState<ControlsScreen> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider.select((c) => c.pinnedEntityIds));
    final ha = ref.watch(homeAssistantServiceProvider);
    // Only rebuild when a pinned entity changes, not on every HA event
    ref.listen(haEntitiesProvider, (prev, next) {
      final entity = next.valueOrNull;
      if (entity != null && config.contains(entity.entityId)) {
        setState(() {});
      }
    });

    final pinned = config;

    if (!ha.isConnected) {
      return const _EmptyState(
        icon: Icons.cloud_off,
        title: 'Not connected',
        subtitle: 'Connect Home Assistant in settings',
      );
    }

    if (pinned.isEmpty) {
      return const _EmptyState(
        icon: Icons.add_circle_outline,
        title: 'No devices pinned',
        subtitle: 'Add devices in Settings \u2192 Pinned Devices',
      );
    }

    // Filter HA entities to only pinned ones, split by domain
    final entities = pinned
        .map((id) => ha.entities[id])
        .whereType<HaEntity>()
        .toList();
    final lights = entities.where((e) => e.domain == 'light').toList();
    final climates = entities.where((e) => e.domain == 'climate').toList();
    final switches = entities.where((e) => e.domain == 'switch').toList();
    final others = entities.where((e) =>
        e.domain != 'light' && e.domain != 'climate' && e.domain != 'switch').toList();

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (lights.isNotEmpty) ...[
            const _SectionHeader(title: 'Lights'),
            const SizedBox(height: 8),
            ...lights.map((entity) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LightCard(
                    entity: entity,
                    onToggle: (value) => ha.callService(
                      domain: 'light',
                      service: value ? 'turn_on' : 'turn_off',
                      entityId: entity.entityId,
                    ),
                    onBrightnessChanged: (value) => ha.callService(
                      domain: 'light',
                      service: 'turn_on',
                      entityId: entity.entityId,
                      data: {'brightness': value.round()},
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          if (climates.isNotEmpty) ...[
            const _SectionHeader(title: 'Climate'),
            const SizedBox(height: 8),
            ...climates.map((entity) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClimateCard(
                    entity: entity,
                    onTemperatureChanged: (value) => ha.callService(
                      domain: 'climate',
                      service: 'set_temperature',
                      entityId: entity.entityId,
                      data: {'temperature': value},
                    ),
                    onModeChanged: (mode) => ha.callService(
                      domain: 'climate',
                      service: 'set_hvac_mode',
                      entityId: entity.entityId,
                      data: {'hvac_mode': mode},
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          if (switches.isNotEmpty) ...[
            const _SectionHeader(title: 'Switches'),
            const SizedBox(height: 8),
            ...switches.map((entity) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ToggleCard(
                    entity: entity,
                    onToggle: (value) => ha.callService(
                      domain: 'switch',
                      service: value ? 'turn_on' : 'turn_off',
                      entityId: entity.entityId,
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          if (others.isNotEmpty) ...[
            const _SectionHeader(title: 'Other'),
            const SizedBox(height: 8),
            ...others.map((entity) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ToggleCard(
                    entity: entity,
                    onToggle: (value) => ha.callService(
                      domain: entity.domain,
                      service: value ? 'turn_on' : 'turn_off',
                      entityId: entity.entityId,
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.4))),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.3))),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w500,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Simple toggle card for switch entities and other on/off domains.
class _ToggleCard extends StatelessWidget {
  final HaEntity entity;
  final ValueChanged<bool>? onToggle;
  const _ToggleCard({required this.entity, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: entity.isOn
            ? Colors.blue.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.power_settings_new,
              color: entity.isOn ? Colors.blue : Colors.white38, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entity.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          Switch(
            value: entity.isOn,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
