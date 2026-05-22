import 'package:flutter/material.dart';

import '../app/app.dart' show kDialogBackground;
import '../app/tokens/tokens.dart';
import '../services/timezone_service.dart';

/// Searchable timezone picker dialog.
///
/// Shows common timezones at the top, then all available timezones
/// filtered by the search query. Selecting "System default" clears
/// the timezone config (empty string).
///
/// Returns the selected IANA timezone string (or empty string for system
/// default) via `Navigator.pop`. Returns `null` on cancel.
class TimezonePickerDialog extends StatefulWidget {
  final List<String> timezones;
  final String currentTimezone;

  const TimezonePickerDialog({
    super.key,
    required this.timezones,
    required this.currentTimezone,
  });

  @override
  State<TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<TimezonePickerDialog> {
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build filtered list: common timezones first, then the rest.
    final lowerFilter = _filter.toLowerCase();
    final common = TimezoneService.commonTimezones
        .where((tz) => lowerFilter.isEmpty || tz.toLowerCase().contains(lowerFilter))
        .toList();
    final rest = widget.timezones
        .where((tz) => !TimezoneService.commonTimezones.contains(tz))
        .where((tz) => lowerFilter.isEmpty || tz.toLowerCase().contains(lowerFilter))
        .toList();

    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: const Text('Timezone'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search timezones...',
                prefixIcon: Icon(Icons.search, size: HearthIcon.sm),
                isDense: true,
              ),
              autofocus: true,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: HearthSpacing.x2),
            Expanded(
              child: ListView(
                children: [
                  // "System default" option to clear the setting.
                  if (lowerFilter.isEmpty || 'system default'.contains(lowerFilter))
                    _buildTile('', 'System default'),
                  if (common.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: HearthSpacing.x1, top: HearthSpacing.x2, bottom: HearthSpacing.x1),
                      child: Text(
                        'Common',
                        style: TextStyle(
                          fontSize: HearthFont.caption,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  ...common.map((tz) => _buildTile(tz, tz)),
                  if (rest.isNotEmpty && lowerFilter.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: HearthSpacing.x1, top: HearthSpacing.x3, bottom: HearthSpacing.x1),
                      child: Text(
                        'All timezones',
                        style: TextStyle(
                          fontSize: HearthFont.caption,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  ...rest.map((tz) => _buildTile(tz, tz)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildTile(String value, String label) {
    final isSelected = value == widget.currentTimezone;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: isSelected
          ? const Icon(Icons.check, size: HearthIcon.xs, color: Colors.amber)
          : const SizedBox(width: HearthIcon.xs),
      title: Text(label, style: const TextStyle(fontSize: HearthFont.body)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}
