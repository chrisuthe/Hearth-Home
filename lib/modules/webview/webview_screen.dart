import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app/scale/hearth_scale.dart';
import '../../config/hub_config.dart';
import '../../config/webview_config.dart';
import 'ha_token_injector.dart';
import 'webview_geometry.dart';
import 'webview_session.dart';
import 'webview_session_pool.dart';

/// Maps a tap at [local] (in display-box pixels) back to webview viewport
/// pixels, inverting the `BoxFit.contain` transform the [FittedBox] applies
/// when a [render]-sized frame is painted inside a [box]-sized area.
///
/// `contain` scales the frame by the smaller of the two axis ratios and
/// **centres** it, so a frame whose aspect differs from the box gets letterbox
/// bars. The mapping must remove that centring offset before un-scaling — e.g.
/// a 1920x1080 webview in a 1184x864 box fits to 1184x666 with 99px bars top
/// and bottom; without subtracting the 99px a tap lands ~160px too low.
Offset webviewViewportOffset(Offset local, Size box, Size render) {
  if (render.width == 0 || render.height == 0) return local;
  final fitScale = (box.width / render.width) < (box.height / render.height)
      ? box.width / render.width
      : box.height / render.height;
  final offsetX = (box.width - render.width * fitScale) / 2;
  final offsetY = (box.height - render.height * fitScale) / 2;
  return Offset(
    (local.dx - offsetX) / fitScale,
    (local.dy - offsetY) / fitScale,
  );
}

/// Renders a single configured webview into HubShell's PageView.
///
/// Resolves a [WebviewSession] from the pool (warm-cache), renders the
/// underlying video texture, and shows Hearth-styled LOADING / ERROR
/// placeholders during transitions.
///
/// Touch input and idle-suspend wiring are added in later tasks
/// (Task 14: Touch input mapping, Task 16: Idle-suspend wiring).
class WebviewScreen extends ConsumerStatefulWidget {
  final WebviewConfig config;

  const WebviewScreen({super.key, required this.config});

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen> {
  WebviewSession? _session;
  Size? _lastRenderPx;

  /// Resolves (or re-resolves) the session for this webview, applying the
  /// HA-token injector when applicable. Safe to call repeatedly: it only swaps
  /// the session when the pool hands back a different instance (e.g. the HA
  /// token changed, so [WebviewSessionPool.getOrCreate] rebuilt the session
  /// with the new document-start script).
  void _ensureSession(Size? renderPx) {
    final config = ref.read(hubConfigProvider);
    final injector = injectorForWebview(
      widget.config,
      haUrl: config.haUrl,
      haToken: config.haToken,
      darkMode: config.haDashboardDarkMode,
    );
    final pool = ref.read(webviewSessionPoolProvider);
    final session = pool.getOrCreate(
      widget.config.url,
      initScript: injector?.script,
      initScriptAllowOrigin: injector?.allowOrigin,
      renderSize: renderPx,
    );
    if (identical(session, _session)) return;
    _session?.removeListener(_onSessionChange);
    setState(() => _session = session);
    session.addListener(_onSessionChange);
  }

  void _onSessionChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the session when the HA URL/token changes in Settings so the
    // new document-start injector takes effect (only matters for HA
    // dashboards; custom URLs derive a null injector either way).
    ref.listen<(String, String, bool)>(
      hubConfigProvider
          .select((c) => (c.haUrl, c.haToken, c.haDashboardDarkMode)),
      (_, _) => _ensureSession(_lastRenderPx),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final renderPx = webviewRenderPx(
        Size(constraints.maxWidth, constraints.maxHeight),
        MediaQuery.devicePixelRatioOf(context),
        ref.read(uiScaleProvider),
      );
      final last = _lastRenderPx;
      if (last == null ||
          (renderPx.width - last.width).abs() > 2 ||
          (renderPx.height - last.height).abs() > 2) {
        _lastRenderPx = renderPx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureSession(renderPx);
        });
      }

      final session = _session;
      if (session == null) {
        return _Placeholder.loading(config: widget.config);
      }
      switch (session.state) {
        case WebviewSessionState.loading:
          return _Placeholder.loading(config: widget.config);
        case WebviewSessionState.error:
          return _Placeholder.error(
            config: widget.config,
            message: session.lastError ?? 'Unknown error',
            onRetry: () => session.reload(),
          );
        case WebviewSessionState.playing:
        case WebviewSessionState.paused:
          final controller = session.controller;
          if (controller == null || !controller.value.isInitialized) {
            return _Placeholder.loading(config: widget.config);
          }
          return _TouchableWebviewView(
            session: session,
            controller: controller,
            size: Size(constraints.maxWidth, constraints.maxHeight),
          );
      }
    });
  }
}

class _Placeholder extends StatelessWidget {
  final WebviewConfig config;
  final bool isError;
  final String? message;
  final VoidCallback? onRetry;

  const _Placeholder.loading({required this.config})
      : isError = false,
        message = null,
        onRetry = null;

  const _Placeholder.error({
    required this.config,
    required String this.message,
    required VoidCallback this.onRetry,
  }) : isError = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : config.icon,
            color: isError ? Colors.redAccent : Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            isError ? 'Reconnecting to ${config.name}…' : config.name,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          if (isError && message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const CircularProgressIndicator(color: Color(0xFF646CFF)),
          ],
        ],
      ),
    );
  }
}

class _TouchableWebviewView extends StatefulWidget {
  final WebviewSession session;
  final VideoPlayerController controller;
  final Size size;

  const _TouchableWebviewView({
    required this.session,
    required this.controller,
    required this.size,
  });

  @override
  State<_TouchableWebviewView> createState() => _TouchableWebviewViewState();
}

class _TouchableWebviewViewState extends State<_TouchableWebviewView> {
  // Position recorded at tap-down; we use it later if the arena commits to
  // tap (in [onTap]) so the press/release pair we synthesise lands at the
  // user's finger, not the centre of the screen.
  Offset? _tapDownPos;
  // True iff the current vertical drag started in the central area (i.e.
  // outside Hearth's top/bottom 80px edge zones). Only those drags are
  // forwarded to the webview as scroll; edge-zone drags pass through to
  // HubShell's edge-swipe handlers.
  bool _vertDragClaimed = false;

  // Hearth's edge-swipe zones occupy the top/bottom 80px of the display.
  // Mirror that here so vertical drags starting in those bands don't
  // get swallowed by the webview.
  static const double _edgeBand = 80;

  // Maps local Flutter pixel to wpe viewport coordinates. VideoPlayer renders
  // via BoxFit.contain inside [size]; map back to the native webview frame.
  Offset _toViewport(Offset local) =>
      webviewViewportOffset(local, widget.size, widget.controller.value.size);

  void _resumeIfNeeded() {
    if (widget.session.state == WebviewSessionState.paused) {
      widget.session.setPaused(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Two deliberate omissions:
      //   * no `onHorizontalDragUpdate` — horizontal drags belong to the
      //     outer PageView for page-to-page navigation.
      //   * no `onTapDown`/`onTapUp` that immediately fire press/release —
      //     emitting the press before the arena commits the gesture would
      //     leak a stuck-press to HA if the user later starts a swipe.
      //     Instead we use `onTap`, which fires only after the gesture
      //     arena has confirmed a tap (not a drag, not a long-press).
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        // Record position; don't emit to the webview yet. The press is
        // sent in [onTap] only after the arena has committed.
        _tapDownPos = d.localPosition;
        _resumeIfNeeded();
      },
      onTapCancel: () {
        // Arena decided this wasn't a tap (became a drag, etc.). Nothing
        // to do — we never sent a press, so there's no release to issue.
        _tapDownPos = null;
      },
      onTap: () async {
        final p = _tapDownPos;
        _tapDownPos = null;
        if (p == null) return;
        final viewport = _toViewport(p);
        await widget.session.sendPointerDown(viewport);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await widget.session.sendPointerUp(viewport);
      },
      onLongPressStart: (d) {
        _resumeIfNeeded();
        widget.session.sendLongPressStart(_toViewport(d.localPosition));
      },
      onLongPressEnd: (d) {
        widget.session.sendLongPressEnd(_toViewport(d.localPosition));
      },
      onVerticalDragStart: (d) {
        final y = d.localPosition.dy;
        // Decline to claim drags that begin in the edge bands — let
        // HubShell's edge-swipe zones handle them (for menu access).
        _vertDragClaimed = y >= _edgeBand &&
            y <= widget.size.height - _edgeBand;
        if (_vertDragClaimed) _resumeIfNeeded();
      },
      onVerticalDragUpdate: (d) {
        if (!_vertDragClaimed) return;
        widget.session.sendScroll(
          _toViewport(d.localPosition),
          0,
          d.delta.dy, // drag down scrolls the page down (matches expectation)
        );
      },
      onVerticalDragEnd: (_) {
        _vertDragClaimed = false;
      },
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: widget.controller.value.size.width,
          height: widget.controller.value.size.height,
          child: VideoPlayer(widget.controller),
        ),
      ),
    );
  }
}
