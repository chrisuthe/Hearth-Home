import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/modules/webview/webview_session.dart';
import 'package:hearth/modules/webview/webview_session_pool.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

const _webview = WebviewConfig(
  id: 'webview:custom:energy',
  url: 'https://example.invalid/energy',
  name: 'Whole-Home Energy & Solar Production Dashboard (Lovelace)',
  iconCodePoint: 0xe1a7,
  source: WebviewSource.customUrl,
  order: 0,
);

/// Hands out plugin-free sessions and remembers the size each was asked for.
class _RecordingPool extends WebviewSessionPool {
  _RecordingPool() : super(sessionFactory: WebviewSession.testing);

  final sizes = <Size?>[];
  WebviewSession? last;

  @override
  Future<WebviewSession> getOrCreate(
    String url, {
    String? initScript,
    String? initScriptAllowOrigin,
    Size? renderSize,
  }) async {
    sizes.add(renderSize);
    return last = await super.getOrCreate(
      url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderSize: renderSize,
    );
  }
}

void main() {
  // The platform texture cannot exist under test, so this covers the states
  // drawn around it. Built via the module synthesised from config, as
  // HubShell does.
  Widget screen() => modulesForConfig(const HubConfig(webviews: [_webview]))
      .firstWhere((m) => m.id == _webview.id)
      .buildScreen(isActive: true);

  testLayouts('webview loading placeholder', (tester, canvas) async {
    final pool = _RecordingPool();
    await pumpModule(tester, screen(), overrides: [
      webviewSessionPoolProvider.overrideWithValue(pool),
    ]);
    expect(find.text(_webview.name), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The frame is requested at the box it fills, so a portrait canvas asks
    // WPE for a portrait page instead of letterboxing a landscape one.
    expect(pool.sizes.last, canvas);
  });

  testLayouts('webview error placeholder', (tester, canvas) async {
    final pool = _RecordingPool();
    await pumpModule(tester, screen(), overrides: [
      webviewSessionPoolProvider.overrideWithValue(pool),
    ]);
    pool.last!.notifyError(
        'GStreamer pipeline error: wpevideosrc0 could not negotiate caps '
        'video/x-raw(memory:GLMemory), format=RGBA, width=864, height=1184 '
        'with the downstream element');
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
