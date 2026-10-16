import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files already moved onto `HearthColors` roles. Later tasks append to it.
const kThemedFiles = <String>[
  'lib/app/hub_shell.dart',
  'lib/app/page_indicator.dart',
  'lib/widgets/toast_overlay.dart',
  'lib/widgets/voice_pill.dart',
  'lib/plugins/framework/plugin_sidebar.dart',
  'lib/plugins/framework/plugin_panel.dart',
  'lib/plugins/framework/list_section.dart',
  'lib/plugins/framework/fields/bool_setting_field.dart',
  'lib/plugins/framework/fields/text_setting_field.dart',
  'lib/plugins/framework/fields/select_setting_field.dart',
  'lib/plugins/framework/fields/slider_setting_field.dart',
  'lib/plugins/framework/fields/password_setting_field.dart',
  'lib/widgets/module_reorder_list.dart',
  'lib/widgets/module_placement_tile.dart',
  'lib/widgets/entity_picker_dialog.dart',
  'lib/widgets/timezone_picker_dialog.dart',
  'lib/widgets/person_avatar.dart',
];

final _forbidden = <RegExp>[
  RegExp(r'Colors\.(white|black)\w*'),
  RegExp(r'Color\(0x[0-9A-Fa-f]{2}(FFFFFF|000000)\)', caseSensitive: false),
  RegExp(r'0x[Ff]{2}646[Cc][Ff]{2}'),
  RegExp(r'kDialogBackground'),
];

void main() {
  test('themed files carry no hardcoded theme literals', () {
    final offenders = <String>[];
    for (final path in kThemedFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('theme-exempt:')) continue;
        if (_forbidden.any((r) => r.hasMatch(line))) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '\n${offenders.join('\n')}');
  });
}
