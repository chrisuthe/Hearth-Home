import 'package:flutter/material.dart';
import '../palette.dart';

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ScenePalette palette;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    // Handoff §06: on flutter-pi skip backdrop blur; compensate with +0.06
    // alpha on chipBg. We apply that bump here once.
    final bg = palette.chipBg.withValues(
      alpha: (palette.chipBg.a + 0.06).clamp(0.0, 1.0),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.chipText.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: palette.chipText.withValues(alpha: 0.75),
            fontSize: 13, fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          )),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(
            color: palette.chipText,
            fontSize: 13, fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
        ],
      ),
    );
  }
}
