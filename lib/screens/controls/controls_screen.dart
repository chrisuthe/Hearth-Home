import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ha_entity.dart';
import 'light_card.dart';
import 'climate_card.dart';

/// Device controls screen -- room-grouped lights and climate entities.
///
/// Pulls HA entities from Riverpod providers (currently placeholder empty
/// lists) and groups them by domain. Shows a friendly empty state when
/// Home Assistant isn't connected yet. Each entity type gets its own
/// specialized card widget for optimal touch interaction.
class ControlsScreen extends ConsumerWidget {
  const ControlsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder entity lists -- will be wired to HA WebSocket provider
    final List<HaEntity> lights = [];
    final List<HaEntity> climates = [];

    final hasDevices = lights.isNotEmpty || climates.isNotEmpty;

    if (!hasDevices) {
      return Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No devices',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect Home Assistant in settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Lights section -- grouped under a header
        if (lights.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Lights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          ...lights.map(
            (entity) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LightCard(
                entity: entity,
                // Toggle and brightness callbacks will be wired to HA service calls
                onToggle: (value) {},
                onBrightnessChanged: (value) {},
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Climate section -- thermostats and HVAC units
        if (climates.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Climate',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          ...climates.map(
            (entity) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClimateCard(
                entity: entity,
                // Temperature and mode callbacks will be wired to HA service calls
                onTemperatureChanged: (value) {},
                onModeChanged: (mode) {},
              ),
            ),
          ),
        ],
      ],
    );
  }
}
