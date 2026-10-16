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
  'lib/screens/settings/settings_screen.dart',
  'lib/modules/controls/controls_screen.dart',
  'lib/modules/controls/climate_card.dart',
  'lib/modules/controls/light_card.dart',
  'lib/modules/cameras/cameras_screen.dart',
  'lib/modules/protect/protect_screen.dart',
  'lib/modules/mealie/mealie_screen.dart',
  'lib/modules/alarm_clock/alarm_clock_screen.dart',
  'lib/modules/webview/webview_screen.dart',
  'lib/screens/settings/update_settings.dart',
  'lib/screens/settings/wifi_settings.dart',
  'lib/screens/settings/display_settings.dart',
  'lib/plugins/calendar/calendar_settings_section.dart',
  'lib/plugins/lists/lists_settings_section.dart',
  'lib/plugins/people/people_settings_section.dart',
  'lib/plugins/display/display_plugin.dart',
  'lib/plugins/network/network_plugin.dart',
  'lib/plugins/capture/capture_plugin.dart',
  'lib/plugins/alarm_clock/alarm_clock_plugin.dart',
  'lib/plugins/sendspin/sendspin_plugin.dart',
  'lib/plugins/home_assistant/home_assistant_plugin.dart',
  'lib/plugins/mqtt/mqtt_plugin.dart',
  'lib/plugins/voice/voice_plugin.dart',
  'lib/plugins/plex/plex_plugin.dart',
  'lib/plugins/system/system_plugin.dart',
  'lib/plugins/screens_order/screens_order_plugin.dart',
  'lib/modules/webview/webview_settings_section.dart',
  'lib/modules/webview/custom_url_editor.dart',
  'lib/modules/webview/ha_dashboard_picker.dart',
  'lib/modules/calendar/calendar_screen.dart',
  'lib/modules/calendar/calendar_widgets.dart',
  'lib/modules/calendar/calendar_time_grid.dart',
  'lib/modules/calendar/calendar_month_view.dart',
  'lib/modules/lists/lists_screen.dart',
  'lib/modules/lists/lists_widgets.dart',
  'lib/modules/lists/chores_view.dart',
  'lib/modules/lists/todo_edit_dialog.dart',
  'lib/modules/alarm_clock/alarm_editor_screen.dart',
  'lib/screens/timer/timer_screen.dart',
  'lib/modules/livetv/live_tv_screen.dart',
  'lib/modules/media/cinematic/cinematic_screen.dart',
  'lib/modules/media/cinematic/top_chrome.dart',
  'lib/modules/media/cinematic/cinematic_bottom_shelf.dart',
  'lib/modules/media/cinematic/transport_row.dart',
  'lib/modules/media/cinematic/queue_lane.dart',
  'lib/modules/media/cinematic/browse_shelves.dart',
  'lib/modules/media/cinematic/mini_bar.dart',
];

final _forbidden = <RegExp>[
  RegExp(r'Colors\.(white|black)\w*'),
  RegExp(r'Color\(0x[0-9A-Fa-f]{2}(FFFFFF|000000)\)', caseSensitive: false),
  RegExp(r'0x[Ff]{2}646[Cc][Ff]{2}'),
  RegExp(r'kDialogBackground'),
  // Phase 2: status hues are roles, hex literals are roles or exempt, and
  // text on a high inkAt would be unreadable on a light theme.
  RegExp(
      r'Colors\.(red|green|amber|orange|yellow|blue|deepOrange|grey|pink|purple)\w*'),
  RegExp(r'Color\(0x'),
  RegExp(r'inkAt\(0\.(3[1-9]|[4-9])'),
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
