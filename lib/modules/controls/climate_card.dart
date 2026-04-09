import 'package:flutter/material.dart';
import '../../models/ha_entity.dart';

/// Card for controlling a climate/thermostat entity.
///
/// Shows the current temperature, target temperature with +/- adjustment
/// buttons, and HVAC mode selector chips. The accent color shifts between
/// orange (heating) and blue (cooling) to give an instant visual cue of
/// what the system is doing.
class ClimateCard extends StatelessWidget {
  final HaEntity entity;
  final ValueChanged<double>? onTemperatureChanged;
  final ValueChanged<String>? onModeChanged;

  const ClimateCard({
    super.key,
    required this.entity,
    this.onTemperatureChanged,
    this.onModeChanged,
  });

  /// Maps HVAC mode strings to accent colors for visual feedback.
  Color _modeColor(String? mode) {
    switch (mode) {
      case 'heat':
        return Colors.orange;
      case 'cool':
        return Colors.blue;
      case 'heat_cool':
      case 'auto':
        return Colors.amber;
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTemp = entity.currentTemperature;
    final targetTemp = entity.temperature ?? 72;
    final mode = entity.hvacMode ?? entity.state;
    final accentColor = _modeColor(mode);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: entity.isOff
            ? Colors.white.withValues(alpha: 0.05)
            : accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon, name, current temperature reading
          Row(
            children: [
              Icon(Icons.thermostat, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entity.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (currentTemp != null)
                Text(
                  '${currentTemp.round()}\u00B0',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Target temperature with +/- buttons for quick adjustment
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.white54,
                onPressed: onTemperatureChanged != null
                    ? () => onTemperatureChanged!(targetTemp - 1)
                    : null,
              ),
              Text(
                '${targetTemp.round()}\u00B0',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: accentColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: Colors.white54,
                onPressed: onTemperatureChanged != null
                    ? () => onTemperatureChanged!(targetTemp + 1)
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // HVAC mode selector chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final m in ['heat', 'cool', 'auto', 'off'])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      m[0].toUpperCase() + m.substring(1),
                      style: TextStyle(
                        fontSize: 11,
                        color: mode == m ? Colors.black : Colors.white70,
                      ),
                    ),
                    selected: mode == m,
                    onSelected: onModeChanged != null
                        ? (_) => onModeChanged!(m)
                        : null,
                    selectedColor: _modeColor(m),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
