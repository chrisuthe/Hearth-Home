import 'package:flutter/material.dart';
import '../../app/tokens/tokens.dart';
import '../../models/ha_entity.dart';
import '../../app/theme/hearth_colors.dart';

/// Card for controlling a single light entity.
///
/// Shows toggle, name, and (when on) a brightness slider.
/// The warm amber accent when lit mirrors the physical warmth of the light.
class LightCard extends StatelessWidget {
  final HaEntity entity;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<double>? onBrightnessChanged;

  const LightCard({
    super.key,
    required this.entity,
    this.onToggle,
    this.onBrightnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    final brightness = entity.brightness;
    final brightnessPercent =
        brightness != null ? (brightness / 255 * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(HearthSpacing.x4),
      decoration: BoxDecoration(
        color: entity.isOn
            ? Colors.amber.withValues(alpha: 0.12)
            : c.inkAt(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: entity.isOn ? Colors.amber : c.textFaint,
                size: HearthIcon.sm,
              ),
              const SizedBox(width: HearthSpacing.x2),
              Expanded(
                child: Text(
                  entity.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                value: entity.isOn,
                onChanged: onToggle,
                activeColor: Colors.amber,
              ),
            ],
          ),
          if (entity.isOn && brightness != null) ...[
            const SizedBox(height: HearthSpacing.x2),
            Row(
              children: [
                Icon(Icons.brightness_low, size: HearthIcon.xs, color: c.textFaint),
                Expanded(
                  child: Slider(
                    value: brightness.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: onBrightnessChanged,
                    activeColor: Colors.amber,
                    inactiveColor: c.inkAt(0.1),
                  ),
                ),
                Text(
                  '$brightnessPercent%',
                  style: TextStyle(fontSize: HearthFont.caption, color: c.textMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
